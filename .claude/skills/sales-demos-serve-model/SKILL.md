---
name: sales-demos-serve-model
description: "Deploy a model on the GPU cluster and publish the inference endpoint to AAP. Runs playbooks/serve_model.yml against --limit gpu,<env>. Creates namespace, downloads weights to a PVC, deploys a vLLM ServingRuntime with RHOAI/KServe, exposes an authenticated Route, and publishes the credential to AAP as 'Sales Demos - Inference Endpoint'. TRIGGER when: the user wants to serve a model, deploy AI/inference, set up the GPU cluster, or get a model running. SKIP: if the model is already serving and the user wants to change model parameters — that is teardown then re-serve."
---

# sales-demos-serve-model

Phase 1 of #661. Deploys a model on the GPU cluster and publishes the
endpoint to AAP so job templates can call inference.

This skill contains **no logic**. All the work is in
[`playbooks/serve_model.yml`](../../../playbooks/serve_model.yml), which
creates all K8s resources on the GPU cluster and publishes the credential to
AAP. See `CLAUDE.md` → *Skills and playbooks*.

## Preflight Checks

```bash
# 1. Vault password exists
test -f "${SALES_DEMOS_VAULT_PASS:-$HOME/secrets/.vault_pass_sales_demos}" \
  || { echo "FAIL: vault password file not found"; exit 1; }

# 2. GPU connection is configured (local.yml or connection.yml)
python3 -c "
import yaml, sys, os
gvd = os.path.join(os.path.dirname(__file__), '..', '..', '..', 'inventory', 'group_vars', 'gpu')
for f in ['local.yml', 'connection.yml']:
    p = os.path.join(gvd, f)
    if os.path.exists(p):
        d = yaml.safe_load(open(p))
        url = d.get('openshift_api_url', '')
        if '<id>' not in url and url:
            print(f'OK: GPU cluster configured in {f}'); sys.exit(0)
print('FAIL: GPU cluster not configured — copy local.yml.example to local.yml and fill in your cluster values')
sys.exit(1)
" 2>/dev/null || echo "Check GPU connection manually"

# 3. kubernetes.core collection is installed
python3 -c "import ansible; from ansible.utils.collection_loader import AnsibleCollectionConfig" 2>/dev/null \
  && ansible-galaxy collection list kubernetes.core 2>/dev/null | grep -q kubernetes.core \
  || echo "WARN: kubernetes.core collection may not be installed"
```

## Inputs

| Variable | Default | Description |
|---|---|---|
| `target_env` | — | **Required.** Which AAP environment receives the credential (`sandbox` or `demo`). |
| `serve_model_id` | `ibm-granite/granite-3.3-8b-instruct-FP8` | HuggingFace model ID. FP8 is the default — 72% faster than fp16 on the L4 (#686). |
| `serve_runtime_extra_args` | `[]` | Extra vLLM args (Phase 5 sets `--enable-auto-tool-choice --tool-call-parser granite`). |
| `serve_model_enable_lightspeed` | `false` | Enable the AAP Lightspeed intelligent assistant pointing at this model (#704). |

## Run

```bash
./utilities/run-playbook.sh playbooks/serve_model.yml \
  --limit gpu,sandbox -e target_env=sandbox
```

To also enable Lightspeed (Phase 4, #704):

```bash
./utilities/run-playbook.sh playbooks/serve_model.yml \
  --limit gpu,sandbox -e target_env=sandbox \
  -e serve_model_enable_lightspeed=true
```

To swap models:

```bash
./utilities/run-playbook.sh playbooks/teardown_model.yml \
  --limit gpu,sandbox -e target_env=sandbox

./utilities/run-playbook.sh playbooks/serve_model.yml \
  --limit gpu,sandbox -e target_env=sandbox \
  -e serve_model_id=ibm-granite/granite-4.0-micro
```

## Verification

After the playbook finishes, verify the endpoint is live:

```bash
# The playbook prints the Route hostname and runs a smoke test.
# To verify independently:
ROUTE=$(oc get route -n granite-serving -o jsonpath='{.items[0].spec.host}')
TOKEN=$(oc get secret aap-inference-client-token -n granite-serving -o jsonpath='{.data.token}' | base64 -d)
curl -sk -H "Authorization: Bearer $TOKEN" "https://$ROUTE/v1/models"
```

Verify the credential exists on AAP:

```bash
# Use the AAP MCP server
# mcp__aap-sandbox__credentials_list with search="Inference"
```

## Teardown

```bash
./utilities/run-playbook.sh playbooks/teardown_model.yml \
  --limit gpu,sandbox -e target_env=sandbox
```

Removes the `granite-serving` namespace (all K8s resources), disables
Lightspeed, deletes the chatbot Secret, and removes the AAP credential.
The credential TYPE is preserved.
