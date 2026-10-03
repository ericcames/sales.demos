# Decision-log mask for AAP Policy as Code (#841).
#
# OPA runs this policy against every decision-log event before it is written,
# and removes or rewrites whatever paths `mask` names. Without it the pod log
# holds every extra_var VALUE AAP sends, measured on sandbox: the db_password
# typed for the demo sat there in the clear.
#
# Keys are kept and values are replaced, so the log still shows WHICH variable
# a policy acted on (the demo beat) without showing what was typed. Survey
# password answers already arrive masked by AAP; this covers everything else.
#
# A key containing "/" or "~" cannot be named safely as a JSON pointer
# segment, so if one is present the whole extra_vars object is erased instead.
# Failing towards hiding more, not less.
#
# Ours, not the library's: rego_policy_libraries holds decisions, and this is
# platform plumbing. It is loaded at OPA's default mask path,
# data.system.log.mask.
package system.log

redacted := "**REDACTED**"

_unsafe_key(k) if regex.match(`[/~]`, k)

_extra_vars := object.get(input, ["input", "extra_vars"], {})

mask contains "/input/extra_vars" if {
	some k, _ in _extra_vars
	_unsafe_key(k)
}

mask contains {"op": "upsert", "path": concat("/", ["", "input", "extra_vars", k]), "value": redacted} if {
	not _any_unsafe_key
	some k, _ in _extra_vars
}

_any_unsafe_key if {
	some k, _ in _extra_vars
	_unsafe_key(k)
}
