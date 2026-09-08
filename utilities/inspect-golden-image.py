#!/usr/bin/env python3
# ===========================================================================
# inspect-golden-image.py -- read the CIS hardening OFF the published Windows
# containerdisk, offline, before anyone trusts the label on it.
#
# WHY THIS EXISTS. `com.redhat.cis.level=L1` is an INPUT to the producer's
# publish, not an observation of the disk: publish_windows_containerdisk.yml
# defaults to cis_level=L1 and the win2k22-cis-l1-golden repository, so the
# label records the operator's intent and nothing reads the media back.
#
# That is not hypothetical. #358: the demo guest scored 9 of 27 CIS controls,
# and the cause turned out to be TWO separate defects of the same shape --
#
#   1. (#364, this repo) link_windows_image.yml decided whether to re-import
#      from whether the DataSource was *Ready* rather than from *which image*
#      it served, so repointing the tag imported nothing;
#   2. (image.builder.pipeline#91) the image the tag names is itself unhardened
#      -- `win2k22-cis-l1-golden:20260907-0516` contains a disk built and
#      sysprepped on 2026-09-05, two days before the tag, with exactly one
#      "Beginning of a new sysprep run" in its own log.
#
# Both are a declared value trusted instead of the artifact measured. This
# script measures the artifact.
#
# IT ANSWERS A QUESTION NO CLUSTER CAN. Scanning a running guest cannot tell
# you whether the image was unhardened or whether something stripped it after
# boot -- #358 burned two rebuilds on exactly that ambiguity. Reading the
# published media settles it with no VM, no cluster and no credentials beyond
# the quay pull.
#
# IT ALSO DISPROVED THE LEADING HYPOTHESIS. `sysprep /generalize` was believed
# to be stripping the hardening. The hive shows \Policies\Microsoft present
# with its six stock subkeys and no WindowsFirewall among them -- generalize
# would have had to delete exactly the CIS key and leave every sibling.
#
# NO ROOT, NO LIBGUESTFS. qemu-img + ntfsprogs (both already present on a
# Fedora workstation) + regipy from pip. Deliberate: a check that needs sudo
# is a check nobody runs.
#
# Usage:
#   pip install regipy
#   utilities/inspect-golden-image.py \
#       --image quay.io/<user>/win2k22-cis-l1-golden:<tag> \
#       --workdir ~/cis-inspect
#
# Credentials come from the vaulted secrets file (quay_username /
# quay_password), the same pair link_windows_image.yml uses. Pass
# --skip-pull to re-analyse a workdir you already populated.
#
# Exit codes: 0 the image carries the hardening, 1 it does not, 2 the run
# could not reach a verdict. So it is usable as a gate.
# ===========================================================================
"""Verify a published Windows golden containerdisk really carries CIS L1."""

import argparse
import json
import os
import subprocess
import sys
import tarfile

# The controls read back out of the hives. A deliberately SMALL subset of
# playbooks/roles/windows_compliance/defaults/main.yml -- the ones whose
# presence is impossible on a clean install, so a pass cannot be a Windows
# default in disguise. That is the whole trick: #358's original evidence was
# ambiguous precisely because nine "compliant" controls were stock values.
#
# hive, key path, value name, expected
CONTROLS = [
    ("SOFTWARE", r"\Policies\Microsoft\WindowsFirewall\DomainProfile", "EnableFirewall", 1),
    ("SOFTWARE", r"\Policies\Microsoft\WindowsFirewall\PrivateProfile", "EnableFirewall", 1),
    ("SOFTWARE", r"\Policies\Microsoft\WindowsFirewall\PublicProfile", "EnableFirewall", 1),
    ("SOFTWARE", r"\Policies\Microsoft\WindowsFirewall\PublicProfile", "DefaultInboundAction", 1),
    ("SOFTWARE", r"\Microsoft\Windows\CurrentVersion\Policies\System", "DontDisplayLastUserName", 1),
    # \Windows NT\Printers, not \Windows. The CIS role writes
    # `HKLM:\SOFTWARE\Policies\Microsoft\Windows Nt\Printers` (rule
    # 18.9.20.1.1); the stock key is spelled `Windows NT`. The old path could
    # not hold this value on ANY machine, and that was invisible for as long as
    # the only disk ever measured was unhardened -- where the honest answer and
    # the bug are both "VALUE ABSENT". Caught by image.builder.pipeline#93 the
    # first time genuinely hardened media was read.
    ("SOFTWARE", r"\Policies\Microsoft\Windows NT\Printers", "DisableWebPnPDownload", 1),
    ("SYSTEM", r"\Control\Lsa", "SCENoApplyLegacyAuditPolicy", 1),
    ("SYSTEM", r"\Services\LanmanWorkstation\Parameters", "RequireSecuritySignature", 1),
    ("SYSTEM", r"\Services\LanmanServer\Parameters", "RequireSecuritySignature", 1),
    ("SYSTEM", r"\Services\LanmanServer\Parameters", "SMB1", 0),
]


