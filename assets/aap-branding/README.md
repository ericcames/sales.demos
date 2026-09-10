# AAP branding assets

**These are AAP gateway configuration inputs, not documentation.** They look
like screenshots. They are not. `playbooks/config.yml` reads two of them at run
time, and deleting them breaks it.

They used to live in `docs/images/`, mixed in with talk-track screenshots. When
the documentation images moved to
[sales.demos-docs](https://github.com/ericcames/sales.demos-docs) (#422), a
sweep of "images already duplicated in the docs repo" would have taken
`aap-logo-white.svg` with them — it is byte-identical over there — and
`make-env-logo.py` would have stopped working with nothing to explain why. Hence
a directory whose name says what these are.

## What reads what

| File | Read by | When |
|---|---|---|
| `logo-sandbox.png.b64` | `inventory/group_vars/sandbox/gateway_settings.yml` | **Playbook run time**, including from AAP's SCM checkout |
| `logo-demo.png.b64` | `inventory/group_vars/demo/gateway_settings.yml` | Same |
| `logo-<env>.png` | `utilities/make-env-logo.py` | Build time — the source of the `.b64` beside it |
| `aap-logo-white.svg` | `utilities/make-env-logo.py` (`SOURCE_SVG`) | Build time — the artwork the badge is composed onto |

The lookup is an absolute path built from `inventory_dir`:

```yaml
custom_logo: "data:image/png;base64,{{ lookup('ansible.builtin.file',
  inventory_dir + '/../assets/aap-branding/logo-sandbox.png.b64') }}"
```

**`.b64` exists because `custom_logo` takes a `data:` URI**, not a file. It is
committed rather than encoded on the fly so that applying the configuration
needs no ImageMagick, and so the `.png` renders on GitHub.

## Regenerating

```bash
python3 utilities/make-env-logo.py --env sandbox
```

Writes both `logo-<env>.png` and its `.b64` sidecar. Needs Pillow, ImageMagick
with the librsvg delegate, and the Red Hat Display font. Commit both.

**CI checks that each `.b64` is the base64 of the `.png` beside it**
(`utilities/check-env-logos.py`). It deliberately does **not** regenerate the
PNG to compare: that needs ImageMagick, librsvg and a specific font, and font
rasterisation is not byte-reproducible across machines — the same reason
`check-docs-artifacts.py` skips `demo-page.png`. The check catches the drift
that actually happens: someone replaces the PNG, forgets the sidecar, and AAP
serves the old logo while git looks correct.

## What this changes, and what it does not

`custom_logo` marks the **sign-in page only**. The post-login masthead is a
bundled UI asset, not a setting — re-measured in
[#54](https://github.com/ericcames/sales.demos/issues/54) with `custom_logo`
applied, and none of the 44 gateway settings marks the environment after login.
Marking it post-login is `utilities/aap-env-badge/`, a browser extension.

**`edge` has no logo here**, because `inventory/group_vars/edge/` has no
`gateway_settings.yml`. Nothing sets `custom_logo` on that cluster.

## Verifying a change

A `file` lookup that resolves to the wrong-but-existing file reports `changed`
and looks green. Apply it and **look at the sign-in page**:

```bash
ansible-playbook playbooks/validate.yml --check -i inventory --limit sandbox \
  -e target_env=sandbox --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```
