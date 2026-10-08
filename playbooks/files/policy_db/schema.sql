-- Policy as Code evidence store (#851, #841 Phase 3c).
--
-- Applied by playbooks/install_policy_db.yml as the database superuser after
-- SET ROLE compliance, so the app role owns every table. IF NOT EXISTS keeps
-- a re-run harmless; it does not migrate a changed column, so a column change
-- needs its own ALTER here, never an edit to a CREATE.

-- The input a framework's policy grades, in the shape that policy expects.
-- One row per host and framework: fact shaping upserts, it does not append.
CREATE TABLE IF NOT EXISTS host_facts (
    host          text        NOT NULL,
    framework     text        NOT NULL,
    collected_at  timestamptz NOT NULL DEFAULT now(),
    facts         jsonb       NOT NULL,
    PRIMARY KEY (host, framework)
);

-- Every grading, kept. This is the history Grafana trends and the evidence an
-- auditor asks for, so the auditor appends rather than updates.
CREATE TABLE IF NOT EXISTS assessments (
    id                     bigserial   PRIMARY KEY,
    host                   text        NOT NULL,
    framework              text        NOT NULL,
    run_at                 timestamptz NOT NULL DEFAULT now(),
    compliant              boolean     NOT NULL,
    compliance_percentage  numeric(5,2),
    violations             jsonb       NOT NULL DEFAULT '[]'::jsonb
);

CREATE INDEX IF NOT EXISTS assessments_host_framework_run_at
    ON assessments (host, framework, run_at DESC);
