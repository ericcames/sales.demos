---
name: sales-demos-env-urls
description: "Regenerate the environment URL reference file (inventory/env-urls.yml) — a single-file lookup of every product URL and optionally credentials across all environments. Runs playbooks/generate_env_urls.yml. TRIGGER when: the user has repointed an environment, asks for all the URLs, or env-urls.yml is stale or missing. SKIP: if the user only needs one specific URL — read connection.yml instead."
---

# sales-demos-env-urls

Regenerates `inventory/env-urls.yml` from the committed `connection.yml` files.
The file is gitignored — it contains credentials when generated with
`--with-creds` (#426, #429).

## There is an AAP path too (#525)

**AAP Ecosystem - Generate Environment URLs** runs this same playbook from AAP.
From AAP, credentials are omitted (the EE has no vault password file), but the
URLs appear in the job log — useful for verifying a repoint.

## Preflight Check

```bash
./utilities/preflight.sh "${ENV:-sandbox}"
```

Verify the Python script and its dependencies exist:

```bash
test -f utilities/generate-env-urls.py || { echo "MISSING: generate-env-urls.py"; exit 1; }
python3 -c "import yaml" 2>/dev/null || { echo "MISSING: pip install pyyaml"; exit 1; }
```

## Run

Default: generate with credentials (the full reference).

```bash
ENV="${ENV:-sandbox}"
mkdir -p ~/ansible-logs
export ANSIBLE_LOG_PATH=~/ansible-logs/generate-env-urls-$(date +%F-%H%M).log

./utilities/run-ansible.sh playbooks/generate_env_urls.yml -i inventory --limit "$ENV" \
  -e target_env="$ENV" \
  -e generate_env_urls_with_creds=true \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

Without credentials (URLs only):

```bash
./utilities/run-ansible.sh playbooks/generate_env_urls.yml -i inventory --limit "$ENV" \
  -e target_env="$ENV" \
  --vault-id sales.demos@~/secrets/.vault_pass_sales_demos
```

## Verify

Check that the output file exists and is current:

```bash
python3 utilities/generate-env-urls.py --check
```

This exits non-zero if the file is missing or the URLs in it don't match
what the current `connection.yml` files would produce.
