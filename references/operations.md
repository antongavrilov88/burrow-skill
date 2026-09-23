# Эксплуатация

## Панель

`http://<подсеть>.1:8088` — только изнутри VPN (по умолчанию `http://10.67.0.1:8088`).
Код доступа лежит в `/etc/vpn-monitor/admin-token`, браузер запоминает его сам.

Снаружи, для того кто держит систему:

```bash
ssh -L 8088:127.0.0.1:8088 <релей>   # затем http://127.0.0.1:8088
```

В панели: кто онлайн, сколько прокачал, кто каким маршрутом идёт, выпуск нового
клиента с QR, удаление, список доменов-исключений.

## Ежедневные команды (на релее)

```bash
# кто сейчас в туннеле
sudo nft list set ip xray_tproxy proxied_src

# переключить одного клиента, мгновенно
sudo nft add element ip xray_tproxy proxied_src { 10.67.0.6 }
sudo nft delete element ip xray_tproxy proxied_src { 10.67.0.6 }

# всех разом в туннель
sudo nft add element ip xray_tproxy proxied_src { 10.67.0.0/24 }

# полный откат на прямой выход
sudo systemctl stop xray-tproxy-route

# состояние
curl -x socks5h://127.0.0.1:1080 https://api.ipify.org    # должен быть IP выхода
sudo cat /var/lib/vpn-monitor/health.json
sudo bash /usr/local/sbin/vpn-verify.sh                   # полная проверка

# домены-исключения (прямой выход с релея)
sudo nano /etc/vpn-monitor/direct-domains.txt
sudo python3 /usr/local/sbin/vpn-split.py

# снимок состояния для разбора
sudo /usr/local/sbin/vpn-diag.sh

# уведомление вручную (проверить, что канал алертов живой)
sudo python3 -c "import importlib.util;s=importlib.util.spec_from_file_location('w','/usr/local/sbin/vpn-watchdog.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m);print(m.notify('Тест','Проверка'))"
```

Переключение из панели само дописывает набор в `/etc/xray/xray-tproxy.nft`,
чтобы он пережил перезагрузку. Если правишь `nft` руками — впиши `elements`
в файл сам, иначе после ребута всё вернётся.

## Как работает сторож

| Состояние | Период проб | Что происходит |
|---|---|---|
| здоров | 30 с | проба через socks: gstatic, затем cloudflare |
| первая неудача | 5 с | режим быстрого подтверждения |
| 3 неудачи подряд (~45–60 с от поломки) | — | **сначала откат**: состав `proxied_src` сохраняется и очищается, клиенты уходят на прямой выход, летит уведомление; **потом починка**: перезапуск Xray |
| лежит | 20 с | перезапуск Xray раз в ~5 минут, напоминание раз в час |
| 5 успешных проб | — | возврат клиентов из сохранённого списка + уведомление |
| флап-защита | — | если за час было 3+ отката, для возврата нужно 20 успешных проб вместо 5 |
| фон, раз в 10 мин | — | отдельная проверка запасного пути; мёртвый резерв = свой алерт |

Порядок «сначала пересадить, потом чинить» выбран нарочно: перезапуск Xray сам
по себе рвёт соединения, и делать его до отката значит ломать людям связь дважды.

В схеме B (одна машина) сторож работает в урезанном режиме: пробует канал,
перезапускает Xray, шлёт уведомление. Пересаживать некуда.

## Учения

```bash
sudo /usr/local/sbin/vpn-drill.sh --check   # только проверка готовности, ничего не ломает
sudo /usr/local/sbin/vpn-drill.sh           # настоящее падение на ~2 минуты
```

Полный прогон: проверка готовности → блокировка пути до выхода → ожидание
отката → снятие блокировки → ожидание возврата → сверка состава клиентов
до и после → отчёт в уведомления. Страховка через `systemd-run --on-active=10min`
снимает блокировку, даже если скрипт умрёт.

Запускается сам первого числа ночью; проверка готовности — каждый понедельник.
Лог: `/var/lib/vpn-monitor/drill.log`.

Учения — единственный способ узнать, что автооткат работает. Настроенный,
но ни разу не проверенный откат — это не откат.

## Замена выходной машины после бана IP (~15 минут)

Порядок строгий.

1. `provision-do.py list --tag vpn-exit` — запомнить id и IP старой. Если машин
   больше одной, сначала навести порядок.
2. Создать новую **с `--ssh-key`** и тем же `out/setup-exit.sh`.
3. Переставить A-записи `@`, `www`, `push` на новый IP, дождаться сертификатов
   (следить в `/var/log/vpn-kit-install.log` на новой машине).
4. Перенести со старой, если она ещё жива: `/var/www/<домен>` и `/var/lib/ntfy`.
5. На релее заменить адрес в `/usr/local/etc/xray/config.json`
   (`outbounds[0].settings.vnext[0].address`), затем
   `xray run -test -c /usr/local/etc/xray/config.json` и `systemctl restart xray`.
   Не забыть про набор `bypass` в `/etc/xray/xray-tproxy.nft` — там старый адрес.
6. Проверить: `curl -x socks5h://127.0.0.1:1080 https://api.ipify.org` → новый IP.
7. **Только теперь** `provision-do.py destroy --id <старый> --tag vpn-exit`
   и убедиться, что он пропал из списка. Это обязательный шаг, а не опциональный:
   забытая машина — счёт каждый месяц.

Ключи REALITY при замене менять не нужно — они в `params.json` и просто
переезжают на новую машину вместе с установщиком.

## Трафик и счета

```bash
sudo wg show wg-clients transfer     # по каждому устройству, с момента поднятия
```

Панель показывает 14 дней истории. Прикидывай месячный расход: выше 800 ГБ при
квоте 1 ТБ — пора либо на дроплет за $12, либо разбираться, кто качает.

Раз в месяц полезно посмотреть `provision-do.py list` целиком: не завелось ли
лишних машин.

## Что где лежит

**Релей**

| Путь | Что это |
|---|---|
| `/usr/local/etc/xray/config.json` | конфиг Xray (клиент REALITY) |
| `/etc/xray/xray-tproxy.nft` | перехват; наборы `proxied_src` и `bypass` |
| `/etc/xray/wgports.nft` | redirect udp/443 → порт WireGuard (юнит `vpn-wgports`) |
| `/usr/local/sbin/vpn-*.py`, `vpn-*.sh` | монитор, сторож, разделение, диагностика, учения |
| `/usr/local/share/vpn-monitor/index.html` | панель |
| `/etc/vpn-monitor/` | `config.json`, `admin-token`, `alerts.json`, `direct-domains.txt`, `names.json` |
| `/var/lib/vpn-monitor/` | `stats.db` (14 дней), `health.json`, `failover-set.json`, `drill.log`, снимки диагностики |
| `/etc/wireguard/` | ключи сервера, конфиги клиентов, `removed/` — архив удалённых |

**Выходная машина**

| Путь | Что это |
|---|---|
| `/usr/local/etc/xray/config.json` | inbound VLESS+XHTTP+REALITY |
| `/etc/nginx/sites-enabled/` | `:80` (ACME и редирект) и `127.0.0.1:8443` (цель self-steal, ntfy) |
| `/var/www/<домен>/` | сайт-прикрытие |
| `/etc/ntfy/server.yml`, `/var/lib/ntfy/` | уведомления |
| `/root/vpn-kit/exit-summary.txt` | сводка по установке (режим 600) |
| `/var/log/vpn-kit-install.log` | журнал установки |
