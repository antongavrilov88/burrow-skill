#!/bin/bash
# Снимок состояния для разбора: собирается автоматически при затяжном отказе
# и вручную командой vpn-diag.sh. Никаких адресов назначения клиентов — только
# состояние инфраструктуры.
. /etc/vpn-monitor/config.sh 2>/dev/null || true
MODE="${VPN_MODE:-relay}"
GW="${VPN_GW:-10.67.0.1}"
OUT=/var/lib/vpn-monitor/diag-$(date +%Y%m%d-%H%M%S).txt
CFG=/usr/local/etc/xray/config.json
EXIT_IP=$(python3 -c "import json;print(json.load(open('$CFG'))['outbounds'][0]['settings']['vnext'][0]['address'])" 2>/dev/null)
SNI=$(python3 -c "import json;print(json.load(open('$CFG'))['outbounds'][0]['streamSettings']['realitySettings']['serverName'])" 2>/dev/null)
{
echo "=== снимок $(date -Is)  |  режим=$MODE  выход=$EXIT_IP  SNI=$SNI"
echo "--- состояние сторожа"; cat /var/lib/vpn-monitor/health.json 2>/dev/null; echo
echo "--- сервисы"; systemctl is-active xray vpn-monitor vpn-watchdog xray-tproxy-route wg-quick@wg-clients 2>/dev/null | tr '\n' ' '; echo
echo "--- проба через Xray (socks)"; curl -s -m 8 -x socks5h://127.0.0.1:1080 -o /dev/null -w "код=%{http_code} время=%{time_total}s\n" https://www.gstatic.com/generate_204
echo "--- прямой выход с этой машины"; curl -s -m 8 --interface "$GW" -o /dev/null -w "код=%{http_code} время=%{time_total}s\n" https://www.gstatic.com/generate_204 2>/dev/null || echo "(нет интерфейса $GW)"
echo "--- интернет с самой машины"; curl -s -m 8 -o /dev/null -w "код=%{http_code}\n" https://www.gstatic.com/generate_204

if [ "$MODE" != "single" ] && [ -n "$EXIT_IP" ]; then
  echo "--- DNS домена"; dig +short A "$SNI" @1.1.1.1 2>/dev/null | tr '\n' ' '; echo "(в конфиге $EXIT_IP)"
  echo "--- TCP до выходной машины"
  timeout 6 bash -c "cat < /dev/null > /dev/tcp/$EXIT_IP/443" 2>/dev/null && echo "443 открыт" || echo "443 НЕ отвечает"
  timeout 6 bash -c "cat < /dev/null > /dev/tcp/$EXIT_IP/22"  2>/dev/null && echo "22 открыт"  || echo "22 НЕ отвечает"
  echo "--- TLS (виден ли настоящий сертификат)"
  timeout 10 openssl s_client -connect "$EXIT_IP:443" -servername "$SNI" </dev/null 2>/dev/null | grep -E "subject=|issuer=|Verify return code" | head -3
  echo "--- ping"; ping -c 3 -W 2 "$EXIT_IP" 2>/dev/null | tail -2
fi

echo "--- WireGuard"; wg show wg-clients dump 2>/dev/null | tail -n +2 | wc -l | xargs echo "пиров:"
wg show wg-upstream 2>/dev/null | grep -E "handshake|transfer"
echo "--- кто в туннеле"
python3 -c "
import re,subprocess
try:
    o=subprocess.run(['nft','list','set','ip','xray_tproxy','proxied_src'],capture_output=True,text=True,timeout=20).stdout
    m=re.search(r'elements = \{([^}]*)\}',o,re.S)
    print(', '.join(sorted(re.findall(r'[0-9.]+(?:/[0-9]+)?',m.group(1)))) if m else 'набор пуст')
except Exception as e: print('таблицы нет:',e)" 
echo "--- маршруты"; ip rule | tr '\n' '|'; echo; ip route show table 101 2>/dev/null | tr '\n' '|'; echo
echo "--- журнал Xray (ошибки)"; journalctl -u xray --no-pager -n 20 --since "-30min" 2>/dev/null | grep -viE "started|reading config|unified platform" | tail -10
echo "--- журнал сторожа"; journalctl -u vpn-watchdog --no-pager -n 8 --since "-30min" 2>/dev/null | tail -6
echo "--- ресурсы"; uptime | sed 's/.*load/load/'; free -m | head -2 | tail -1; df -h / | tail -1
} > "$OUT" 2>&1
chmod 644 "$OUT"
ls -1t /var/lib/vpn-monitor/diag-*.txt 2>/dev/null | tail -n +11 | xargs -r rm -f
echo "$OUT"
