#!/usr/bin/env python3
"""Benchmark an OpenAI-compatible inference endpoint.

Measures TTFT, single-stream throughput, concurrent throughput, and runs
a drift-narration quality test.  ALL measurements use streaming — the
OAuth proxy on the Route times out non-streaming requests before the
model finishes generating.

Outputs a markdown table suitable for pasting into a GitHub issue.

Usage:
    INFERENCE_TOKEN=eyJ... python3 utilities/benchmark-inference.py \
        --url  https://granite-3-3-8b-instruct-granite-serving.apps.example.com \
        --model granite-3-3-8b-instruct

Requires only ``requests`` (ships with Ansible / Fedora).
"""

from __future__ import annotations

import argparse
import json
import os
import statistics
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Any

import requests

requests.packages.urllib3.disable_warnings()  # type: ignore[attr-defined]

RETRIES = 3
RETRY_DELAY = 5


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _headers(token: str) -> dict[str, str]:
    return {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }


def _stream_request(endpoint: str, body: dict, token: str,
                    timeout: int = 120) -> requests.Response:
    """POST with streaming, retry on transient 5xx."""
    body = {**body, "stream": True, "stream_options": {"include_usage": True}}
    for attempt in range(RETRIES):
        resp = requests.post(endpoint, json=body, headers=_headers(token),
                             verify=False, stream=True, timeout=timeout)
        if resp.status_code < 500 or attempt == RETRIES - 1:
            resp.raise_for_status()
            return resp
        print(f"  Retry {attempt + 1}/{RETRIES} after {resp.status_code}...",
              file=sys.stderr)
        resp.close()
        time.sleep(RETRY_DELAY * (attempt + 1))
    return resp  # unreachable


def _consume_stream(resp: requests.Response) -> dict[str, Any]:
    """Read a streaming response, return timing and content."""
    t_first: float | None = None
    t_last: float = 0.0
    token_count = 0
    content_parts: list[str] = []
    usage: dict[str, int] = {}

    for line in resp.iter_lines():
        text = line.decode("utf-8", errors="replace") if isinstance(line, bytes) else line
        if not text.startswith("data: ") or text == "data: [DONE]":
            continue
        chunk = json.loads(text[6:])
        if chunk.get("usage"):
            usage = chunk["usage"]
        choices = chunk.get("choices", [])
        if not choices:
            continue
        delta = choices[0].get("delta", {})
        content = delta.get("content", "")
        if content:
            now = time.perf_counter()
            if t_first is None:
                t_first = now
            t_last = now
            token_count += 1
            content_parts.append(content)

    resp.close()
    completion_tokens = usage.get("completion_tokens", token_count)
    return {
        "t_first": t_first,
        "t_last": t_last,
        "token_count": token_count,
        "completion_tokens": completion_tokens,
        "content": "".join(content_parts),
    }


# ---------------------------------------------------------------------------
# TTFT — time to first token
# ---------------------------------------------------------------------------

def measure_ttft(url: str, token: str, model: str, n: int = 20) -> dict[str, Any]:
    endpoint = f"{url}/v1/chat/completions"
    body = {
        "model": model,
        "messages": [{"role": "user", "content": "Explain why configuration drift matters."}],
        "max_tokens": 32,
        "temperature": 0,
        "ignore_eos": True,
    }
    ttfts: list[float] = []

    for _ in range(n):
        t0 = time.perf_counter()
        resp = _stream_request(endpoint, body, token, timeout=60)
        stream = _consume_stream(resp)
        if stream["t_first"] is not None:
            ttfts.append((stream["t_first"] - t0) * 1000)

    return {
        "n": len(ttfts),
        "p50_ms": round(statistics.median(ttfts), 1),
        "p95_ms": round(sorted(ttfts)[int(len(ttfts) * 0.95) - 1], 1) if len(ttfts) >= 20 else None,
        "min_ms": round(min(ttfts), 1),
        "max_ms": round(max(ttfts), 1),
    }


# ---------------------------------------------------------------------------
# Single-stream throughput
# ---------------------------------------------------------------------------

def measure_single_stream(url: str, token: str, model: str,
                          max_tokens_list: list[int] | None = None) -> list[dict[str, Any]]:
    if max_tokens_list is None:
        max_tokens_list = [128, 256, 512]
    endpoint = f"{url}/v1/chat/completions"
    results: list[dict[str, Any]] = []

    for mt in max_tokens_list:
        body = {
            "model": model,
            "messages": [{"role": "user",
                          "content": "Explain why configuration drift matters to an operations team."}],
            "max_tokens": mt,
            "temperature": 0,
            "ignore_eos": True,
        }
        t0 = time.perf_counter()
        resp = _stream_request(endpoint, body, token, timeout=120)
        stream = _consume_stream(resp)
        elapsed = time.perf_counter() - t0
        results.append({
            "max_tokens": mt,
            "completion_tokens": stream["completion_tokens"],
            "elapsed_s": round(elapsed, 2),
            "tok_per_s": round(stream["completion_tokens"] / elapsed, 1),
        })

    return results


