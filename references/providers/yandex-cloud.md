# Yandex Cloud

*Written 2026-09-24 from the console and pricing pages as known at that date, not re-verified live. Tested by this skill: as a relay, by hand.*

| | |
|---|---|
| **Layer** | **relay only.** It is inside the country; it must never be the exit. |
| **Automation** | Manual. The platform has an API and the `yc` CLI, but this skill does not drive them. |
| **Machine** | Compute Cloud VM: **Ubuntu 24.04**, 2 vCPU at **20% core share**, 1 GB RAM, 10 GB HDD, a **public IPv4** — the cheapest configuration, on the order of 300–600 ₽ a month at last check. Egress traffic beyond the free allowance is billed per gigabyte and is the line item that surprises people: the free allowance was 100 GB a month in the original notes and may be smaller now — check the pricing page — and a family watching video passes it either way. Count before you promise a price; a flat-rate VPS (`provisioning.md`, relay-capable hosts) avoids the question. |
| **Payment** | Cards of the local banking system, corporate invoices. Requires a Yandex ID. New accounts get a starter grant — do not rely on it for the monthly figure. |
| **Known blocked ranges** | Not applicable — the address is domestic, which is the point. What can happen instead is that the provider, being legally obliged to follow local filtering orders, starts dropping the tunnel to the exit: that is why the relay profile has a watchdog that fails everyone over to the direct route and back. |
| **Quirks** | The login is the user you name when creating the VM, **not root**, with passwordless `sudo`: the two lines become `scp … <user>@<IP>:~/` and `ssh <user>@<IP> 'sudo bash ~/setup-relay.sh'`. The metadata **user-data** field exists — **do not** put the relay installer in it: metadata is readable by any local process and the relay installer carries the panel code and the tunnel identifiers. Deliver it over SSH. |

## Click paths

**Account** — `console.yandex.cloud` → sign in with a Yandex ID → create a billing account → attach a card.

**VM (§6)** — **Compute Cloud → Virtual machines → Create VM** → image **Ubuntu 24.04** → availability zone: any → Computing resources: platform **Intel Ice Lake** (or whatever offers a **20%** core fraction), **2 vCPU**, **1 GB** → Network settings: **Public address: Auto** → Access: **Login** (a name), **SSH key**: paste the public key you generated (`~/.ssh/vpn-kit.pub`) or the person's own → Name `vpn-relay` → **Create VM**. The public IP is on the VM's page.

**Then** — rebuild the installers once `exit_ip` and `ntfy_alert_token` are in `params.json`, deliver `setup-relay.sh` over SSH, run it with `sudo`, `vpn-verify.sh`, and `relay_ip` into `params.json`.
