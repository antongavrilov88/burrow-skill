# Vultr

*Written 2026-09-24 from public pricing and billing pages as known at that date, not re-verified live. Tested by this skill: not yet.*

| | |
|---|---|
| **Layer** | **exit**. Thirty-odd locations on every continent; still not a relay, because none of them are inside the filtered countries this profile exists for. |
| **Automation** | Manual. The person deploys in the console; you install over SSH (a startup script is possible but untested here). |
| **Machine** | **Cloud Compute → Regular Performance**, 1 vCPU / 1 GB, $5–6/month with 1–2 TB of traffic depending on the location. Ubuntu 24.04 is a stock image. |
| **Payment** | Cards, PayPal, Alipay, WeChat Pay and **cryptocurrency** (through a payment processor) — one of the few mainstream providers that takes crypto. New accounts often have to prepay a deposit and are limited to a handful of instances at first. Check the billing page on the day: methods come and go by country. |
| **Known blocked ranges** | Nothing systematic known; individual addresses get blocked as anywhere, and some Vultr ranges carry a reputation from earlier abuse — if a fresh instance's IP is unreachable from the users' country, redeploy in another location. |
| **Quirks** | IPv6 is optional; leave it on. The console offers **Startup Scripts** and a **Cloud-Init User-Data** field at deploy time; SSH is the path this skill has verified for manual providers. |

## Click paths

**Account** — `my.vultr.com/register` → sign up → confirm the email → **Billing** → add a payment method and, if asked, the initial deposit.

**Server** — **Deploy +** → **Deploy New Server** → **Cloud Compute** → **Regular Performance** → Location → Image **Ubuntu 24.04 LTS** → the cheapest plan → **SSH Keys**: add the public key from `~/.ssh/vpn-kit.pub` (or the person's own) → Server Hostname & Label `vpn-exit` → **Deploy Now**. The IP appears on the instance page once it is running.

**Then** — DNS at the registrar (three A records `@`, `www`, `push`, TTL 300), `dns-check`, `setup-exit.sh` over SSH as root.