# ---------------------------------------------------------------------------
# Concurrent throughput
# ---------------------------------------------------------------------------

def _single_streaming_request(url: str, token: str, model: str,
                              max_tokens: int) -> dict[str, Any]:
    endpoint = f"{url}/v1/chat/completions"
    body = {
        "model": model,
        "messages": [{"role": "user",
                      "content": "Explain why configuration drift matters to an operations team."}],
        "max_tokens": max_tokens,
        "temperature": 0,
        "ignore_eos": True,
    }
    t0 = time.perf_counter()
    resp = _stream_request(endpoint, body, token, timeout=180)
    stream = _consume_stream(resp)
    elapsed = time.perf_counter() - t0
    return {
        "completion_tokens": stream["completion_tokens"],
        "elapsed_s": elapsed,
    }


def measure_concurrent(url: str, token: str, model: str,
                       concurrency_levels: list[int] | None = None,
                       max_tokens: int = 256) -> list[dict[str, Any]]:
    if concurrency_levels is None:
        concurrency_levels = [4, 8, 16]
    results: list[dict[str, Any]] = []

    for c in concurrency_levels:
        wall_start = time.perf_counter()
        with ThreadPoolExecutor(max_workers=c) as pool:
            futures = [pool.submit(_single_streaming_request, url, token, model, max_tokens)
                       for _ in range(c)]
            sub_results = [f.result() for f in as_completed(futures)]
        wall_elapsed = time.perf_counter() - wall_start
        total_tokens = sum(r["completion_tokens"] for r in sub_results)

        results.append({
            "concurrency": c,
            "total_tokens": total_tokens,
            "wall_s": round(wall_elapsed, 2),
            "aggregate_tok_per_s": round(total_tokens / wall_elapsed, 1),
            "per_stream_tok_per_s": round(total_tokens / wall_elapsed / c, 1),
        })

    return results


# ---------------------------------------------------------------------------
# Drift narration quality test
# ---------------------------------------------------------------------------

DRIFT_PAYLOAD = json.dumps([
    {"field": "os.kernel", "severity": "expected",
     "was": "5.14.0-427.13.1.el9_4", "now": "5.14.0-503.38.1.el9_5"},
    {"field": "os.version", "severity": "expected",
     "was": "9.4", "now": "9.5"},
    {"field": "uptime.last_boot", "severity": "expected",
     "was": "2026-09-02 04:11 UTC", "now": "2026-09-18 06:32 UTC"},
    {"field": "resources.memory_mb", "severity": "investigate",
     "was": 3919, "now": 7856},
    {"field": "network.dns_servers", "severity": "investigate",
     "was": ["10.0.0.2"], "now": ["10.0.0.2", "8.8.8.8"]},
])

DRIFT_SYSTEM_PROMPT = (
    "You are a systems administrator reviewing a drift report for a managed "
    "host. Each item has a field name, the previous value (was), the current "
    "value (now), and a severity that Ansible has already assigned "
    "(investigate, notable, or expected).\n\n"
    "DO NOT reassign severity — it is authoritative.\n\n"
    "For each changed field, explain in one or two sentences: "
    "(1) why this change matters in a production environment, and "
    "(2) what an operator should do next.\n\n"
    "Keep it concise — this appears in a job log. Use plain language, not "
    "jargon. Address the operator directly."
)


def measure_drift_narration(url: str, token: str, model: str) -> dict[str, Any]:
    endpoint = f"{url}/v1/chat/completions"
    body = {
        "model": model,
        "messages": [
            {"role": "system", "content": DRIFT_SYSTEM_PROMPT},
            {"role": "user", "content": f"Host: web-lnx-1. Drift report: {DRIFT_PAYLOAD}"},
        ],
        "max_tokens": 512,
        "temperature": 0,
    }

    t0 = time.perf_counter()
    resp = _stream_request(endpoint, body, token, timeout=60)
    stream = _consume_stream(resp)
    elapsed = time.perf_counter() - t0
    content = stream["content"]
    completion_tokens = stream["completion_tokens"]

    field_keywords = {
        "os.kernel": ["kernel"],
        "os.version": ["version", "os version"],
        "uptime.last_boot": ["last boot", "uptime", "reboot"],
        "resources.memory_mb": ["memory", "ram", "3919", "7856"],
        "network.dns_servers": ["dns", "8.8.8.8", "name resolution"],
    }
    fields_mentioned = []
    for field, keywords in field_keywords.items():
        if any(kw in content.lower() for kw in keywords):
            fields_mentioned.append(field)

    return {
        "fields_mentioned": len(fields_mentioned),
        "fields_total": 5,
        "fields_detail": fields_mentioned,
        "completion_tokens": completion_tokens,
        "elapsed_s": round(elapsed, 2),
        "tok_per_s": round(completion_tokens / elapsed, 1),
        "content": content,
    }


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

