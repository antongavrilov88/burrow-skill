# What you say — English

Use one section at a time: take the section for the step you are on, retell it in your own words, wait for "done". Never paste this file, or a whole list of sections, into the chat. Section numbers match `references/human-steps.md`. Everything in quotation marks is meant to be said to the person, in their language: for a language other than English or Russian, translate from here as you go — the meaning and the warnings, not the sentences. The Russian file `ru.md` is tested with real families; use it verbatim.

## How to phrase things (the examples the rules refer to)

- "we need a long password that lets me rent a server on your behalf" — not "generate an API token"
- "we need to tell them that this company is now in charge of your address" — not "delegate the domain"
- "the server is ready, I checked, it works" — not which version of what you installed
- "this will take about ten minutes, I'll tell you when it's done"
- "that didn't go through, let's try another way" — never "you entered it wrong"

## §0 The first questions

The layout question, exactly as asked:

> "Where are the people who'll use this, and do they hit networks that only allow whitelisted traffic (typical on mobile data in some countries)?"

Examples they can pick from:

- "Abroad, or somewhere nothing is filtered"
- "In a country with filtering, but a VPN app on their phone connects fine on mobile data, and I can get to their devices when something changes"
- "In a country with filtering, and on mobile data only certain services get through — or it's a household and I can't keep reconfiguring their phones"
- "Not sure"

Follow-up for "not sure": "On their phone, with Wi-Fi off, does any VPN app connect at all?"

Domain: "Do you have your own address on the internet — a domain?" If no, or they have never heard of it: "It's an address like `ivanov-notes.com`, about ten dollars a year. We need it as a disguise: from the outside it looks like you're simply visiting some website."

Hosting: "Do you have an account with DigitalOcean or another hosting provider?" If no: "You'll need one, and it needs a payment method they accept — a card that works internationally, or PayPal. That's the most common place where this stalls, so it's better to know now than in an hour."

Notifications: "Do you want your phone to tell you if something breaks?"

[relay] "Can a small server be rented in the country where they live — by you, or by someone there with a local card?"

Money — one paragraph, no confirmation asked:

- `single`: "Here's what it comes to: a server abroad is about six dollars a month, the domain about ten dollars a year. All in, around seven dollars a month."
- `relay`: "Here's what it comes to: a server abroad is about six dollars a month, the domain about ten dollars a year, and a small server in the country where they live, usually four to eight dollars a month. All in, around twelve dollars a month."

## §1 Hosting account

Why, said to them: "We need a computer abroad that runs around the clock. We'll rent it from DigitalOcean — it's like web hosting, except you get the whole server. Six dollars a month."

The card: "About a dollar will be charged to check the card and refunded straight away."

If the card is refused: "They don't take that card. What works: a card from a bank in another country, PayPal linked to an account outside the country, or a virtual card from a service like Wise or Payoneer. If none of those is an option, we'll pick a provider that accepts what you have — I have a list."

Never: suggest an account in someone else's name, or a way around the card check.

## §2 The access key

"So that I can do everything for you, I need a key to your account. It's a long line of text. It gives full access, which is why we'll revoke it right after the setup — and then it's useless."

Must be said aloud: "This line will pass through our conversation. When we're done, we'll revoke it and, if needed, issue a new one — so even if this chat leaked somewhere one day, the key is already dead."

Revoking later: "The same page: API → Tokens → the three dots next to the token → Delete."

## §3 Domain

"We need an address of your own on the internet, like `ivanov-notes.com`. About ten dollars a year. It's for the disguise: whoever looks from the outside sees you simply visiting some website."

Where: "Namecheap, Porkbun or Cloudflare — cheap, paid by card. Or the registrar you already use."

What to pick: "Any free name. `.com`, `.net`, `.org`, `.me` are all fine. Skip the very cheap ones — `.xyz`, `.top`, `.click` — they get blocked in bulk."

The warning, said in full, not in passing:

> "Don't pick a domain you're attached to, and don't use one that already carries your website or your email. About once every six months the server's address may get blocked; then we swap the machine, and the domain stays tied to that history. And if the domain itself is ever blocked, everything on it goes down with it."

"Something neutral and yours works fine: notes, a pet project, a photo archive."

## §4 Pointing the domain at DigitalOcean

"One more thing: we need to tell them that DigitalOcean is in charge of your address. It's one setting where you bought the domain — after that I do everything myself."

What to expect: "It updates in fifteen minutes to a few hours, occasionally up to a day. That's normal, nothing to re-click. I'll check myself and tell you when it's ready."

If they would rather not change the nameservers (email on the domain, say): don't push. §5 instead.

## §5 Three records by hand

