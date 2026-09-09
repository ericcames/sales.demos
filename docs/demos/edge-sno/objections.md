# Objections and questions — Edge / Single Node OpenShift

What this audience actually asks, and answers grounded in what the kit really
does. The full version with more detail is in the
[published guide](https://ericcames.github.io/sales.demos-docs/demos/edge-sno/objections/).

---

## "Why not just use RHDP?"

> **"RHDP gives you a running cluster. It doesn't show you the cluster getting
> there. For an edge conversation, the install story — unattended boot, Day 0
> operators, no manual steps — is the whole point. And RHDP environments expire.
> This one doesn't."**

---

## "What if my hardware is different?"

> **"The ISO generator takes nine hardware values as required inputs and
> validates them before it touches anything. Every hardware-specific value — IP,
> MAC, disk device, NIC name, hostname — is a parameter, not a hardcoded
> default. If your hardware meets the minimums (32 GB RAM, 120 GB disk, 8 CPUs,
> x86_64), it should work."**

If they ask about ARM: SNO supports ARM, but this kit has not been tested on
it. Say so honestly.

---

## "Can I run just Virt without AAP?"

> **"Today the kit installs all four operators. We're adding operator selection
> profiles — `--profile virt-only` would give you CNV and LVMS without AAP.
> That's tracked in the repo and coming soon."**

Link: [image.builder.pipeline#108](https://github.com/ericcames/image.builder.pipeline/issues/108)

---

## "How do I update OCP on this?"

> **"The same way you update any OpenShift cluster — through the console or
> `oc adm upgrade`. SNO does an in-place update: the node cordons itself,
> applies the update, and uncordons. Workloads go down during the reboot."**

---

## "What about disconnected installs?"

> **"This kit requires network access at install time — the ABI ISO pulls
> container images from the Red Hat registries during bootstrap. A fully
> disconnected install needs a mirror registry, and this kit does not set
> one up."**

---

## "Is this production-ready?"

> **"This is a demo platform, not a production reference architecture. It runs
> on one disk with no redundancy, DNS is dnsmasq on a laptop, and there's no
> backup strategy. The automation is production-quality — idempotent,
> tested, in version control — but the infrastructure it runs on is a home
> lab."**

---

## "How do you manage fifty of these?"

> **"You don't, with this tool. At scale you'd use Red Hat Advanced Cluster
> Management and Zero Touch Provisioning. What this demonstrates is that the
> platform deploys unattended, which is the prerequisite for ZTP."**

---

## "Can I have this?"

> **"Yes. Both repos are public. Clone them, follow the run sheet, and you'll
> have your own environment."**

---

## Things not to say

- **"This replaces VMware at the edge."** It might, but that is their conclusion
  to reach, not yours to claim.
- **"Zero touch."** It is not. Say "unattended".
- **"It scales to hundreds of sites."** This kit does not. RHACM + ZTP does.
- **"The same as production."** It is the same automation. It is not the same
  infrastructure. Say which one you mean.