def run(*argv, **kw):
    r = subprocess.run(argv, capture_output=True, text=True, **kw)
    if r.returncode:
        sys.exit(f"FAILED: {' '.join(argv[:3])}\n{r.stderr[-2000:]}")
    return r.stdout


def quay_creds():
    """Read quay_username / quay_password from the vaulted secrets file."""
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    vault = os.environ.get(
        "SALES_DEMOS_VAULT_PASS", os.path.expanduser("~/secrets/.vault_pass_sales_demos")
    )
    out = run(
        "ansible-vault", "view",
        os.path.join(repo, "playbooks/group_vars/all/secrets.yml"),
        "--vault-password-file", vault,
    )
    import yaml
    d = yaml.safe_load(out)
    return d["quay_username"], d["quay_password"]


def pull(image, workdir):
    user, password = quay_creds()
    print(f"==> pulling {image} (this is the slow part; ~9 GiB)")
    run("skopeo", "copy", "--src-creds", f"{user}:{password}",
        f"docker://{image}", f"dir:{workdir}/img")


def extract_disk(workdir):
    """FROM scratch + COPY disk.img -> one big layer holding the qcow2."""
    man = json.load(open(f"{workdir}/img/manifest.json"))
    blob = max(man["layers"], key=lambda x: x["size"])["digest"].split(":")[1]
    qcow = f"{workdir}/disk.qcow2"
    if not os.path.exists(qcow):
        with tarfile.open(f"{workdir}/img/{blob}") as t:
            names = [n for n in t.getnames() if n.rstrip("/").endswith("disk.img")]
            if not names:
                sys.exit(f"no disk.img in the layer; members: {t.getnames()[:20]}")
            src = t.extractfile(names[0])
            with open(qcow, "wb") as out:
                while chunk := src.read(16 << 20):
                    out.write(chunk)
    return qcow


def carve_volume(workdir, qcow):
    """qcow2 -> raw -> the Windows NTFS partition as its own file."""
    raw = f"{workdir}/disk.raw"
    if not os.path.exists(raw):
        print("==> converting qcow2 to raw")
        run("qemu-img", "convert", "-O", "raw", qcow, raw)
    vol = f"{workdir}/win.ntfs"
    if not os.path.exists(vol):
        pt = json.loads(run("sfdisk", "-J", raw))["partitiontable"]
        sector = pt.get("sectorsize", 512)
        # The Windows volume is the biggest partition; the others are ESP and
        # the ~128 MiB Microsoft Reserved partition.
        big = max(pt["partitions"], key=lambda p: p["size"])
        print(f"==> carving the Windows volume ({big['size'] * sector // (1 << 30)} GiB)")
        run("dd", f"if={raw}", f"of={vol}", "bs=1M",
            f"skip={big['start'] * sector // (1 << 20)}",
            f"count={big['size'] * sector // (1 << 20) + 1}",
            "conv=sparse", "status=none")
    return vol