"We need to add three lines in the domain settings. All three are the same; only the first field differs."

The explanations everyone trips on:

- "`@` means the domain itself, with nothing in front. Some panels want the field left empty instead, or the full domain typed in."
- "TTL 300 is 'five minutes' — the smaller, the faster changes take effect. If there's no TTL field, skip it."
- "The type is exactly A — not AAAA, not CNAME."

## §6 [relay] The server in their country

"We need one more computer, this time in the country where they live. Devices will connect through it. It's cheap — a few dollars a month — and it's paid with a local card."

What to order, as needed: "Ubuntu 24.04. The smallest plan: one processor, one gigabyte of memory, ten gigabytes of disk. It must have its own IPv4 address — if they offer 'without a dedicated IP', don't take it. And check the traffic limit: everything passes through this machine twice. Unlimited, or a terabyte and up."

What you need afterwards: "The server's address, the login (usually `root`) and the password — they email those right after payment."

Say it straight: "This server's password will also pass through our conversation. After the install I'll show you how to change it — it's one command."

## §7 Running one command on the server

"I'll send you a file and two lines. You open one program on your computer and paste them in. It takes a minute, and then the server sets itself up in about ten."

Opening the terminal: "Mac: Cmd+Space, type `Terminal`, Enter. Windows 10/11: Start, type `PowerShell`, Enter. Linux: Ctrl+Alt+T."

The three warnings, before they paste:

1. "The first line asks for the server's password. Nothing shows while you type — no dots, no stars. That's normal: paste or type it blind and press Enter."
2. "It may ask `Are you sure you want to continue connecting (yes/no)?` — type `yes` and Enter. That happens once."
3. "It asks for the password twice — the second time is for the second line."

"Then lines will scroll by — that's normal, just wait. When it stops, send me the last twenty lines."

If pasting fails: "In Windows PowerShell paste is the right mouse button, not Ctrl+V. On a Mac it's Cmd+V as usual."

## §8 The app on the devices

"We're installing the WireGuard app — it's free and official. Then you scan a picture with a code, and that's it."

Adding a device: "In the app tap +, choose 'Create from QR code', point the camera at the code the panel shows. Give it a name, save, flip the switch on."

On a computer: "Instead of a QR the panel gives you a `.conf` file; in the app choose 'Import tunnel(s) from file'."

The system prompt: "The phone will ask once whether to allow this VPN to be set up. That's the normal system question — say yes."

The first device, before you send its code: "The very first device I set up from the server and send you the code for, because the panel only opens from inside the VPN and nothing is inside it yet. This one code passed through our chat; once you're connected you can make a fresh one in the panel and delete this one, if you like. From the second device on, you do it yourself in the panel, with me watching."

People who are not in the room: "Send them a screenshot of the QR, or the `.conf` file for a computer, over a messenger you trust — and delete the message once they've scanned it: that picture is a key."

The check: "Open youtube.com — does it open?"

The panel is in Russian for now — the buttons the person needs, with meanings (full glossary at the end of this file): «+ Новый клиент» — "New client"; «Создать и показать QR» — "Create and show the QR"; «Скачать .conf» — "Download .conf"; «Порт: 51821 (обычный) / 443 (для строгих сетей)» — "Port: 51821 (normal) / 443 (for strict networks)"; «Маршрут: через туннель / напрямую» — "Route: through the tunnel / direct". Say once, before the first device: "The panel's buttons are in Russian at the moment. I'll tell you which one to press, and the handout lists what each one means."

[relay] Before anyone else gets a QR: "Let's try the first phone on mobile data, with Wi-Fi off — that's the network that matters." Then: "Now I'll switch the bypass on for this phone. Same question: does YouTube open?"

[relay] The two warnings: "Some mobile operators cut this kind of connection on the usual port. If a phone won't connect on mobile data, we make it a 443 one — that goes through almost everywhere." And: "If their operator starts blocking the tunnel, everyone is moved to the direct route within a minute or two, automatically. The internet keeps working, just without the bypass, and they're moved back when it recovers. So 'the VPN is on but the sites don't open' means that, not that the whole thing is broken."

## §9 Notifications

"If something breaks, you'll be the first to know — not your parents. It takes a minute to set up."

"Install the ntfy app. Tap +, 'Subscribe to topic', turn on 'Use another server' and enter the address I'll give you, then the topic name, the login and the password — also from me. The messages themselves are in Russian for now; the handout translates every title."

Then: "I've just sent a test — did it arrive?"

## §10 Cleaning up (a day or two later, one message)

