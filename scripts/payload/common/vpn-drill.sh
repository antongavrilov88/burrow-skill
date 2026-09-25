#!/bin/bash
# Учебное падение основного канала: блокируем путь релей → выход на 443, смотрим, как отработает
# сторож, снимаем блокировку. Страховка снимает её в любом случае.
#
# Почему обычный запуск уходит в фон: учения рвут ровно тот канал, через который оператор
# чаще всего и подключён к серверу. Запущенный из такой ssh-сессии скрипт умрёт вместе с ней
# посреди прогона — с уже поднятой блокировкой, которую снимет только страховочный таймер,
# через SAFETY_MIN минут. Поэтому обычный запуск перезапускает себя отдельным systemd-юнитом
# и сразу отдаёт управление; --fg выполняет прогон в текущем процессе (так его зовёт systemd).
#
#   vpn-drill.sh          — прогон с отчётом в уведомления, в фоновом юните
#   vpn-drill.sh --check  — только проверка готовности, без падения
#   vpn-drill.sh --force  — не откладывать, даже если каналом сейчас пользуются
#   vpn-drill.sh --fg     — прогон в текущем процессе, без фонового юнита
set -u
CHECK=""; FORCE=""; FG=""
for arg in "$@"; do
  case "$arg" in
    --check) CHECK=1 ;;
    --force) FORCE=1 ;;
    --fg)    FG=1 ;;
    *) echo "неизвестный ключ: $arg" >&2
       echo "использование: vpn-drill.sh [--check] [--force] [--fg]" >&2
       exit 2 ;;
  esac
done
# под systemd мы и так отдельный процесс — отделяться второй раз незачем
[ -n "${INVOCATION_ID:-}" ] && FG=1
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
STATS_DB=/var/lib/vpn-monitor/stats.db
QUIET_SEC=300
QUIET_MB=5

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

# Пользуется ли кто-нибудь каналом прямо сейчас: сумма дельт трафика за последние
# QUIET_SEC секунд. Базы нет — смотрим на свежие рукопожатия WireGuard.
anyone_active() {
  if [ -f "$STATS_DB" ]; then
    python3 - "$STATS_DB" "$QUIET_SEC" "$QUIET_MB" <<'PY'
import sqlite3, sys, time
db, quiet_sec, quiet_mb = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
try:
    conn = sqlite3.connect("file:%s?mode=ro" % db, uri=True)
    row = conn.execute("SELECT COALESCE(SUM(rx+tx),0) FROM samples WHERE ts > ?",
                       (int(time.time()) - quiet_sec,)).fetchone()
except Exception:
    sys.exit(2)
sys.exit(0 if (row[0] or 0) > quiet_mb * 1024 * 1024 else 1)
PY
    rc=$?
    [ "$rc" -le 1 ] && return "$rc"
  fi
  wg show wg-clients latest-handshakes 2>/dev/null \
    | awk -v now="$(date +%s)" '$2 ~ /^[0-9]+$/ && $2 > 0 && now - $2 < 180 { active = 1 } END { exit active ? 0 : 1 }'
}

echo "=== $(date -Is) drill start" >> $LOG

# --- проверка готовности: без неё падение устраивать нельзя
tunnel_ok || { notify "Учения отменены" "Основной канал и так не работает — сначала надо разобраться с этим." high; echo "abort: tunnel down" >> $LOG; exit 1; }
fallback_ok || { notify "Учения отменены" "Запасной путь не отвечает — падать некуда. Это само по себе повод посмотреть." urgent; echo "abort: fallback down" >> $LOG; exit 1; }
systemctl is-active --quiet vpn-watchdog || { notify "Учения отменены" "Сторож не запущен, некому реагировать." high; echo "abort: watchdog down" >> $LOG; exit 1; }
notify "Готовность к учениям" "Основной канал работает, запасной работает, сторож на посту." >/dev/null

if [ -n "$CHECK" ]; then echo "check ok" >> $LOG; exit 0; fi

# --- учения не должны ронять тех, кто прямо сейчас работает
if [ -z "$FORCE" ] && anyone_active; then
  notify "Учения отложены" "Каналом сейчас пользуются — прогон не проводился. Попробуем в следующий раз."
  echo "skip: clients active" >> $LOG
  echo "Каналом сейчас пользуются — учения отложены."
  echo "Провести всё равно: /usr/local/sbin/vpn-drill.sh --force"
  exit 3
fi

# --- уходим в отдельный юнит: разрыв ssh-сессии не должен убить прогон с поднятой блокировкой
if [ -z "$FG" ]; then
  systemctl stop vpn-drill-manual.service >/dev/null 2>&1 || true
  systemctl reset-failed vpn-drill-manual.service >/dev/null 2>&1 || true
  if systemd-run --unit=vpn-drill-manual --description="Учения по запросу" --quiet \
       /usr/local/sbin/vpn-drill.sh --fg ${FORCE:+--force} >/dev/null 2>&1; then
    echo "Учения запущены в фоне: минуту-две зарубежные сайты будут недоступны, местные продолжат открываться. Если вы подключены к серверу через этот VPN, ваша сессия оборвётся — так и задумано."
    echo "Отчёт придёт push-уведомлением. Журнал: tail -n 20 /var/lib/vpn-monitor/drill.log"
    exit 0
  fi
  echo "systemd-run не сработал — провожу учения в текущем процессе." >&2
fi

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
