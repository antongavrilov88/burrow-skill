#!/bin/bash
# Установка выходной машины: VLESS + XHTTP + REALITY на 443, настоящий сайт под
# тем же доменом (self-steal), сертификаты, ntfy для уведомлений.
# При ROLE=single здесь же поднимается WireGuard для клиентов, дашборд и сторож.
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
PKGS="curl ca-certificates nginx certbot python3-certbot-nginx nftables jq unzip"
[ "$ROLE" = "single" ] && PKGS="$PKGS wireguard-tools qrencode python3 iproute2"
$APT install $PKGS

# ---------------------------------------------------------------- Xray
if ! command -v xray >/dev/null || ! xray version 2>/dev/null | grep -q "${XRAY_VERSION#v}"; then
  log "ставлю Xray $XRAY_VERSION"
  bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" \
    @ install --version "${XRAY_VERSION#v}" >/dev/null
fi
command -v xray >/dev/null || die "Xray не установился"

# ---------------------------------------------------------------- сайт-прикрытие
log "раскладываю сайт для $DOMAIN"
install -d -m755 "/var/www/$DOMAIN"
sed -e "s|__SITE_TITLE__|$SITE_TITLE|g" \
    -e "s|__SITE_TAGLINE__|$SITE_TAGLINE|g" \
    -e "s|__DOMAIN__|$DOMAIN|g" \
    -e "s|__DATE_1__|$(date -d '-8 days' +%d.%m.%Y 2>/dev/null || date +%d.%m.%Y)|g" \
    -e "s|__DATE_2__|$(date -d '-31 days' +%d.%m.%Y 2>/dev/null || date +%d.%m.%Y)|g" \
    -e "s|__DATE_3__|$(date -d '-74 days' +%d.%m.%Y 2>/dev/null || date +%d.%m.%Y)|g" \
    "$KIT/site/index.html" > "/var/www/$DOMAIN/index.html"

# ---------------------------------------------------------------- nginx :80 + сертификаты
log "nginx на 80 и сертификаты"
rm -f /etc/nginx/sites-enabled/default
cat > "/etc/nginx/sites-available/$DOMAIN-http" <<EOF
server {
    listen 80; listen [::]:80;
    server_name $DOMAIN${PUSH_DOMAIN:+ $PUSH_DOMAIN};
    root /var/www/$DOMAIN;
    location /.well-known/acme-challenge/ { allow all; }
    location / { return 301 https://\$host\$request_uri; }
}
EOF
ln -sf "/etc/nginx/sites-available/$DOMAIN-http" "/etc/nginx/sites-enabled/$DOMAIN-http"
nginx -t || die "конфиг nginx не проходит проверку"
systemctl reload nginx

certbot_for() {
  local d="$1"
  [ -d "/etc/letsencrypt/live/$d" ] && { log "сертификат для $d уже есть"; return 0; }
  for attempt in 1 2 3 4 5 6; do
    if certbot certonly --webroot -w "/var/www/$DOMAIN" -d "$d" \
         --non-interactive --agree-tos -m "$ACME_EMAIL" >/dev/null 2>&1; then
      log "сертификат для $d получен"; return 0
    fi
    log "сертификат для $d не вышел (попытка $attempt) — жду DNS, 60 с"
    sleep 60
  done
  return 1
}
certbot_for "$DOMAIN" || die "не удалось получить сертификат для $DOMAIN. Проверь, что A-запись $DOMAIN указывает на этот сервер, и запусти скрипт ещё раз."
PUSH_OK=0
if [ -n "${PUSH_DOMAIN:-}" ]; then certbot_for "$PUSH_DOMAIN" && PUSH_OK=1 || log "ntfy-домен без сертификата — уведомления пойдут через запасной публичный ntfy"; fi

# ---------------------------------------------------------------- nginx :8443 (цель self-steal)
cat > "/etc/nginx/sites-available/$DOMAIN-https" <<EOF
server {
    # сюда попадает только активное зондирование через REALITY и локальные запросы
    listen 127.0.0.1:8443 ssl;
    http2 on;
    server_name $DOMAIN;
    ssl_certificate     /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_tickets off;
    root /var/www/$DOMAIN;
    index index.html;
}
EOF
ln -sf "/etc/nginx/sites-available/$DOMAIN-https" "/etc/nginx/sites-enabled/$DOMAIN-https"

# ---------------------------------------------------------------- ntfy
NTFY_OK=0
if [ "$PUSH_OK" = 1 ] && [ -n "${NTFY_VERSION:-}" ]; then
  log "ставлю ntfy $NTFY_VERSION"
  ARCH=$(dpkg --print-architecture)
  if curl -fsSL -o /tmp/ntfy.deb \
      "https://github.com/binwiederhier/ntfy/releases/download/${NTFY_VERSION}/ntfy_${NTFY_VERSION#v}_linux_${ARCH}.deb"; then
    apt-get install -y -qq /tmp/ntfy.deb >/dev/null && rm -f /tmp/ntfy.deb
    install -d -m755 /etc/ntfy /var/lib/ntfy
    cat > /etc/ntfy/server.yml <<EOF
base-url: "https://$PUSH_DOMAIN"
listen-http: "127.0.0.1:2586"
cache-file: "/var/lib/ntfy/cache.db"
auth-file: "/var/lib/ntfy/user.db"
auth-default-access: "deny-all"
behind-proxy: true
EOF
    chown -R ntfy:ntfy /var/lib/ntfy 2>/dev/null || true
    systemctl enable ntfy >/dev/null 2>&1 || true
    systemctl restart ntfy >/dev/null 2>&1 || true
    sleep 3
    NTFY_PASSWORD="$NTFY_PASS" ntfy user add --role=user "$NTFY_USER" >/dev/null 2>&1 || true
    ntfy access "$NTFY_USER" "$NTFY_TOPIC" rw >/dev/null 2>&1 || true
    NTFY_PASSWORD="$(openssl rand -base64 18)" ntfy user add --role=user alerts >/dev/null 2>&1 || true
    ntfy access alerts "$NTFY_TOPIC" write-only >/dev/null 2>&1 || true
    ALERT_TOKEN=$(ntfy token add alerts 2>/dev/null | grep -o 'tk_[a-z0-9]*' | head -1 || true)
    chown -R ntfy:ntfy /var/lib/ntfy 2>/dev/null || true
    systemctl restart ntfy >/dev/null 2>&1 || true
    if [ -n "$ALERT_TOKEN" ]; then
      sed -i "s|^NTFY_ALERT_TOKEN=.*|NTFY_ALERT_TOKEN='$ALERT_TOKEN'|" "$KIT/vars.sh"
      NTFY_ALERT_TOKEN="$ALERT_TOKEN"
    fi
    cat > "/etc/nginx/sites-available/$PUSH_DOMAIN-https" <<EOF
server {
    listen 127.0.0.1:8443 ssl;
    http2 on;
    server_name $PUSH_DOMAIN;
    ssl_certificate     /etc/letsencrypt/live/$PUSH_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$PUSH_DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    client_max_body_size 20M;
    location / {
        proxy_pass http://127.0.0.1:2586;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_connect_timeout 3m; proxy_send_timeout 3m; proxy_read_timeout 3m;
        proxy_buffering off;
    }
}
EOF
    ln -sf "/etc/nginx/sites-available/$PUSH_DOMAIN-https" "/etc/nginx/sites-enabled/$PUSH_DOMAIN-https"
    NTFY_OK=1
  else
    log "не смог скачать ntfy — уведомления пойдут через публичный ntfy.sh"
  fi
fi
nginx -t || die "конфиг nginx не проходит проверку"
systemctl reload nginx

# ---------------------------------------------------------------- Xray: inbound REALITY
log "конфигурирую Xray"
install -d -m755 /usr/local/etc/xray
python3 - <<PY
import json
clients = [{"id": "$UUID_RELAY", "email": "relay"}]
if "$UUID_DIRECT":
    clients.append({"id": "$UUID_DIRECT", "email": "direct"})
short = [s for s in ["$SHORT_RELAY", "$SHORT_DIRECT"] if s]
cfg = {
  "log": {"loglevel": "warning", "access": "none", "error": "", "dnsLog": False},
  "inbounds": [{
    "tag": "vless-xhttp-reality", "listen": "0.0.0.0", "port": 443, "protocol": "vless",
    "settings": {"clients": clients, "decryption": "none"},
    "streamSettings": {
      "network": "xhttp", "security": "reality",
      "realitySettings": {"show": False, "target": "127.0.0.1:8443",
                          "serverNames": ["$DOMAIN"],
                          "privateKey": "$REALITY_PRIVATE", "shortIds": short},
      "xhttpSettings": {"path": "$XHTTP_PATH", "mode": "auto"}},
    "sniffing": {"enabled": True, "destOverride": ["http", "tls", "quic"]}}],
  "outbounds": [{"tag": "direct", "protocol": "freedom"},
                {"tag": "block", "protocol": "blackhole"}],
  "routing": {"domainStrategy": "AsIs",
              "rules": [{"type": "field", "ip": ["geoip:private"], "outboundTag": "block"}]}
}
if "$ROLE" == "single":
    # локальный socks: через него сторож проверяет, что машина вообще в сети
    cfg["inbounds"].append({"tag": "socks-test", "listen": "127.0.0.1", "port": 1080,
                            "protocol": "socks", "settings": {"udp": True}})
    cfg["routing"]["rules"].append({"type": "field", "inboundTag": ["socks-test"],
                                    "outboundTag": "direct"})
json.dump(cfg, open("/usr/local/etc/xray/config.json", "w"), indent=2)
PY
# В конфиге лежит приватный ключ REALITY. Xray бежит от nobody, поэтому 640
# с группой, а не 644: прочие локальные процессы читать его не должны.
chgrp nogroup /usr/local/etc/xray/config.json 2>/dev/null || true
chmod 640 /usr/local/etc/xray/config.json
xray run -test -c /usr/local/etc/xray/config.json >/dev/null || die "конфиг Xray не проходит проверку"
systemctl enable --now xray >/dev/null 2>&1
systemctl restart xray

# ---------------------------------------------------------------- обновление сертификатов
install -d -m755 /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/reload.sh <<'EOF'
#!/bin/sh
systemctl reload nginx || true
EOF
chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload.sh
systemctl enable --now certbot.timer >/dev/null 2>&1 || true

# ---------------------------------------------------------------- фаервол
log "фаервол"
# Своя таблица, без flush ruleset: таблицы vpnnat и wgports живут отдельно
# и не должны исчезать при перезагрузке фаервола.
cat > /etc/nftables.conf <<EOF
#!/usr/sbin/nft -f
table inet filter
delete table inet filter
table inet filter {
    chain input {
        type filter hook input priority filter; policy drop;
        ct state established,related accept
        iif lo accept
$([ "$ROLE" = "single" ] && echo '        iifname "wg-clients" accept')
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept
        tcp dport { 22, 80, 443 } accept
$([ "$ROLE" = "single" ] && echo "        udp dport { 443, $WG_PORT } accept")
    }
    chain forward { type filter hook forward priority filter; policy accept; }
    chain output  { type filter hook output  priority filter; policy accept; }
}
EOF
nft -f /etc/nftables.conf
systemctl enable --now nftables >/dev/null 2>&1 || true

# ---------------------------------------------------------------- проверялка
install -d -m755 /etc/vpn-monitor /usr/local/sbin
install -m755 "$KIT/common/verify.sh" /usr/local/sbin/vpn-verify.sh
[ -f /etc/vpn-monitor/config.sh ] || printf 'VPN_MODE=exit\n' > /etc/vpn-monitor/config.sh

# ---------------------------------------------------------------- одна машина: клиентская часть
if [ "$ROLE" = "single" ]; then
  log "поднимаю WireGuard для клиентов"
  bash "$KIT/common/install-clientside.sh"
  systemctl restart vpn-watchdog
fi

# ---------------------------------------------------------------- итог
install -d -m700 /root/vpn-kit
cat > /root/vpn-kit/exit-summary.txt <<EOF
домен            $DOMAIN
push-домен       ${PUSH_DOMAIN:-(нет)}  ntfy: $([ "$NTFY_OK" = 1 ] && echo "свой, тема $NTFY_TOPIC" || echo "публичный ntfy.sh")
ntfy alerts-токен ${ALERT_TOKEN:-(нет)}
uuid реле        $UUID_RELAY
uuid прямой      ${UUID_DIRECT:-(нет)}
reality pubkey   $REALITY_PUBLIC
shortId реле     $SHORT_RELAY
shortId прямой   ${SHORT_DIRECT:-(нет)}
xhttp path       $XHTTP_PATH
EOF
chmod 600 /root/vpn-kit/exit-summary.txt
echo
echo "=== ВЫХОДНАЯ МАШИНА ГОТОВА ==="
systemctl is-active xray nginx 2>/dev/null | tr '\n' ' ' || true; echo
echo "ntfy-alerts-token: ${ALERT_TOKEN:-none}"
echo "сводка: /root/vpn-kit/exit-summary.txt"