- revoke the access key (§2, "revoking later");
- delete the server password and the key from the conversation, if they were sent here;
- keep `params.json` somewhere safe — a password manager or a cloud drive; it holds the keys without which repairs get much harder;
- a calendar reminder a month before the domain renewal.

## Between the steps

- While the exit installs: "This will take about ten minutes. Meanwhile, let's put the app on your phone."
- [relay] After the relay is up: "Right now everyone connects directly, the bypass isn't on yet. That's on purpose: first we make sure the connection works, then we switch the bypass on one device at a time and watch that nothing falls over."
- [relay] Drill consent: "Want me to test it for real? I'll break the main channel for two minutes and watch the system get itself out. If nobody is watching a film right now, this is the moment."
- The cover site: "At your address there's now a page of notes about servers. It's there so that a check sees an ordinary website. Over time it's better to replace the text with your own — even three paragraphs about fishing. The same template on a dozen addresses becomes a tell." For a person who does not write in Russian, say instead: "At your address there's now a page of notes about servers, in Russian. It's there so that a check sees an ordinary website, and it works best when the text is your own — give me a topic and I'll rewrite it in your language now, before we finish."
- Privacy: "You'll see that your mother's phone used two gigabytes, and you won't see what she watched. Even if you wanted to — the data isn't there."
- Goodbye: what works and how to add a device (one line); revoke the key (the exact path); `params.json`: "This file is yours — it holds the keys without which repairs get much harder. Put it in a password manager or a cloud drive, then delete it from this chat."; the domain renewal reminder.
- The day after: "Hi — is everything still working? Anything odd on any of the phones?"

## Glossary: the panel (Russian labels → meaning)

| On the panel | Meaning |
|---|---|
| «VPN — трафик» | VPN — traffic (the page title) |
| «6 ч / 24 ч / 7 дней» | 6 h / 24 h / 7 days (the period) |
| «Трафик по времени» | Traffic over time |
| «Через туннель» / «Напрямую (резерв)» / «Трафик клиентов» | Through the tunnel / Direct (fallback) / Client traffic |
| «Кто сколько прокачал» | Usage per device |
| «Клиенты» · «Все / Онлайн / Туннель / Напрямую» · «поиск» | Devices · All / Online / Tunnel / Direct · search |
| «Всех → туннель» / «Всех → напрямую» | Everyone → tunnel / Everyone → direct |
| «+ Новый клиент» | + New client (add a device) |
| «Имя» · «Маршрут: через туннель / напрямую» · «Порт: 51821 (обычный) / 443 (для строгих сетей)» | Name · Route: through the tunnel / direct · Port: 51821 (normal) / 443 (for strict networks) |
| «Создать и показать QR» | Create and show the QR |
| «Скачать .conf» / «Скопировать» / «Закрыть» | Download .conf / Copy / Close |
| «Клиент / Маршрут / Активность / Вниз / Вверх / Всего» | Device / Route / Activity / Down / Up / Total (table headers) |
| «онлайн» · «только что» · «N мин назад» · «никогда» | online · just now · N min ago · never |
| «Исключения — идут напрямую с релея» · «Добавить» · «Убрать» | Exceptions — go direct from the relay · Add · Remove |
| «Код администратора (спроси у того, кто ставил VPN):» | "Admin code (ask whoever set up the VPN):" — the one-time prompt |
| «Туннель в порядке» | Tunnel OK |
| «Туннель не отвечает» | Tunnel not responding (repair in progress) |
| «Туннель лежит, все переведены на запасной путь» | Tunnel down, everyone on the fallback route |
| «Связь вернулась, проверяю стабильность» | Back, checking stability |
| «Сторож не запущен» | Watchdog not running |

## Glossary: push notifications (Russian titles → meaning)

| Title | Meaning |
|---|---|
| «VPN: сервер не отвечает» | the server isn't responding (urgent) |
| «VPN: сервер снова отвечает» | the server is responding again |
| «VPN: туннель упал, все переведены на запасной путь» | the tunnel is down, everyone moved to the fallback route |
| «VPN: туннель восстановился» | the tunnel is back, clients moved back |
| «VPN: запасной путь не отвечает» | the fallback route isn't responding — look at it |
| «VPN: запасной путь снова живой» | the fallback route is alive again |
| «VPN: основной канал всё ещё лежит» | the main channel is still down (hourly reminder) |
| «VPN: собран снимок состояния» | a diagnostic snapshot was saved |
| «VPN: клиенты возвращены на туннель» | clients moved back to the tunnel after a reboot |
| «Готовность к учениям» / «Учения: всё сработало» / «Учения: есть замечания» / «Учения отменены» | ready for the drill / drill: all good / drill: needs a look / drill cancelled |
