#!/bin/bash
# Проверка установки. Запускать на сервере от root: bash verify.sh
. /etc/vpn-monitor/config.sh 2>/dev/null || true
MODE="${VPN_MODE:-unknown}"
GW="${VPN_GW:-10.67.0.1}"
ok(){ printf '  \033[32m✓\033[0m %s\n' "$1"; }
no(){ printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=1; }
FAIL=0
echo "режим: $MODE"

echo "службы:"
for u in xray nginx ntfy vpn-monitor vpn-watchdog xray-tproxy-route wg-quick@wg-clients; do
  systemctl cat "$u" >/dev/null 2>&1 || continue      # юнита нет — в этой роли и не должно быть
  if systemctl is-active --quiet "$u"; then ok "$u"; else no "$u не работает"; fi
done

if [ -f /usr/local/etc/xray/config.json ]; then
  xray run -test -c /usr/local/etc/xray/config.json >/dev/null 2>&1 && ok "конфиг Xray валиден" || no "конфиг Xray не проходит проверку"
fi

if grep -q '"vnext"' /usr/local/etc/xray/config.json 2>/dev/null; then
  EXP=$(python3 -c "import json;print(json.load(open('/usr/local/etc/xray/config.json'))['outbounds'][0]['settings']['vnext'][0]['address'])")
  GOT=$(curl -s -m 20 -x socks5h://127.0.0.1:1080 https://api.ipify.org || true)
  [ "$GOT" = "$EXP" ] && ok "туннель работает, наружу видно $GOT" || no "через туннель видно '$GOT', ожидалось '$EXP'"
  curl -s -m 8 --interface "$GW" -o /dev/null -w "" https://www.gstatic.com/generate_204 \
    && ok "запасной путь (прямой выход) работает" || no "прямой выход с релея не работает"
else
  DOM=$(python3 -c "import json;print(json.load(open('/usr/local/etc/xray/config.json'))['inbounds'][0]['streamSettings']['realitySettings']['serverNames'][0])" 2>/dev/null)
  if [ -n "$DOM" ]; then
    echo | timeout 10 openssl s_client -connect 127.0.0.1:8443 -servername "$DOM" 2>/dev/null \
      | grep -q "Verify return code: 0" && ok "сайт-прикрытие отдаёт валидный сертификат" \
      || no "сертификат для $DOM не отдаётся — REALITY будет заметен"
    ss -lntp 2>/dev/null | grep -q ':443 ' && ok "443/tcp слушается" || no "никто не слушает 443/tcp"
  fi
fi

if command -v wg >/dev/null && wg show wg-clients >/dev/null 2>&1; then
  N=$(wg show wg-clients dump | tail -n +2 | wc -l)
  ok "WireGuard поднят, пиров: $N"
  curl -s -m 5 -o /dev/null "http://$GW:${VPN_DASH_PORT:-8088}/api/data?hours=1" \
    && ok "дашборд отвечает на http://$GW:8088" || no "дашборд не отвечает"
fi

echo
[ "$FAIL" = 0 ] && echo "всё в порядке" || echo "есть замечания — смотри /usr/local/sbin/vpn-diag.sh и journalctl"
exit $FAIL