def print_results(model: str, ttft: dict, single: list, concurrent: list,
                  drift: dict) -> None:
    print(f"\n## Benchmark: `{model}`\n")

    print("### TTFT (time to first token)\n")
    print("| Stat | Value |")
    print("|---|---|")
    print(f"| n | {ttft['n']} |")
    print(f"| p50 | {ttft['p50_ms']} ms |")
    if ttft.get("p95_ms") is not None:
        print(f"| p95 | {ttft['p95_ms']} ms |")
    print(f"| min | {ttft['min_ms']} ms |")
    print(f"| max | {ttft['max_ms']} ms |")

    print("\n### Single-stream throughput\n")
    print("| max_tokens | completion_tokens | elapsed (s) | tok/s |")
    print("|---|---|---|---|")
    for r in single:
        print(f"| {r['max_tokens']} | {r['completion_tokens']} | {r['elapsed_s']} | {r['tok_per_s']} |")

    if concurrent:
        print("\n### Concurrent throughput (256 tokens per stream)\n")
        print("| concurrency | total tokens | wall (s) | aggregate tok/s | per-stream tok/s |")
        print("|---|---|---|---|---|")
        for r in concurrent:
            print(f"| {r['concurrency']} | {r['total_tokens']} | {r['wall_s']} | {r['aggregate_tok_per_s']} | {r['per_stream_tok_per_s']} |")

    print("\n### Drift narration test\n")
    print(f"Fields reported: **{drift['fields_mentioned']}/{drift['fields_total']}**"
          f" ({', '.join(drift['fields_detail'])})")
    print(f"\nTokens: {drift['completion_tokens']}, "
          f"elapsed: {drift['elapsed_s']} s, "
          f"throughput: {drift['tok_per_s']} tok/s\n")
    print("**Narration:**\n")
    print(f"> {drift['content'].replace(chr(10), chr(10) + '> ')}")
    print()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Benchmark an inference endpoint")
    parser.add_argument("--url", required=True, help="Base URL (https://route-host)")
    parser.add_argument("--token", default=None,
                        help="Bearer token (prefer INFERENCE_TOKEN env var)")
    parser.add_argument("--model", required=True, help="Served model name")
    parser.add_argument("--ttft-n", type=int, default=20, help="TTFT sample count")
    parser.add_argument("--skip-concurrent", action="store_true",
                        help="Skip concurrent tests (faster iteration)")
    args = parser.parse_args()

    token = args.token or os.environ.get("INFERENCE_TOKEN", "")
    if not token:
        print("Error: pass --token or set INFERENCE_TOKEN", file=sys.stderr)
        sys.exit(1)
    args.token = token

    url = args.url.rstrip("/")

    print(f"Verifying endpoint: {url}/v1/models", file=sys.stderr)
    resp = requests.get(f"{url}/v1/models", headers=_headers(args.token),
                        verify=False, timeout=30)
    resp.raise_for_status()
    models = resp.json()
    print(f"Models available: {[m['id'] for m in models.get('data', [])]}", file=sys.stderr)

    print(f"\nRunning TTFT (n={args.ttft_n})...", file=sys.stderr)
    ttft = measure_ttft(url, args.token, args.model, n=args.ttft_n)

    print("Running single-stream throughput...", file=sys.stderr)
    single = measure_single_stream(url, args.token, args.model)

    if args.skip_concurrent:
        concurrent: list[dict[str, Any]] = []
        print("Skipping concurrent tests.", file=sys.stderr)
    else:
        print("Running concurrent throughput...", file=sys.stderr)
        concurrent = measure_concurrent(url, args.token, args.model)

    print("Running drift narration test...", file=sys.stderr)
    drift = measure_drift_narration(url, args.token, args.model)

    print_results(args.model, ttft, single, concurrent, drift)

    summary = {
        "model": args.model,
        "ttft": ttft,
        "single_stream": single,
        "concurrent": concurrent,
        "drift": {k: v for k, v in drift.items() if k != "content"},
    }
    print(f"\n::JSON::{json.dumps(summary)}", file=sys.stderr)


if __name__ == "__main__":
    main()
