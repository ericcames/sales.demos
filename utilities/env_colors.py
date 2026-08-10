"""The environment color convention, in one place.

Lifted out of make-env-logo.py when the masthead badge (#54) became a second
consumer. Two things now paint an environment marker — the sign-in logo and the
browser extension — and they must agree, because the whole point is that the
color means the same thing everywhere.

Reusing aap_config's severity convention, so there is no new color language to
learn:

    sandbox — the environment you are actively building against and breaking
    demo    — the environment you show customers

Kept dependency-free on purpose. make-env-logo.py needs Pillow and ImageMagick;
make-env-badge-config.py needs neither, and should not inherit them just to read
two hex values.
"""

# env -> (fill, text color)
COLORS = {
    "sandbox": ("#3E8635", "#FFFFFF"),
    "demo": ("#EE0000", "#FFFFFF"),
}

# Shown for an RHDP AAP host that is not in either connection.yml. Deliberately
# neutral rather than alarming: it means "unknown", not "dangerous".
UNKNOWN_COLOR = ("#6A6E73", "#FFFFFF")
