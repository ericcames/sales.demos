# Tests for decision_log_mask.rego. Run in the opa-test-mask initContainer on
# every rollout, so a broken mask fails the rollout rather than leaking.
package system.log_test

import data.system.log

test_values_redacted_keys_kept if {
	m := log.mask with input as {"input": {"extra_vars": {"greeting": "hello", "db_password": "s3cret"}}}
	{"op": "upsert", "path": "/input/extra_vars/db_password", "value": "**REDACTED**"} in m
	{"op": "upsert", "path": "/input/extra_vars/greeting", "value": "**REDACTED**"} in m
	count(m) == 2
}

test_unsafe_key_erases_whole_object if {
	m := log.mask with input as {"input": {"extra_vars": {"a/b": "x", "db_password": "s3cret"}}}
	m == {"/input/extra_vars"}
}

test_no_extra_vars_masks_nothing if {
	m := log.mask with input as {"input": {"name": "Policy as Code - Hello"}}
	count(m) == 0
}

test_empty_extra_vars_masks_nothing if {
	m := log.mask with input as {"input": {"extra_vars": {}}}
	count(m) == 0
}
