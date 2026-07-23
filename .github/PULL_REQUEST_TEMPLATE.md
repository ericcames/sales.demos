## Summary

<!-- What does this PR add or change, and why? -->

## Test plan

<!-- How was this validated? e.g. yamllint + ansible-lint pass, terraform plan
     clean, playbook run against the sandbox environment, skill invoked. -->

## Risk / rollback

<!-- Blast radius and how to undo. Which environment does it touch? -->

## Checklist

- [ ] No tokens, passwords, or secrets committed
- [ ] No RHDP hostname, cluster ID, or customer data — generic placeholders only
- [ ] Environment-specific values go in the gitignored `secrets.yml`, not `connection.yml`
- [ ] `bash utilities/check-no-secrets.sh` passes
- [ ] `yamllint .` and `ansible-lint` pass locally
- [ ] Any new skill uses only `name` / `description` / `license` frontmatter and is listed in `README.md`
- [ ] Survey vars, skill prompts, and playbook `extra_vars` use matching names
- [ ] Any playbook creating a token deletes it in an `always:` block
- [ ] `CHANGELOG.md` updated under `[Unreleased]`
- [ ] `CLAUDE.md` updated if a convention changed

## Related issues

<!-- Closes #NN -->
