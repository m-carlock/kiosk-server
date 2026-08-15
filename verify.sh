#!/bin/bash
# Run ON the kiosk box, as a sudo-capable user:  sudo ./verify.sh
# Confirms the firewall and proxy are actually doing their job.

set -u
PASS=0; FAIL=0
KUSER="${1:-kiosk1}"

ok()   { echo "  PASS  $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }

echo
echo "Verifying kiosk lockdown as user: $KUSER"
echo "----------------------------------------------------"

# --- 1. Kiosk user cannot reach the internet directly ---------------
if sudo -u "$KUSER" curl -s -m 6 -o /dev/null https://example.com 2>/dev/null; then
  bad "Direct egress BLOCKED (kiosk user reached the internet without the proxy)"
else
  ok  "Direct egress blocked"
fi

# --- 2. Kiosk user CAN reach Squid on loopback ----------------------
ALLOWED=$(grep -m1 '^\.' /etc/squid/whitelist.txt | sed 's/^\.//')
if [ -n "$ALLOWED" ] && sudo -u "$KUSER" curl -s -m 10 -o /dev/null \
     -x "http://127.0.0.1:3128" "https://${ALLOWED}" 2>/dev/null; then
  ok  "Whitelisted domain reachable via proxy ($ALLOWED)"
else
  bad "Whitelisted domain NOT reachable via proxy ($ALLOWED)"
fi

# --- 3. Squid denies a non-whitelisted domain -----------------------
CODE=$(sudo -u "$KUSER" curl -s -m 10 -o /dev/null -w '%{http_code}' \
       -x "http://127.0.0.1:3128" "https://neverssl.com" 2>/dev/null)
if [ "$CODE" = "403" ] || [ "$CODE" = "000" ]; then
  ok  "Non-whitelisted domain denied by Squid (HTTP $CODE)"
else
  bad "Non-whitelisted domain returned HTTP $CODE - expected 403"
fi

# --- 4. Raw IP is denied --------------------------------------------
CODE=$(sudo -u "$KUSER" curl -s -m 10 -o /dev/null -w '%{http_code}' \
       -x "http://127.0.0.1:3128" "https://1.1.1.1" 2>/dev/null)
if [ "$CODE" = "403" ] || [ "$CODE" = "000" ]; then
  ok  "Raw IP denied (HTTP $CODE)"
else
  bad "Raw IP returned HTTP $CODE - expected 403"
fi

# --- 5. Primary group is correct ------------------------------------
if [ "$(id -gn "$KUSER")" = "kiosks" ]; then
  ok  "Primary group is 'kiosks'"
else
  bad "Primary group is '$(id -gn "$KUSER")' - firewall rule will MISS"
fi

# --- 6. No sudo access ----------------------------------------------
if id -nG "$KUSER" | tr ' ' '\n' | grep -qx -e sudo -e adm -e root; then
  bad "Kiosk user is in a privileged group"
else
  ok  "Kiosk user has no privileged groups"
fi

# --- 7. Services up --------------------------------------------------
for svc in squid nftables xrdp xrdp-sesman tailscaled; do
  if systemctl is-active --quiet "$svc"; then ok "$svc running"
  else bad "$svc not running"; fi
done

# --- 8. Firewall counter is non-zero (rule is being hit) -------------
DROPS=$(nft list chain inet filter output 2>/dev/null | grep -o 'packets [0-9]*' | head -1 | awk '{print $2}')
echo "  INFO  nftables kiosk-drop counter: ${DROPS:-unknown} packets"

# --- 9. Memory headroom ----------------------------------------------
echo
free -h
echo
echo "----------------------------------------------------"
echo "  $PASS passed, $FAIL failed"
echo
echo "Still to test MANUALLY from inside an RDP session:"
echo "  - Ctrl+Alt+F2         -> no VT switch"
echo "  - right-click page bg -> no Openbox menu"
echo "  - F12 / Ctrl+Shift+I  -> devtools blocked"
echo "  - Ctrl+N              -> new window blocked"
echo "  - file:///etc/passwd  -> blocked"
echo "  - chrome://settings   -> blocked"
echo "  - Alt+F4              -> browser relaunches in ~2s"
echo "  - two users connected at once, independent sessions"
[ "$FAIL" -eq 0 ]
