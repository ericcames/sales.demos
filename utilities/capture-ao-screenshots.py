#!/usr/bin/env python3
"""Capture Automation Orchestrator screenshots for the demo docs.

WHY THIS EXISTS
    The AO run sheet in sales.demos-docs embeds screenshots of the login page,
    integrations, and workflow builder.  AO is a React SPA that needs JavaScript
    to render, so a headless browser with playwright is required.  This script
    automates the capture so screenshots can be refreshed when the environment
    changes.

WHAT IT CAPTURES
    1. AO login page (pre-auth — SSO button visible)
    2. Integrations list (authenticated)
    3. AAP integration detail (authenticated)
    4. Workflow builder canvas (authenticated)

    Items that need a live rehearsal and CANNOT be automated:
    - Canvas with a completed workflow (requires manual drag-and-drop)
    - Execution views (requires running a workflow)
    - Approval gate (requires a pending approval)

PREREQUISITES
    pip install playwright && playwright install chromium

USAGE
    python3 utilities/capture-ao-screenshots.py <env>

    <env> is 'sandbox' or 'demo'.  The script reads the AO Route from the
    cluster via the kubeconfig, and the admin password from the vault.

    Screenshots are written to ../sales.demos-docs/docs/images/ by default.
    Override with --output-dir.

AO UI PATHS (discovered 2026-09-11)
    /workflows                              Workflow list
    /executions                             Workflow Runs
    /approvals                              Approval queue
    /configuration/integrations             Integration list
    /configuration/integrations/<uuid>      Integration detail
    /configuration/credentials              Credential list
    /workflow-builder/new                   Empty canvas
    /system-administration/access-management    Users/teams
    /system-administration/authentication       Identity providers
    /system-administration/settings             Settings

    The sidebar is PatternFly 6 with collapsible sections.  At narrow
    viewports it collapses to icon-only; 1400px+ shows labels.  The
    hamburger button has aria-label="Global navigation" and there are
    TWO of them (mobile + desktop) — use the second one.

    Login form IDs: #pf-login-username-id, #pf-login-password-id
    The "Sign in using local account" link reveals the local login form.
    SSO login ("Log in with Ansible Automation Platform") redirects to
    the AAP gateway.
"""

import argparse
import os
import subprocess
import sys
import time


def get_ao_url(env):
    """Get the AO Route URL from the cluster."""
    kubeconfig = os.path.expanduser(f".kube/{env}.kubeconfig")
    if not os.path.exists(kubeconfig):
        sys.exit(f"Kubeconfig not found: {kubeconfig}\nRun: bash utilities/make-kubeconfig.sh {env}")

    result = subprocess.run(
        ["oc", "get", "route", "ao", "-n", "automation-orchestrator",
         "-o", "jsonpath={.spec.host}"],
        env={**os.environ, "KUBECONFIG": kubeconfig},
        capture_output=True, text=True
    )
    if result.returncode != 0 or not result.stdout.strip():
        sys.exit(f"Failed to get AO route: {result.stderr}")
    return f"https://{result.stdout.strip()}"


def get_ao_password():
    """Get the AO admin password from the vault."""
    vault_pass = os.environ.get(
        "SALES_DEMOS_VAULT_PASS",
        os.path.expanduser("~/secrets/.vault_pass_sales_demos")
    )
    result = subprocess.run(
        ["ansible-vault", "view", "playbooks/group_vars/all/secrets.yml",
         "--vault-id", f"sales.demos@{vault_pass}"],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        sys.exit(f"Failed to decrypt vault: {result.stderr}")

    for line in result.stdout.splitlines():
        if "aap_password" in line:
            return line.split(":", 1)[1].strip()
    sys.exit("aap_password not found in vault")


def capture(ao_url, password, output_dir):
    """Capture screenshots using playwright."""
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        sys.exit("playwright not installed.\nRun: pip install playwright && playwright install chromium")

    os.makedirs(output_dir, exist_ok=True)

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(
            viewport={"width": 1280, "height": 800},
            ignore_https_errors=True
        )

        # 1. Pre-auth login page
        page.goto(ao_url, wait_until="networkidle", timeout=30000)
        time.sleep(3)
        path = os.path.join(output_dir, "ao-login-page.png")
        page.screenshot(path=path)
        print(f"  {path}")

        # Login via local account
        page.get_by_text("Sign in using local account").click()
        time.sleep(2)
        page.fill("#pf-login-username-id", "admin")
        page.fill("#pf-login-password-id", password)
        page.click('button:has-text("Log in"):not(:has-text("Ansible"))')
        page.wait_for_load_state("networkidle")
        time.sleep(5)

        if "/workflows" not in page.url and page.url.rstrip("/") != ao_url.rstrip("/"):
            print(f"  WARNING: unexpected URL after login: {page.url}")

        # 2. Integrations list
        page.goto(f"{ao_url}/configuration/integrations",
                  wait_until="networkidle", timeout=15000)
        time.sleep(4)
        path = os.path.join(output_dir, "ao-integrations.png")
        page.screenshot(path=path)
        print(f"  {path}")

        # 3. AAP integration detail (click the first row link)
        try:
            link = page.locator("td a").first
            if link.count() > 0:
                link.click()
                page.wait_for_load_state("networkidle")
                time.sleep(3)
                path = os.path.join(output_dir, "ao-integration-detail.png")
                page.screenshot(path=path)
                print(f"  {path}")
        except Exception as e:
            print(f"  SKIP integration detail: {e}")

        # 4. Workflow builder (empty canvas)
        page.goto(f"{ao_url}/workflow-builder/new",
                  wait_until="networkidle", timeout=15000)
        time.sleep(5)
        path = os.path.join(output_dir, "ao-workflow-builder.png")
        page.screenshot(path=path)
        print(f"  {path}")

        browser.close()


def main():
    parser = argparse.ArgumentParser(
        description="Capture AO screenshots for the demo docs"
    )
    parser.add_argument("env", choices=["sandbox", "demo"],
                        help="Target environment")
    parser.add_argument("--output-dir",
                        default="../sales.demos-docs/docs/images",
                        help="Where to write the PNGs (default: %(default)s)")
    args = parser.parse_args()

    print(f"Resolving AO route for {args.env}...")
    ao_url = get_ao_url(args.env)
    print(f"  {ao_url}")

    print("Reading admin password from vault...")
    password = get_ao_password()
    print("  (decrypted)")

    print(f"Capturing screenshots to {args.output_dir}/")
    capture(ao_url, password, args.output_dir)
    print("Done.")


if __name__ == "__main__":
    main()
