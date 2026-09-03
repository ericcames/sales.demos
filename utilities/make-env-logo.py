#!/usr/bin/env python3
"""Generate an AAP sign-in logo badged with the environment name.

Ported from ericcames/aap_config, with this repo's two environments in place of
its dev/qa/prod. Extends the official Ansible Automation Platform lockup rather
than replacing it, so the product branding survives and only an environment
marker is added. The result is set as the gateway's `custom_logo`, which renders
on the LOGIN page beside `custom_login_info`.

Both environments look identical at the sign-in page otherwise, and the moment
you are most likely to act on the wrong one is the moment before you have
touched anything.

It does not change the post-login masthead — that is a bundled UI asset, not a
setting. Re-measured on the live 2.6 gateway in #54: `custom_logo` was already
applied, 26 KB of base64 PNG, and the masthead still rendered the stock lockup.
So this really is a sign-in-time warning, and no setting will change that.

THE COUNTS THAT USED TO BE HERE WERE WRONG, and are gone rather than corrected
in place, because the number is the least durable part of the claim. This file
previously said 2.7 exposes 43 gateway settings and 2.6 exposes 44; the live
2.7 gateway on cluster-kbjvc returns 41 (#101). All 41 were enumerated and none
marks the environment post-login, so the conclusion survives every count it has
been given. Cite the conclusion, not the tally.

Marking the environment AFTER login needs the browser, not the server — see
utilities/aap-env-badge/, which paints a matching pill in the masthead using the
same colors from env_colors.py.

    python3 utilities/make-env-logo.py --env sandbox

Writes docs/images/logo-<env>.png and the single-line base64 sidecar
docs/images/logo-<env>.png.b64 that inventory/group_vars/<env>/gateway_settings.yml
references. Re-run it to regenerate; both outputs are committed so they render on
GitHub and so a clone does not need ImageMagick to apply the config.

Needs Pillow, ImageMagick with the librsvg delegate, and the Red Hat Display
font.
"""
import argparse
import base64
import pathlib
import shutil
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

# Shared with utilities/make-env-badge-config.py (#54). The sign-in logo and the
# masthead badge must agree on what each color means.
from env_colors import COLORS

REPO = pathlib.Path(__file__).resolve().parent.parent
IMAGES = REPO / "docs" / "images"
SOURCE_SVG = IMAGES / "aap-logo-white.svg"
FONT = "/usr/share/fonts/redhat/RedHatDisplay-SemiBold.otf"

LOGO_HEIGHT = 56          # masthead-appropriate; lockup is 6.56:1 so ~367px wide
BADGE_GAP = 24            # space between lockup and badge
BADGE_PAD_X = 18          # horizontal padding inside the badge
BADGE_FONT_SIZE = 30


def render_lockup(height: int) -> Image.Image:
    """Rasterize the official SVG lockup via ImageMagick/librsvg."""
    if not SOURCE_SVG.exists():
        sys.exit(f"missing {SOURCE_SVG} — fetch it from the AAP instance first")
    magick = shutil.which("magick") or shutil.which("convert")
    if not magick:
        sys.exit("ImageMagick not found (needs librsvg for real SVG rendering)")
    out = IMAGES / ".lockup-tmp.png"
    subprocess.run(
        [magick, "-background", "none", "-density", "300",
         str(SOURCE_SVG), "-resize", f"x{height}", str(out)],
        check=True,
    )
    img = Image.open(out).convert("RGBA")
    img.load()
    out.unlink()
    return img


def build(env: str) -> pathlib.Path:
    key = env.lower()
    if key not in COLORS:
        sys.exit(f"unknown env '{env}' — expected one of {', '.join(COLORS)}")
    fill, text_color = COLORS[key]
    label = env.upper()

    lockup = render_lockup(LOGO_HEIGHT)
    font = ImageFont.truetype(FONT, BADGE_FONT_SIZE)

    # Measure the label so the badge hugs it.
    probe = ImageDraw.Draw(Image.new("RGBA", (1, 1)))
    l, t, r, b = probe.textbbox((0, 0), label, font=font)
    text_w, text_h = r - l, b - t
    badge_h = LOGO_HEIGHT
    badge_w = text_w + BADGE_PAD_X * 2

    canvas = Image.new(
        "RGBA",
        (lockup.width + BADGE_GAP + badge_w, max(lockup.height, badge_h)),
        (0, 0, 0, 0),
    )
    canvas.paste(lockup, (0, (canvas.height - lockup.height) // 2), lockup)

    # The badge carries its own solid background so the environment stays
    # legible in both light and dark themes, even where the white wordmark
    # does not.
    draw = ImageDraw.Draw(canvas)
    x0 = lockup.width + BADGE_GAP
    y0 = (canvas.height - badge_h) // 2
    draw.rounded_rectangle(
        [x0, y0, x0 + badge_w, y0 + badge_h], radius=8, fill=fill
    )
    draw.text(
        (x0 + (badge_w - text_w) / 2 - l,
         y0 + (badge_h - text_h) / 2 - t),
        label, font=font, fill=text_color,
    )

    png = IMAGES / f"logo-{key}.png"
    canvas.save(png, optimize=True)

    b64 = base64.b64encode(png.read_bytes()).decode()
    (IMAGES / f"logo-{key}.png.b64").write_text(b64 + "\n")
    return png


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--env", required=True, help="sandbox or demo")
    args = ap.parse_args()
    p = build(args.env)
    size = p.stat().st_size
    b64_size = (IMAGES / f"{p.name}.b64").stat().st_size
    print(f"{p}  ({size:,} bytes)")
    print(f"{p}.b64  ({b64_size:,} bytes)")
