#!/bin/bash
# Учебное падение основного канала: блокируем путь релей → выход на 443, смотрим, как отработает
# сторож, снимаем блокировку. Страховка снимает её в любом случае.
#
#   vpn-drill.sh          — прогон с отчётом в уведомления
#   vpn-drill.sh --check  — только проверка готовности, без падения
set -u
. /etc/vpn-monitor/config.sh 2>/dev/null || true
GW="${VPN_GW:-10.67.0.1}"
if [ "${VPN_MODE:-relay}" = "single" ]; then
  echo "Учения имеют смысл только в схеме с двумя машинами: на одной машине переключаться некуда." >&2
  exit 1
fi
EXIT_IP=$(python3 -c "import json;print(json.load(open('/usr/local/etc/xray/config.json'))['outbounds'][0]['settings']['vnext'][0]['address'])" 2>/dev/null)
[ -n "$EXIT_IP" ] || { echo "не смог прочитать адрес выходной машины из конфига Xray" >&2; exit 1; }
STATE=/var/lib/vpn-monitor/health.json
LOG=/var/lib/vpn-monitor/drill.log
SAFETY_MIN=10

notify() {
  python3 - "$1" "$2" "${3:-default}" <<'PY'
import importlib.util, sys
s = importlib.util.spec_from_file_location("w", "/usr/local/sbin/vpn-watchdog.py")
m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
m.notify(sys.argv[1], sys.argv[2], sys.argv[3])
PY
}
read_set() {
  # nft переносит длинный набор на несколько строк, поэтому не grep, а разбор целиком
  python3 - <<'PYEOF'
import re, subprocess
try:
    out = subprocess.run(["nft", "list", "set", "ip", "xray_tproxy", "proxied_src"],
                         capture_output=True, text=True, timeout=20).stdout
    m = re.search(r"elements = \{([^}]*)\}", out, re.S)
    print(", ".join(sorted(re.findall(r"[\d]+\.[\d]+\.[\d]+\.[\d]+(?:/\d+)?", m.group(1)))) if m else "")
except Exception:
    print("")
PYEOF
}
tunnel_ok() { curl -s -m 8 -x socks5h://127.0.0.1:1080 -o /dev/null -w "%{http_code}" https://www.gstatic.com/generate_204 | grep -qE "20[04]"; }
fallback_ok() { curl -s -m 8 --interface "$GW" -o /dev/null -w "%{http_code}" https://www.gstatic.com/generate_204 | grep -qE "20[04]"; }

echo "=== $(date -Is) drill start" >> $LOG

# --- проверка готовности: без неё падение устраивать нельзя
tunnel_ok || { notify "Учения отменены" "Основной канал и так не работает — сначала надо разобраться с этим." high; echo "abort: tunnel down" >> $LOG; exit 1; }
fallback_ok || { notify "Учения отменены" "Запасной путь не отвечает — падать некуда. Это само по себе повод посмотреть." urgent; echo "abort: fallback down" >> $LOG; exit 1; }
systemctl is-active --quiet vpn-watchdog || { notify "Учения отменены" "Сторож не запущен, некому реагировать." high; echo "abort: watchdog down" >> $LOG; exit 1; }
notify "Готовность к учениям" "Основной канал работает, запасной работает, сторож на посту." >/dev/null

if [ "${1:-}" = "--check" ]; then echo "check ok" >> $LOG; exit 0; fi

BEFORE=$(read_set); BEFORE="${BEFORE:-пусто}"
echo "before: $BEFORE" >> $LOG

# --- страховка: снимет блокировку, даже если скрипт умрёт
systemctl stop drill-cleanup.timer drill-cleanup.service >/dev/null 2>&1 || true
systemctl reset-failed drill-cleanup.service >/dev/null 2>&1 || true
systemd-run --on-active=${SAFETY_MIN}min --unit=drill-cleanup --description="Снять учебную блокировку" \
  /usr/sbin/nft delete table ip drill >/dev/null 2>&1

nft -f - <<EOF
table ip drill
delete table ip drill
table ip drill {
    chain output {
        type filter hook output priority filter; policy accept;
        ip daddr $EXIT_IP tcp dport 443 counter drop
    }
}
EOF
T0=$(date +%s); echo "blocked at $(date -Is)" >> $LOG

# --- ждём переключения (сторож должен уложиться в ~90 секунд)
FAILOVER_AT=""
for i in $(seq 1 40); do
  sleep 5
  if python3 -c "import json,sys;sys.exit(0 if json.load(open('$STATE')).get('failover') else 1)" 2>/dev/null; then
    FAILOVER_AT=$(( $(date +%s) - T0 )); break
  fi
done

nft delete table ip drill 2>/dev/null
systemctl stop drill-cleanup.timer 2>/dev/null
echo "unblocked at $(date -Is)" >> $LOG

# --- ждём возврата
RESTORE_AT=""
for i in $(seq 1 60); do
  sleep 5
  if python3 -c "import json,sys;sys.exit(0 if not json.load(open('$STATE')).get('failover') else 1)" 2>/dev/null; then
    RESTORE_AT=$(( $(date +%s) - T0 )); break
  fi
done

AFTER=$(read_set); AFTER="${AFTER:-пусто}"
echo "after: $AFTER | failover=${FAILOVER_AT:-нет} restore=${RESTORE_AT:-нет}" >> $LOG

if [ -n "$FAILOVER_AT" ] && [ -n "$RESTORE_AT" ] && [ "$BEFORE" = "$AFTER" ]; then
  notify "Учения: всё сработало" "Переключение на запасной путь через ${FAILOVER_AT} с после падения, возврат через ${RESTORE_AT} с. Состав клиентов восстановлен точно."
else
  notify "Учения: есть замечания" "Переключение: ${FAILOVER_AT:-НЕ ПРОИЗОШЛО} с, возврат: ${RESTORE_AT:-НЕ ПРОИЗОШЁЛ} с. Было: $BEFORE / стало: $AFTER. Нужно посмотреть." urgent
fi
echo "=== $(date -Is) drill end" >> $LOG
