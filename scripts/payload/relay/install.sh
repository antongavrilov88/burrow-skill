#!/bin/bash
# Установка релея: WireGuard для клиентов, прозрачный перехват их трафика в Xray,
# оттуда — VLESS + XHTTP + REALITY до выходной машины. Плюс дашборд, сторож и учения.
set -euo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$KIT/vars.sh"
export DEBIAN_FRONTEND=noninteractive
log() { echo "[$(date +%H:%M:%S)] $*"; }
die() { echo "ОШИБКА: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die "запускать от root"

log "ставлю пакеты"
APT="apt-get -o DPkg::Lock::Timeout=600 -y -qq"
for i in 1 2 3; do $APT update && break || { log "apt update не удался ($i), жду"; sleep 20; }; done
$APT install curl ca-certificates nftables wireguard-tools qrencode python3 iproute2 jq

# ---------------------------------------------------------------- Xray
if ! command -v xray >/dev/null || ! xray version 2>/dev/null | grep -q "${XRAY_VERSION#v}"; then
  log "ставлю Xray $XRAY_VERSION"
  bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" \
    @ install --version "${XRAY_VERSION#v}" >/dev/null
fi
command -v xray >/dev/null || die "Xray не установился"

# ---------------------------------------------------------------- клиент REALITY
[ -n "$EXIT_IP" ] || die "в установщике не задан адрес выходной машины. Впиши exit_ip в params.json и пересобери: python3 scripts/build-installers.py --params params.json --out ./out"
log "конфигурирую Xray (клиент REALITY → $EXIT_IP)"
install -d -m755 /usr/local/etc/xray
python3 - <<PY
import json
cfg = {
  "log": {"loglevel": "warning", "access": "none", "error": "", "dnsLog": False},
  "inbounds": [
    {"tag": "tproxy-in", "listen": "0.0.0.0", "port": 12345, "protocol": "dokodemo-door",
     "settings": {"network": "tcp,udp", "followRedirect": True},
     "streamSettings": {"sockopt": {"tproxy": "tproxy"}},
     "sniffing": {"enabled": True, "destOverride": ["http", "tls", "quic"], "routeOnly": True}},
    {"tag": "socks-test", "listen": "127.0.0.1", "port": 1080, "protocol": "socks",
     "settings": {"udp": True}}],
  "outbounds": [
    {"tag": "proxy", "protocol": "vless",
     "settings": {"vnext": [{"address": "$EXIT_IP", "port": 443,
                             "users": [{"id": "$UUID_RELAY", "encryption": "none"}]}]},
     "streamSettings": {
        "network": "xhttp", "security": "reality",
        "realitySettings": {"serverName": "$DOMAIN", "fingerprint": "chrome",
                            "password": "$REALITY_PUBLIC", "publicKey": "$REALITY_PUBLIC",
                            "shortId": "$SHORT_RELAY", "spiderX": "/"},
        "xhttpSettings": {"path": "$XHTTP_PATH", "mode": "auto"},
        "sockopt": {"mark": 255}}},
    {"tag": "direct", "protocol": "freedom", "streamSettings": {"sockopt": {"mark": 255}}},
    {"tag": "block", "protocol": "blackhole"}],
  "routing": {"domainStrategy": "IPIfNonMatch", "rules": [
    {"type": "field", "inboundTag": ["tproxy-in"], "network": "udp", "port": 443,
     "outboundTag": "block"},
    {"type": "field", "inboundTag": ["tproxy-in", "socks-test"], "outboundTag": "proxy"}]}
}
json.dump(cfg, open("/usr/local/etc/xray/config.json", "w"), indent=2)
PY
xray run -test -c /usr/local/etc/xray/config.json >/dev/null || die "конфиг Xray не проходит проверку"

# ---------------------------------------------------------------- перехват трафика
log "правила перехвата"
install -d -m755 /etc/xray
MYIP=$(curl -s -m 10 https://api.ipify.org || ip -o -4 addr show scope global | awk '{print $4}' | cut -d/ -f1 | head -1)
# Если файл уже есть — сохраняем действующий состав proxied_src: повторный
# запуск установщика не должен молча снимать всех клиентов с туннеля.
KEEP=$(python3 - <<'PYEOF' || true
import re
try:
    src = open("/etc/xray/xray-tproxy.nft").read()
    m = re.search(r"set proxied_src \{[^}]*elements = \{([^}]*)\}", src, re.S)
    print(", ".join(re.findall(r"[\d./]+", m.group(1))) if m else "")
except Exception:
    print("")
PYEOF
)
ELEMENTS=""
[ -n "$KEEP" ] && ELEMENTS="
        elements = { $KEEP }"
[ -n "$KEEP" ] && log "сохраняю действующий состав туннеля: $KEEP"
cat > /etc/xray/xray-tproxy.nft <<EOF
#!/usr/sbin/nft -f
# Заворачиваем трафик выбранных клиентов wg-clients в Xray (dokodemo-door :12345).
# proxied_src — кто идёт через туннель. Кого здесь нет, тот выходит напрямую с релея.
table ip xray_tproxy
delete table ip xray_tproxy
table ip xray_tproxy {
    set proxied_src {
        type ipv4_addr
        flags interval$ELEMENTS
    }
    set bypass {
        type ipv4_addr
        flags interval
        elements = { 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16,
                     172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 240.0.0.0/4,
                     $MYIP, $EXIT_IP }
    }
    chain prerouting {
        type filter hook prerouting priority mangle; policy accept;
        iifname != "wg-clients" return
        ip saddr != @proxied_src return
        ip daddr @bypass return
        meta l4proto { tcp, udp } tproxy to :12345 meta mark set 1 accept
    }
}
EOF

# ---------------------------------------------------------------- фаервол
# Своя таблица, без flush ruleset: xray_tproxy, wgports и vpnnat живут отдельно.
cat > /etc/nftables.conf <<EOF
#!/usr/sbin/nft -f
table inet filter
delete table inet filter
table inet filter {
    chain input {
        type filter hook input priority filter; policy drop;
        ct state established,related accept
        iif lo accept
        iifname "wg-clients" accept
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept
        tcp dport 22 accept
        udp dport { $WG_PORT, $ALT_PORT } accept
    }
    chain forward { type filter hook forward priority filter; policy accept; }
    chain output  { type filter hook output  priority filter; policy accept; }
}
EOF
nft -f /etc/nftables.conf
systemctl enable --now nftables >/dev/null 2>&1 || true

# ---------------------------------------------------------------- клиентская часть
# (создаёт wg-clients и /etc/xray/wgports.nft, который нужен следующему юниту)
bash "$KIT/common/install-clientside.sh"

# ---------------------------------------------------------------- юниты и запуск
install -m644 "$KIT/relay/systemd/"*.service "$KIT/relay/systemd/"*.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable xray xray-tproxy-route >/dev/null 2>&1
systemctl restart xray-tproxy-route
systemctl restart xray

# ---------------------------------------------------------------- разделение маршрутов
log "разделение маршрутов"
python3 /usr/local/sbin/vpn-split.py || die "vpn-split не отработал"

# сторож — последним, когда туннель уже поднят
systemctl restart vpn-watchdog
systemctl enable --now vpn-drill.timer vpn-drill-check.timer >/dev/null 2>&1 || true

# ---------------------------------------------------------------- проверка
log "проверяю туннель"
sleep 4
OUTIP=$(curl -s -m 20 -x socks5h://127.0.0.1:1080 https://api.ipify.org || true)
echo
echo "=== РЕЛЕЙ ГОТОВ ==="
systemctl is-active xray vpn-monitor vpn-watchdog xray-tproxy-route wg-quick@wg-clients 2>/dev/null | tr '\n' ' ' || true; echo
if [ "$OUTIP" = "$EXIT_IP" ]; then
  echo "туннель работает: выход виден как $OUTIP"
else
  echo "ВНИМАНИЕ: через туннель наружу видно '$OUTIP', ожидалось '$EXIT_IP'."
  echo "Смотри: journalctl -u xray -n 40  и  /usr/local/sbin/vpn-diag.sh"
fi
echo "дашборд: http://$WG_SUBNET.1:$DASH_PORT (изнутри VPN), код $DASH_TOKEN"
