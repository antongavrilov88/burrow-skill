#!/usr/bin/env python3
"""Rebuild Xray routing on the relay from the operator-editable domain list.

Domains in the list (and, optionally, the home country's IP ranges) leave straight
from the relay; everything else goes through the REALITY tunnel to the exit machine.
"""
import json, os, subprocess, sys

CFG = "/usr/local/etc/xray/config.json"
LIST = "/etc/vpn-monitor/direct-domains.txt"
CONFIG = "/etc/vpn-monitor/config.json"

try:
    HOME_GEOIP = json.load(open(CONFIG)).get("home_geoip", "")
except Exception:
    HOME_GEOIP = ""


def load_domains():
    out = []
    if os.path.exists(LIST):
        for raw in open(LIST, encoding="utf-8"):
            d = raw.split("#")[0].strip().lower().lstrip(".")
            if d and d not in out:
                out.append(d)
    return out


def build(cfg, domains, home_geoip=HOME_GEOIP):
    rules = [
        {"type": "field", "inboundTag": ["tproxy-in"], "network": "udp",
         "port": 443, "outboundTag": "block"},
    ]
    if domains:
        rules.append({"type": "field", "domain": ["domain:" + d for d in domains],
                      "outboundTag": "direct"})
    if home_geoip:
        rules.append({"type": "field", "ip": ["geoip:" + home_geoip], "outboundTag": "direct"})
    rules.append({"type": "field", "inboundTag": ["tproxy-in", "socks-test"],
                  "outboundTag": "proxy"})
    cfg["routing"] = {"domainStrategy": "IPIfNonMatch", "rules": rules}
    return cfg


def main():
    cfg = json.load(open(CFG))
    domains = load_domains()
    cfg = build(cfg, domains)
    tmp = CFG.replace(".json", ".new.json")
    json.dump(cfg, open(tmp, "w"), indent=2, ensure_ascii=False)
    r = subprocess.run(["xray", "run", "-test", "-c", tmp], capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        print("config invalid, not applied:\n" + r.stdout[-800:] + r.stderr[-800:], file=sys.stderr)
        os.remove(tmp)
        return 1
    os.replace(tmp, CFG)
    subprocess.run(["systemctl", "restart", "xray"], timeout=60)
    print(f"applied: {len(domains)} direct domains" + (f" + geoip:{HOME_GEOIP}" if HOME_GEOIP else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
