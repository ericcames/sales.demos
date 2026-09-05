#!/usr/bin/env python3
"""Render the demo's guest-facing artifacts without a cluster.

WHY THIS EXISTS
    The talk track in docs/demos/openshift-virtualization/ has to work when the
    presenter has no environment — an RHDP cluster expires, a demo slot lands
    before the morning's build finishes, a colleague reads the docs on a plane.
    Two of the three things a customer actually looks at are Jinja templates in
    playbooks/roles/linux_configure/templates/, so they can be rendered on a
    laptop with nothing running.

    This is the same convention as utilities/make-env-logo.py: a generated
    image committed under docs/images/, beside the script that regenerates it.

WHAT IT IS NOT
    The screenshot is RENDERED FROM THE TEMPLATE, not photographed from a live
    run. It is accurate — the guest serves this exact template — but it is not
    a capture, and the docs say so wherever it appears. Do not describe it as a
    screenshot of a running VM.

FIXTURE VALUES ARE REPRESENTATIVE, NOT REAL. The shape is what a small-1cpu-2gb
RHEL 9 guest reports; the cluster id is the generic placeholder form. Nothing
here is a live host, and nothing here is a credential.

USAGE
    python3 utilities/render-demo-assets.py            # write PNG, print banners
    python3 utilities/render-demo-assets.py --no-png   # banners only, no Chrome

REQUIRES
    jinja2, and google-chrome (or chromium) on PATH for the PNG.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    from jinja2 import Environment, FileSystemLoader, StrictUndefined
except ImportError:  # pragma: no cover - a missing dep should say what to do
    sys.exit("jinja2 is not installed. Try: pip install --user jinja2")

REPO = Path(__file__).resolve().parent.parent
ROLE = REPO / "playbooks" / "roles" / "linux_configure"
TEMPLATES = ROLE / "templates"
LOGOS = ROLE / "files" / "logos"
OUT_PNG = REPO / "docs" / "images" / "demo-page.png"

# The headless window, which IS the screenshot: --screenshot captures the
# viewport, not the full scrollable page, so the height has to be sized to the
# content or the committed PNG carries a slab of empty background. 1000px wide
# renders the page's 48rem max-width column with margin either side; 940 tall
# ends just under the footer link. Re-measure if the facts table gains a row.
VIEWPORT = (1000, 940)

# ---------------------------------------------------------------------------
# Fixture. Mirrors what `Sales Demos - Configure VMs` has in scope on a
# small-1cpu-2gb Linux guest: role defaults, the guest's own gathered facts,
# and the host variables provision_vm.yml registered into AAP (#49).
#
# ansible_virtualization_type/_role are the literal string "NA" ON PURPOSE.
# That is what a KubeVirt guest genuinely reports, and it is why index.html.j2
# cannot use `| default()` — "NA" is defined, so the default never fires and
# the page rendered "NA (NA)" until it was special-cased. Keeping the real
# value here means the rendered PNG exercises that branch instead of hiding it.
# ---------------------------------------------------------------------------
CLUSTER = "cluster-abcde.dyn.redhatworkshops.io"
VM_NAME = "sd-lnx-small-1cpu-2gb"
NAMESPACE = "sales-demos-demo"

FIXTURE = {
    # --- role defaults (playbooks/roles/linux_configure/defaults/main.yml) ---
    "linux_configure_message": (
        "Running on Red Hat Enterprise Linux, virtualized by Red Hat OpenShift "
        "Virtualization, provisioned by Terraform and configured by Red Hat "
        "Ansible Automation Platform."
    ),
    "linux_configure_teardown_time": "6 PM America/Phoenix",
    "linux_configure_repo_url": "https://github.com/ericcames/sales.demos",
    "linux_configure_banner_owner": "Red Hat, Inc.",
    "linux_configure_motd_tagline": "V I R T U A L I Z A T I O N   D E M O",
    # MIRRORS linux_configure/defaults/main.yml, AND CI ENFORCES IT (#145).
    # These are data rather than markup — motd.j2 iterates them — so a copy
    # here is what lets this script render without the role. check-renderer-
    # fixture.py fails if the two lists diverge; the role's defaults win.
    "linux_configure_motd_credits": [
        "OpenShift Virtualization    (host)",
        "Terraform                   (provision)",
        "Ansible Automation Platform (configure/patch)",
        "Red Hat Insights            (detect)",
    ],
    # --- gathered facts ---
    "inventory_hostname": "linuxweb",
    "inventory_hostname_short": "linuxweb",
    "ansible_distribution": "RedHat",
    "ansible_distribution_version": "9.6",
    "ansible_kernel": "5.14.0-570.21.1.el9_6.x86_64",
    "ansible_processor_vcpus": 1,
    "ansible_memtotal_mb": 1743,
    "ansible_virtualization_type": "NA",
    "ansible_virtualization_role": "NA",
    "ansible_date_time": {"iso8601": "2026-08-11T14:32:07Z"},
    # --- host vars set by provision_vm.yml ---
    "ansible_host": f"{VM_NAME}.{NAMESPACE}.svc.cluster.local",
    "vm_size_tier": "small-1cpu-2gb",
    "vm_size_chosen": "sd1.small",
    # #202 — golden image provenance, forwarded by provision_vm.yml
    "golden_image_source": "quay.io/zigfreed/rhel9-cis-l1-golden:20260905-0411",
    "golden_image_cis_level": "L1",
}
FIXTURE["linux_configure_motd_url"] = f"https://{VM_NAME}-web-{NAMESPACE}.apps.{CLUSTER}"
FIXTURE["linux_configure_cockpit_url"] = f"https://{VM_NAME}-cockpit-{NAMESPACE}.apps.{CLUSTER}"
FIXTURE["linux_configure_compliance_url"] = f"https://{VM_NAME}-web-{NAMESPACE}.apps.{CLUSTER}/compliance/report.html"

# MIRRORS linux_configure/vars/main.yml, AND CI ENFORCES IT (#160). On a KubeVirt
# guest the virtualization facts come back as the literal string "NA", so both
# the page and facts.json normalise them — and they must normalise identically,
# because a live VM once served a page saying "KVM (guest)" while facts.json on
# the same host said "NA". Derived here the same way rather than hardcoded, so
# changing the fact above carries through as it would on a real guest.
_vt = FIXTURE["ansible_virtualization_type"]
_vr = FIXTURE["ansible_virtualization_role"]
FIXTURE["linux_configure_virt_type"] = _vt if _vt not in ("NA", "") else "KVM"
FIXTURE["linux_configure_virt_role"] = _vr if _vr not in ("NA", "") else "guest"

# MIRRORS linux_configure defaults and vars for golden image provenance (#202).
_gi_src = FIXTURE["golden_image_source"]
FIXTURE["linux_configure_golden_image_source"] = _gi_src
FIXTURE["linux_configure_golden_image_cis_level"] = FIXTURE["golden_image_cis_level"]
FIXTURE["linux_configure_golden_image_pipeline_url"] = "https://github.com/ericcames/image.builder.pipeline"
_gi_repo = _gi_src.rsplit(":", 1)[0] if _gi_src else ""
_gi_tag = _gi_src.rsplit(":", 1)[1] if ":" in _gi_src else ""
FIXTURE["linux_configure_golden_image_repo"] = _gi_repo
FIXTURE["linux_configure_golden_image_tag"] = _gi_tag
FIXTURE["linux_configure_golden_image_build_date"] = (
    f"{_gi_tag[:4]}-{_gi_tag[4:6]}-{_gi_tag[6:8]} {_gi_tag[9:11]}:{_gi_tag[11:13]} UTC"
    if len(_gi_tag) >= 13
    else _gi_tag
)


def jinja() -> Environment:
    """A Jinja environment configured the way ansible.builtin.template is.

    trim_blocks IS NOT OPTIONAL. Ansible defaults it to True; Jinja defaults it
    to False. With Jinja's default, the newline after every `{% for %}` and
    `{% endfor %}` survives, and motd.j2's "Powered by" list renders with a
    blank line between each credit — the boxed banner falls apart. The other
    two values are Ansible's defaults as well.
    """
    return Environment(
        loader=FileSystemLoader(TEMPLATES),
        undefined=StrictUndefined,
        trim_blocks=True,
        lstrip_blocks=False,
        keep_trailing_newline=True,
        autoescape=False,  # noqa: S701 - matches Ansible's template module
    )


def render(name: str, **overrides: object) -> str:
    return jinja().get_template(name).render({**FIXTURE, **overrides})


def facts_json() -> str:
    """The curated facts.json, matching linux_configure/tasks/main.yml.

    THAT CLAIM IS ENFORCED, NOT ASSERTED (#145). utilities/check-renderer-fixture.py
    renders the role's own `content:` block with the FIXTURE below and diffs it
    against this function, in CI. The ROLE is the source of truth; if the two
    disagree, this is what changes.
    """
    f = FIXTURE
    return json.dumps(
        {
            "hostname": f["inventory_hostname"],
            "gathered": f["ansible_date_time"]["iso8601"],
            "os": {
                "distribution": f["ansible_distribution"],
                "version": f["ansible_distribution_version"],
                "kernel": f["ansible_kernel"],
            },
            "resources": {
                "vcpus": f["ansible_processor_vcpus"],
                "memory_mb": f["ansible_memtotal_mb"],
            },
            "virtualization": {
                "type": f["linux_configure_virt_type"],
                "role": f["linux_configure_virt_role"],
            },
            "provisioning": {
                "vm_size_tier": f["vm_size_tier"],
                "instance_type": f["vm_size_chosen"],
                "in_cluster_address": f["ansible_host"],
                "repository": f["linux_configure_repo_url"],
            },
            "golden_image": {
                "source": f["linux_configure_golden_image_source"] or None,
                "repo": f["linux_configure_golden_image_repo"] or None,
                "build_date": f["linux_configure_golden_image_build_date"] or None,
                "cis_level": f["linux_configure_golden_image_cis_level"] or None,
                "pipeline": f["linux_configure_golden_image_pipeline_url"],
            },
        },
        indent=4,
    )


def find_chrome() -> str:
    for exe in ("google-chrome", "chromium", "chromium-browser", "google-chrome-stable"):
        found = shutil.which(exe)
        if found:
            return found
    sys.exit(
        "No Chrome or Chromium on PATH. Install one, or re-run with --no-png "
        "to get the text banners only."
    )


def screenshot(html: str) -> None:
    """Write docs/images/demo-page.png from the rendered page.

    THE LOGOS MUST BE STAGED BESIDE THE HTML. index.html.j2 references
    `logos/rhel.svg` RELATIVELY, so rendering the file on its own produces a
    screenshot with three broken-image boxes where the product marks belong.
    That is the one failure mode of this script worth knowing about.
    """
    chrome = find_chrome()
    with tempfile.TemporaryDirectory(prefix="sales-demos-render-") as tmp:
        stage = Path(tmp)
        (stage / "index.html").write_text(html, encoding="utf-8")
        shutil.copytree(LOGOS, stage / "logos")

        OUT_PNG.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(  # noqa: S603 - fixed argv, no shell
            [
                chrome,
                "--headless",
                "--no-sandbox",
                "--disable-gpu",
                "--hide-scrollbars",
                # Force the light palette: the page is `color-scheme: light dark`
                # and headless Chrome may inherit a dark preference, which would
                # make the committed asset flip depending on who regenerated it.
                "--force-color-profile=srgb",
                "--blink-settings=preferredColorScheme=1",
                f"--window-size={VIEWPORT[0]},{VIEWPORT[1]}",
                f"--screenshot={OUT_PNG}",
                "--virtual-time-budget=2000",
                (stage / "index.html").as_uri(),
            ],
            check=True,
            capture_output=True,
            cwd=stage,
        )

    if not OUT_PNG.exists() or OUT_PNG.stat().st_size == 0:
        sys.exit(f"Chrome exited cleanly but wrote nothing to {OUT_PNG}")


def banner(title: str, body: str) -> None:
    rule = "=" * 78
    print(f"\n{rule}\n{title}\n{rule}\n{body}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument(
        "--no-png",
        action="store_true",
        help="skip the screenshot; print the text artifacts only",
    )
    args = ap.parse_args()

    html = render("index.html.j2")

    if not args.no_png:
        screenshot(html)
        rel = OUT_PNG.relative_to(REPO)
        print(f"wrote {rel} ({OUT_PNG.stat().st_size:,} bytes)")
        print("  -> open it and check the three product logos are NOT broken boxes")

    # The pre-auth notice renders with the URL forced empty, exactly as
    # linux_configure does: /etc/issue.net is shown before anyone has proved who
    # they are, and the demo URL is not part of that.
    banner("/etc/issue.net  (pre-authentication)", render("issue.j2"))
    banner("/etc/motd  (post-authentication)", render("motd.j2"))
    banner("<web_url>/facts.json", facts_json())


if __name__ == "__main__":
    main()
