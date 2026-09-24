# Alibaba Cloud

*Written 2026-09-24 from the international console and pricing pages as known at that date, not re-verified live. Tested by this skill: not yet.*

| | |
|---|---|
| **Layer** | **relay or exit**, depending on where the users are: regions in East and Southeast Asia, the Middle East, Europe and the Americas. As a relay it is a home-country relay for users in the same country; as an exit, pick a region outside their country. |
| **Last verified** | 2026-09-24 (pages read, not tested). |
| **Automation** | Manual. The person creates the instance in the console; you install over SSH. |
| **Machine** | **ECS** burstable instance (`ecs.t6` / `ecs.t5` class), 1 vCPU / 1 GB, image **Ubuntu 24.04 64-bit**, a **public IPv4** with **pay-by-traffic** bandwidth billing; or the **Simple Application Server** product, which bundles a monthly traffic quota at a flat price and is the better fit for a relay. Egress is billed per gigabyte on ECS — count before promising a price. |
| **Signup** | Email or phone, then account verification: **an ID document or a card** on the international site; mainland-China regions require real-name verification with a local ID. Region choice is locked to the account type — the international account and the mainland account are different signups. |
| **Payment** | International cards, PayPal, Alipay on the international site; local cards and Alipay on the mainland site. New accounts may be asked for a prepaid balance. |
| **Known blocked ranges** | Nothing systematic known outside the provider's own home market; individual addresses get blocked as anywhere. Mainland regions cannot serve a website on `80/443` without a hosting filing, so they are unsuitable as an exit (the cover site would be cut) — fine as a relay, which serves nothing on those ports to the outside. |
| **Firewall** | **Security groups**, mandatory: the default group allows only `22` tcp inbound. Add inbound rules for the layer — exit `22/80/443` tcp plus `443/51821` udp in the `single` profile; relay `22` tcp and `443/51821` udp. Without the rules the installer finishes and nothing connects. |
| **Quirks** | Root login with a password is on by default; set an SSH key at creation and let the installer harden the rest. The instance's **user data** field is cloud-init and is readable by any local process: acceptable for the exit installer only. Bandwidth billing "pay-by-bandwidth" caps throughput at the chosen Mbps; "pay-by-traffic" does not. Time zone and mirrors of the stock image point at the provider's own repositories — apt works, just slower for the first update. |

## Click paths

**Account** — `alibabacloud.com` → **Free Account** → email or phone → confirm → **Account verification** (ID or card) → **Billing** → add a payment method.

**Instance** — **Elastic Compute Service → Instances → Create Instance** → Billing method **Pay-as-you-go** → Region (home country for a relay, abroad for an exit) → Instance type: the smallest burstable → Image **Ubuntu 24.04 64-bit** → Public IP: **Assign**, billing **Pay-by-traffic** → **Security group**: create one and add the inbound rules above → Logon credentials: **Key pair** (upload the public key from `~/.ssh/vpn-kit.pub` or the person's own) → Instance name `vpn-exit` or `vpn-relay` → **Create**. The public IP is on the instance page.

**Then** — exit: DNS at the registrar (three A records `@`, `www`, `push`, TTL 300), `dns-check`, `setup-exit.sh` over SSH as root. Relay: rebuild the installers once `exit_ip` and `ntfy_alert_token` are in `params.json`, `setup-relay.sh` over SSH, `vpn-verify.sh`, `relay_ip` into `params.json`.
