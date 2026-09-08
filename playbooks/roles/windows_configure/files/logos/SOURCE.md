# Logo assets

Official Red Hat product logos, pulled from the Red Hat brand source at
`https://www.redhat.com/rhdc/managed-files/`:

| File | Upstream |
|---|---|
| `openshift.svg` | `Logo-Red_Hat-OpenShift-A-Reverse-RGB.svg` |
| `aap.svg` | `Logo-Red_Hat-Ansible_Automation_Platform-A-Reverse-RGB.svg` |

**Two marks, not three, and no Microsoft mark.** `roles/linux_configure` serves
`rhel.svg` alongside these because the guest *is* RHEL. This guest is not, and
the honest story is the one these two already tell: it runs **on** OpenShift
Virtualization and is configured **by** Ansible Automation Platform. A Windows
logo is not ours to redistribute, and the guest OS is named in the page's
headline and facts table anyway.

**Reverse variants on purpose** — they are white, and the demo page places them
on a dark band so the pair reads as one lockup.

**Copied, not shared with `linux_configure`.** A role cannot reach into another
role's `files/`, and duplicating two static assets is a far smaller risk than
duplicating a *value* — an SVG cannot silently disagree with its twin the way
the numbers behind #334, #342 and #352 did.

They are copied into the repo rather than linked because the page is served from
a cluster whose egress you do not control, in front of a customer. Anything
fetched at render time is a blank box waiting to happen.

Red Hat trademarks, used for a Red Hat product demo. Do not restyle or redraw
them; replace them from the same source if a newer version is published.
