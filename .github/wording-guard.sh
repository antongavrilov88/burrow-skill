#!/usr/bin/env bash
# Fails when a country-specific term is back in the public surface.
# The list and the approved vocabulary live in CONTRIBUTING.md ("Wording rules").
# Case-insensitive, Latin and Cyrillic. Language labels ("the panel is in Russian",
# lang/ru.md) are allowed on purpose: only geographic / positioning uses are banned.
# Excluded from the scan: this script and CONTRIBUTING.md (they quote the list),
# .git, images.
set -u
export LC_ALL=C.UTF-8
PATTERN='\bRKN\b|Roskomnadzor|Роскомнадзор|Sberbank|Сбербанк|\bСбер\b|обход блокировок|белы[йе] спис|whitelist|Russian (sites?|exit|banks?|IPs?|address(es)?|cards?|hosting|hosters?|providers?|laws?|carriers?|networks?|users?|households?)|VPN for Russians|works in Russia|\bin Russia\b|\bРосси[яию]|российск|\bРФ\b'
HITS=$(grep -rniE "$PATTERN" \
  --exclude-dir=.git --exclude='*.png' --exclude='*.jpg' --exclude='*.pyc' \
  --exclude='wording-guard.sh' --exclude='CONTRIBUTING.md' \
  "${1:-.}" || true)
if [ -n "$HITS" ]; then
  echo "banned wording found (see CONTRIBUTING.md, Wording rules):"
  echo "$HITS"
  exit 1
fi
echo "wording guard: 0 hits"
