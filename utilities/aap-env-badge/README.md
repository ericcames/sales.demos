# AAP environment badge

Paints a `SANDBOX` or `DEMO` pill in the middle of the AAP masthead, so you can
tell which environment you are in **after** logging in.

```
|  RedHat AAP              [ SANDBOX ]              ⟳ ☾ 🔔 ? admin  |
```

Green `#3E8635` for sandbox, red `#EE0000` for demo — the same convention the
sign-in logo uses, from [`../env_colors.py`](../env_colors.py).

## Why a browser extension and not a setting

The sign-in page already marks the environment: `make-env-logo.py` badges the
Ansible lockup and it is applied as the gateway's `custom_logo`. After login,
nothing does — and after login is when you are actually clicking things.

**No AAP setting can fix that.** Measured against the live 2.6 gateway (#54):

- `/api/gateway/v1/settings/all/` returns **44 settings**. The only
  branding-related ones are `custom_login_info` and `custom_logo`.
- `custom_logo` **was already applied** on sandbox — 26,714 characters of base64
  PNG — and the masthead still rendered the stock lockup.

So `custom_logo` is sign-in-page-only. Anything further server-side means
patching a bundled asset inside the gateway container, which the operator
reconciles away and an upgrade breaks. The browser is the right place, and in a
demo it is sufficient: the only screen that matters is the one being shared.

**This changes nothing on the cluster.** It reads no AAP data and sends nothing
anywhere.

## Install

1. `chrome://extensions`
2. Turn on **Developer mode**
3. **Load unpacked** → select this directory

It applies to `https://aap-aap.apps.cluster-*.dyn.redhatworkshops.io/*`, so both
environments are covered by the one load, and it keeps working when RHDP hands
you a new cluster ID.

## An unrecognized environment is a feature

A host matching the RHDP AAP pattern but absent from
[`envs.json`](envs.json) gets a neutral gray `UNRECOGNIZED ENV` pill rather than
no pill at all. A freshly built environment nobody has recorded yet is exactly
when you are most likely to act on the wrong cluster.

To make it recognized, add the environment to
`inventory/group_vars/<env>/connection.yml` as usual, then regenerate:

```bash
python3 utilities/make-env-badge-config.py
```

`envs.json` is **generated and committed** — do not edit it by hand.
`aap_hostname` in `connection.yml` stays the single source of truth, because a
stale hand-maintained copy does not error, it labels the wrong cluster with the
right color.

## Design notes

- **It is an overlay, not DOM surgery.** One `position: fixed` element appended
  to `<body>`; AAP's own markup is never modified. The masthead is PatternFly
  with version-prefixed class names (`pf-v5-c-masthead__*`), so anchoring inside
  it would break on a gateway upgrade. All this depends on is a `<header>`
  existing at the top of the page.
- **It hides below 1100px** rather than overlapping the nav toggle or the
  right-hand icons. A badge sitting on top of the controls is worse than none,
  particularly on a shared screen.
- **No theme detection.** A light outline on the pill keeps it legible against
  both the dark masthead and AAP's light theme.
- **Nothing on the sign-in page.** That page already has the badged logo.
