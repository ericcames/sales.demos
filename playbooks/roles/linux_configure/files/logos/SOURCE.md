# Logo assets

Official Red Hat product logos, pulled from the Red Hat brand source at
`https://www.redhat.com/rhdc/managed-files/`:

| File | Upstream |
|---|---|
| `rhel.svg` | `Logo-Red_Hat-Enterprise_Linux-A-Reverse-RGB.svg` |
| `openshift.svg` | `Logo-Red_Hat-OpenShift-A-Reverse-RGB.svg` |
| `aap.svg` | `Logo-Red_Hat-Ansible_Automation_Platform-A-Reverse-RGB.svg` |

**Reverse variants on purpose** — they are white, and the demo page places all
three on a dark band so the set reads as one lockup rather than three mismatched
marks.

They are copied into the repo rather than linked because the page is served from
a cluster whose egress you do not control, in front of a customer. Anything
fetched at render time is a blank box waiting to happen.

Red Hat trademarks, used for a Red Hat product demo. Do not restyle or redraw
them; replace them from the same source if a newer version is published.