def read_file(vol, path):
    r = subprocess.run(["ntfscat", "-f", vol, path], capture_output=True)
    return r.stdout if r.returncode == 0 else None


def hives_and_provenance(workdir, vol):
    for hive in ("SOFTWARE", "SYSTEM"):
        dest = f"{workdir}/{hive}"
        if not os.path.exists(dest):
            data = read_file(vol, f"/Windows/System32/config/{hive}")
            if data is None:
                sys.exit(f"could not read the {hive} hive out of the volume")
            open(dest, "wb").write(data)
    # The sysprep log dates the disk, which is how #358 caught a two-day-old
    # payload under a fresh tag. Provenance, not compliance -- reported either
    # way, never fatal on its own.
    log = read_file(vol, "/Windows/System32/Sysprep/Panther/setupact.log")
    if log:
        text = log.decode("utf-16" if log[:2] in (b"\xff\xfe", b"\xfe\xff") else "utf-8",
                          errors="replace")
        runs = [ln for ln in text.splitlines() if "Beginning of a new sysprep run" in ln]
        stamps = [ln.split(",")[0] for ln in text.splitlines() if "The time is now" in ln]
        print(f"\n==> provenance: {len(runs)} sysprep run(s) recorded on this disk")
        if stamps:
            print(f"    first: {stamps[0]}")
            print(f"    last:  {stamps[-1]}")


def check(workdir):
    from regipy.registry import RegistryHive
    hives = {n: RegistryHive(f"{workdir}/{n}") for n in ("SOFTWARE", "SYSTEM")}
    # An offline SYSTEM hive has no CurrentControlSet; \Select\Current names it.
    try:
        sel = {v.name: v.value for v in hives["SYSTEM"].get_key(r"\Select").get_values()}
        cs = f"\\ControlSet{sel.get('Current', 1):03d}"
    except Exception:
        cs = r"\ControlSet001"

    print(f"\n{'state':<15}{'found':<10}{'want':<8}key")
    good = 0
    for hive_name, path, value, want in CONTROLS:
        full = (cs + path) if hive_name == "SYSTEM" else path
        try:
            key = hives[hive_name].get_key(full)
        except Exception:
            print(f"{'KEY ABSENT':<15}{'-':<10}{str(want):<8}{hive_name}:{full}\\{value}")
            continue
        found = next((v.value for v in key.get_values()
                      if v.name and v.name.lower() == value.lower()), None)
        if found is None:
            state = "VALUE ABSENT"
        elif found == want:
            state, good = "OK", good + 1
        else:
            state = "WRONG"
        print(f"{state:<15}{str(found):<10}{str(want):<8}{hive_name}:{full}\\{value}")
    return good, len(CONTROLS)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--image", help="containerdisk reference to inspect")
    ap.add_argument("--workdir", default=os.path.expanduser("~/cis-inspect"))
    ap.add_argument("--skip-pull", action="store_true",
                    help="re-analyse an already-populated workdir")
    args = ap.parse_args()

    if not args.skip_pull and not args.image:
        ap.error("--image is required unless --skip-pull is given")
    os.makedirs(args.workdir, exist_ok=True)

    if not args.skip_pull:
        pull(args.image, args.workdir)
    vol = carve_volume(args.workdir, extract_disk(args.workdir))
    hives_and_provenance(args.workdir, vol)
    good, total = check(args.workdir)

    print(f"\n{good} of {total} non-default CIS controls present in the PUBLISHED IMAGE")
    if good == total:
        print("VERDICT: the image carries the hardening its label claims.")
        return 0
    print("VERDICT: THE IMAGE DOES NOT CARRY THE HARDENING ITS LABEL CLAIMS.")
    print("  Every control above is one that CANNOT be set on a clean install,")
    print("  so absence is not a Windows default -- it is a missing hardening pass.")
    print("  Do not link this image, and do not claim CIS L1 from it. See #358.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
