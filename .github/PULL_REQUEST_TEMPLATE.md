## Summary

<!-- What does this PR add or change, and why? -->

## Test plan

<!-- How was this validated? e.g. yamllint + ansible-lint pass, terraform plan
     clean, playbook run against the sandbox environment, skill invoked. -->

## Risk / rollback

<!-- Blast radius and how to undo. Which environment does it touch? -->

## Checklist

- [ ] No credentials in plaintext — they belong in the vault-encrypted `playbooks/group_vars/all/secrets.yml`
- [ ] **No customer or company data** anywhere, including the commit message and PR body
- [ ] Non-secret per-environment values (hostnames, API URLs, namespaces) go in the committed `connection.yml`, *not* the vault
- [ ] RHDP `*.dyn.redhatworkshops.io` URLs left as they are — they are committed on purpose, not placeholders to restore
- [ ] `bash utilities/check-no-secrets.sh` passes
- [ ] `yamllint .` and `ansible-lint` pass locally
- [ ] Any new skill uses only `name` / `description` / `license` frontmatter and is listed in `README.md`
- [ ] Survey vars, skill prompts, and playbook `extra_vars` use matching names
- [ ] Any playbook creating a token deletes it in an `always:` block
- [ ] `CHANGELOG.md` updated under `[Unreleased]`
- [ ] `CLAUDE.md` updated if a convention changed

## Related issues

<!-- Closes #NN -->
