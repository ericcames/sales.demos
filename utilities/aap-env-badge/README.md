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

**This changes nothing on the cluster.** It reads one AAP endpoint — the job
template list, to find out which environment it is on — and sends nothing
anywhere. No writes, no third parties, no storage.

## How it knows which environment it is

It asks AAP. `inventory/group_vars/aap/controller_templates.yml` sets
`target_env: "{{ aap_env_name }}"` on the `Sales Demos - Provision VM` and
`Sales Demos - Teardown VMs` templates, so every AAP already states its own name
in a field this repo controls. The extension does one same-origin request to
`/api/controller/v2/job_templates/` and scans for a template carrying a
`target_env` — by field, not by template name, so a rename cannot break it.

`playbooks/tasks/assert_target_environment.yml` fails a run closed if
`target_env` ever disagrees with the template's `limit`, so the value the badge
reads is the same one the playbooks trust.

`extra_vars` comes back as a JSON-encoded *string* rather than an object; the
code parses it and tolerates both.

### Why not the hostname

It used to look `location.hostname` up in a generated map built from
`aap_hostname` in each `connection.yml`. The hostname is only a *proxy* for the
environment: it changes every time RHDP rebuilds a cluster, so the map had to be
regenerated and committed on every rotation — a third step on top of the
`connection.yml` edit and the vault.

It went stale exactly as you would expect, and **silently**: a grey
`UNRECOGNIZED ENV` pill in the masthead next to a correctly badged green
`SANDBOX` sign-in page. Nothing errored. See #87.

## Install

1. `chrome://extensions`
2. Turn on **Developer mode**
3. **Load unpacked** → select this directory

Both environments are covered by the one load, and — since #87 — it genuinely
keeps working when RHDP hands you a new cluster ID. There is nothing to
regenerate and nothing to commit.

If it was already loaded, hit **Reload** on the card: Chrome caches the
extension's own files, and the old `envs.json` will otherwise still be in there.

### Why the manifest matches all of `*.dyn.redhatworkshops.io`

It looks too broad, and it is deliberate. **Chrome match patterns allow `*` only
as an entire leading subdomain** (`*.example.com`) or as the whole host — never
inside a hostname label. The obvious pattern

```
https://aap-aap.apps.cluster-*.dyn.redhatworkshops.io/*
```

is rejected with `Invalid value for 'content_scripts[0].matches[0]': Invalid
host wildcard` and the extension will not load at all. Do not "tighten" it back
to that.

So the manifest matches every RHDP host and `content.js` narrows it in one line:
the AAP gateway Route on this catalog item is always `aap-<namespace>`, so
anything else — the OpenShift console, Cockpit, a demo web server — returns
before touching the page.

## An unrecognized environment is a feature

Signed in, AAP answered, and nothing declared an environment → a neutral gray
`UNRECOGNIZED ENV` pill, rather than no pill at all. A cluster nobody has
recorded is exactly when you are most likely to act on the wrong one. It is not
a fallback, and no failure ever produces a *coloured* pill.

You get it when the config-as-code has not been applied to that cluster yet, if
the API call fails, if the two templates disagree, or if `target_env` names an
environment with no colour.

Two consequences worth knowing before they surprise you:

- **A brand-new RHDP environment is grey until `setup.yml` has run.** The old
  hostname map went green whether or not AAP was configured. This is a change,
  and arguably the better answer — an unconfigured AAP is not one to be
  confidently clicking around in.
- **The pill reports what AAP says it is, not where you are.** If `config.yml`
  were ever applied to sandbox with `--limit demo`, the sandbox host would show
  a **red DEMO** pill. That is a true report of a real misconfiguration, and one
  the hostname map would have hidden.
- **It needs read access to the job templates.** Signing in as a user who cannot
  see them gives `200` with no results, and therefore grey.

**Signed out is different, and is treated differently.** A `401`/`403` is AAP
telling you it does not know who you are — not that the cluster is
unidentifiable — so the extension paints nothing at all. The sign-in page
already carries the badged logo, and a grey pill contradicting a green logo two
inches away is worse than no pill. That distinction keys off the HTTP status,
never off the URL: sniffing AAP's routes is the coupling this design avoids.

Once you log in the pill appears on its own, without a reload.

## `colors.json`

The only generated file left, and it holds **colours only** — no hostnames, no
environments to keep in step with a cluster.

```bash
python3 utilities/make-env-badge-config.py
```

Re-run it when the colour convention changes or an environment is added, **not**
when a cluster is rebuilt. [`../env_colors.py`](../env_colors.py) stays the
single source of truth, shared with `make-env-logo.py` so the sign-in logo and
the masthead pill cannot drift apart; this file exists only because JavaScript
cannot import Python. CI regenerates it and fails the build if the committed
copy differs.

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
- **It stays off the sign-in page.** It used to paint there — redundant rather
  than wrong, when the environment came from the hostname and was known before
  login. Now the environment comes from an authenticated call, so pre-login the
  honest answer is "don't know yet", and a grey pill beside the correctly badged
  green logo would actively mislead. Suppressed by HTTP status, not by route.
- **One request per page load.** The environment cannot change under a live
  page, so the first successful answer is cached and no further calls are made.
  While it is still unknown, a 3-second poll retries — that is what makes the
  pill appear after login without a reload — and it stops itself the moment the
  environment is known. The MutationObserver repaints from the cached value and
  never re-fetches.
