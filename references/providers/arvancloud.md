# ArvanCloud

*Written 2026-09-24 from the provider's public pages as known at that date, not re-verified live. Tested by this skill: not yet.*

| | |
|---|---|
| **Layer** | **relay or exit**: data centers inside the provider's home country and a few abroad. For users in that country it is a home-country relay (pick a domestic data center); a data center abroad can serve as an exit for them, with the caveat below. |
| **Last verified** | 2026-09-24 (pages read, not tested). |
| **Automation** | Manual. The person creates the instance in the panel; you install over SSH. |
| **Machine** | **Cloud Server** (the IaaS product), the smallest general plan: 1 vCPU / 1 GB, image **Ubuntu 24.04**, a **public IPv4** (assigned at creation — keep it on). Traffic is metered per plan; check the quota, a relay passes everything twice. |
| **Signup** | Email and a **local mobile number** for confirmation; **identity verification** (national ID) is required to activate billing on the local site. There is no separate international signup at last check — tell the person up front. |
| **Payment** | Local cards in local currency; some resellers take crypto. Prepaid balance model: top up, then spend. |
| **Known blocked ranges** | The domestic ranges are, by definition, reachable on carrier-restricted networks in that country — that is the point of a relay there. The foreign data centers belong to a provider that answers to that country's law: as an exit they are reachable but not independent, say so in one sentence (same note as for other home-registered hosts in `provisioning.md`). |
| **Firewall** | **Security groups** in the panel; the default group is restrictive. Add inbound rules for the layer — relay `22` tcp and `443/51821` udp; exit `22/80/443` tcp plus `443/51821` udp in the `single` profile. |
| **Quirks** | The panel and documentation are in the local language first; the English switch is at the top of the page. Not verified here: whether images ship with a pre-enabled firewall (`ufw`) and whether a cloud-init field exists — run the checks in `providers/generic-ubuntu.md` before installing, and if a user-data field exists, use it for the exit installer only, never the relay's. Plans are prepaid: a relay with an exhausted balance stops without warning — put the top-up date in the handout. |

## Click paths

**Account** — the provider's site → **Sign up** → mobile number → confirmation code → complete identity verification → **Wallet** → top up.

**Instance** — **Cloud Server → Create** → Data center (domestic for a relay) → Image **Ubuntu 24.04** → the smallest plan → **Public IP: on** → **SSH key**: paste the public key from `~/.ssh/vpn-kit.pub` (or the person's own) → **Security group**: add the inbound rules above → Name `vpn-relay` (or `vpn-exit`) → **Create**. The IP is on the instance page.

**Then** — relay: rebuild the installers once `exit_ip` and `ntfy_alert_token` are in `params.json`, `setup-relay.sh` over SSH, `vpn-verify.sh`, `relay_ip` into `params.json`. Exit: DNS records, `dns-check`, `setup-exit.sh` over SSH as root.
