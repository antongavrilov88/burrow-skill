#!/usr/bin/env python3
"""Собирает самораспаковывающиеся установщики из params.json.

    python3 build-installers.py --params params.json --out ./out

Получается:
    out/setup-exit.sh   — выходная машина (или единственная, если mode=single)
    out/setup-relay.sh  — релей (только при mode=relay)

Каждый файл самодостаточен: внутри лежит весь код. Его можно передать
в cloud-init как user-data или просто выполнить на сервере от root.
"""
import argparse, base64, io, json, os, shutil, tarfile, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PAYLOAD = os.path.join(HERE, "payload")

WRAPPER = """#!/bin/bash
# Самораспаковывающийся установщик VPN ({role}). Сгенерирован vpn-kit.
# Запускать от root на чистой Ubuntu 24.04. Повторный запуск безопасен.
set -euo pipefail
touch /var/log/vpn-kit-install.log && chmod 600 /var/log/vpn-kit-install.log
exec > >(tee -a /var/log/vpn-kit-install.log) 2>&1
echo "=== vpn-kit {role}: старт $(date -Is)"
if [ "$(id -u)" != 0 ]; then echo "нужен root" >&2; exit 1; fi
command -v base64 >/dev/null || {{ apt-get update -qq && apt-get install -y -qq coreutils; }}
command -v tar >/dev/null || {{ apt-get update -qq && apt-get install -y -qq tar; }}
rm -rf /opt/vpn-kit && mkdir -p /opt/vpn-kit
base64 -d <<'__VPNKIT_PAYLOAD__' | tar xzf - -C /opt/vpn-kit
{payload}
__VPNKIT_PAYLOAD__
chmod -R go-rwx /opt/vpn-kit
bash /opt/vpn-kit/{entry}
echo "=== vpn-kit {role}: готово $(date -Is)"
"""

VAR_MAP = [
    ("ROLE", None), ("DOMAIN", "domain"), ("PUSH_DOMAIN", "push_domain"),
    ("ACME_EMAIL", "acme_email"), ("SITE_TITLE", "site_title"), ("SITE_TAGLINE", "site_tagline"),
    ("UUID_RELAY", "uuid_relay"), ("UUID_DIRECT", "uuid_direct"),
    ("REALITY_PRIVATE", "reality_private"), ("REALITY_PUBLIC", "reality_public"),
    ("SHORT_RELAY", "short_relay"), ("SHORT_DIRECT", "short_direct"),
    ("XHTTP_PATH", "xhttp_path"), ("XRAY_VERSION", "xray_version"), ("NTFY_VERSION", "ntfy_version"),
    ("NTFY_TOPIC", "ntfy_topic"), ("NTFY_USER", "ntfy_user"), ("NTFY_PASS", "ntfy_pass"),
    ("NTFY_PUBLIC_TOPIC", "ntfy_public_topic"),
    ("WG_SUBNET", "wg_subnet"), ("WG_PORT", "wg_port"), ("ALT_PORT", "alt_port"),
    ("CLIENT_DNS", "client_dns"), ("DASH_PORT", "dashboard_port"), ("DASH_TOKEN", "dashboard_token"),
    ("HOME_GEOIP", "home_geoip"), ("EXIT_IP", "exit_ip"), ("RELAY_IP", "relay_ip"),
]


def shq(v):
    return "'" + str(v).replace("'", "'\\''") + "'"


# Что НЕ должно попадать на релей: приватный ключ REALITY (он нужен только
# выходной машине) и личный запасной вход владельца.
RELAY_FORBIDDEN = {"REALITY_PRIVATE", "UUID_DIRECT", "SHORT_DIRECT", "NTFY_PASS", "ACME_EMAIL"}


def vars_sh(p, role):
    lines = ["# сгенерировано build-installers.py — не редактировать вручную"]
    for name, key in VAR_MAP:
        if role == "relay" and name in RELAY_FORBIDDEN:
            lines.append(f"{name}=''")
            continue
        val = role if key is None else p.get(key, "")
        lines.append(f"{name}={shq(val)}")
    # адрес, который клиенты пишут в Endpoint своего WireGuard
    endpoint = p.get("client_endpoint") or (p.get("relay_ip") if role == "relay" else p.get("exit_ip"))
    lines.append("CLIENT_ENDPOINT=" + shq(endpoint or ""))
    # сервер ntfy и токен для сторожа подставляются на выходной машине
    lines.append('NTFY_SERVER=' + shq(("https://" + p["push_domain"]) if p.get("push_domain") else ""))
    lines.append('NTFY_ALERT_TOKEN=' + shq(p.get("ntfy_alert_token", "")))
    return "\n".join(lines) + "\n"


def make(role, entry, parts, p, outdir, vars_role=None):
    with tempfile.TemporaryDirectory() as td:
        root = os.path.join(td, "kit")
        os.makedirs(root)
        for part in parts:
            shutil.copytree(os.path.join(PAYLOAD, part), os.path.join(root, part),
                            ignore=shutil.ignore_patterns("__pycache__", "*.pyc", ".DS_Store"))
        with open(os.path.join(root, "vars.sh"), "w", encoding="utf-8") as f:
            f.write(vars_sh(p, vars_role or role))
        buf = io.BytesIO()
        with tarfile.open(fileobj=buf, mode="w:gz") as t:
            for name in sorted(os.listdir(root)):
                t.add(os.path.join(root, name), arcname=name)
        b64 = base64.b64encode(buf.getvalue()).decode()
        wrapped = "\n".join(b64[i:i + 76] for i in range(0, len(b64), 76))
    os.makedirs(outdir, exist_ok=True)
    path = os.path.join(outdir, f"setup-{role}.sh")
    with open(path, "w", encoding="utf-8") as f:
        f.write(WRAPPER.format(role=role, payload=wrapped, entry=entry))
    os.chmod(path, 0o700)
    return path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--params", required=True)
    ap.add_argument("--out", default="./out")
    a = ap.parse_args()
    p = json.load(open(a.params, encoding="utf-8"))
    made = []
    if p.get("mode") == "single":
        made.append(make("exit", "exit/install.sh", ["common", "exit", "site"], p, a.out,
                         vars_role="single"))
    else:
        made.append(make("exit", "exit/install.sh", ["common", "exit", "site"], p, a.out))
        made.append(make("relay", "relay/install.sh", ["common", "relay"], p, a.out))
    for m in made:
        print(f"{m}  ({os.path.getsize(m)} байт)")


if __name__ == "__main__":
    main()
