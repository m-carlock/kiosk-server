#!/bin/bash
# Run ON the Guacamole host:  sudo ./verify-guac.sh
set -u
PASS=0; FAIL=0
ok()  { echo "  PASS  $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }

DOMAIN=$(grep -oP '^\S+(?= \{)' /etc/caddy/Caddyfile | head -1)
echo
echo "Verifying Guacamole gateway: $DOMAIN"
echo "----------------------------------------------------"

for c in guacamole guacd guac-postgres; do
  if docker ps --format '{{.Names}}' | grep -qx "$c"; then ok "container $c up"
  else bad "container $c not running"; fi
done

for s in caddy docker nftables; do
  systemctl is-active --quiet "$s" && ok "$s active" || bad "$s inactive"
done

systemctl is-active --quiet ddns-update.timer && ok "DDNS timer active" || bad "DDNS timer inactive"

# Guacamole must NOT be reachable except via loopback
if ss -lntp 2>/dev/null | grep -q '127.0.0.1:8080'; then ok "Guacamole bound to loopback only"
else bad "Guacamole not bound to 127.0.0.1:8080 - check compose ports"; fi

# TLS should REJECT us: we have no client certificate
OUT=$(curl -sS -m 10 -o /dev/null -w '%{http_code}' "https://${DOMAIN}/" 2>&1)
if [ "$OUT" = "000" ] || echo "$OUT" | grep -qi 'alert\|handshake\|certificate'; then
  ok "mTLS rejects connections without a client cert"
else
  bad "Got HTTP $OUT without a client cert - mTLS is NOT enforcing"
fi

# With a client cert it should succeed
if [ -f /etc/caddy/clients/ca.crt ]; then
  CN=$(ls /etc/caddy/clients/*.crt 2>/dev/null | grep -v ca.crt | head -1 | xargs -r basename -s .crt)
  if [ -n "$CN" ]; then
    CODE=$(curl -sS -m 15 -o /dev/null -w '%{http_code}' \
      --cert "/etc/caddy/clients/${CN}.crt" --key "/etc/caddy/clients/${CN}.key" \
      "https://${DOMAIN}/guacamole/" 2>/dev/null)
    [ "$CODE" = "200" ] || [ "$CODE" = "302" ] \
      && ok "Authenticated client reaches Guacamole (HTTP $CODE)" \
      || bad "Authenticated client got HTTP $CODE"
  fi
  ok "Client CA present"
else
  bad "No client CA - run make-client-cert.sh"
fi

# DNS points at us
PUB=$(curl -fsS -m 10 https://api.ipify.org 2>/dev/null)
RES=$(getent hosts "$DOMAIN" | awk '{print $1}' | head -1)
[ -n "$PUB" ] && [ "$PUB" = "$RES" ] \
  && ok "DNS resolves to our public IP ($PUB)" \
  || bad "DNS says $RES, we are $PUB - DDNS lagging or record proxied"

# Kiosk reachable over Tailscale
KIP=$(grep -oP '(?<=kiosk_tailscale_ip: ")[^"]+' /root/.kiosk_ip 2>/dev/null || echo "")
if [ -n "$KIP" ]; then
  timeout 5 bash -c "cat < /dev/null > /dev/tcp/${KIP}/3389" 2>/dev/null \
    && ok "Kiosk RDP reachable at $KIP:3389" || bad "Cannot reach kiosk at $KIP:3389"
fi

echo
echo "----------------------------------------------------"
echo "  $PASS passed, $FAIL failed"
echo
echo "Manual checks:"
echo "  - Browser WITHOUT the cert installed: connection refused"
echo "  - Browser WITH the cert: prompted to select, then Guacamole login"
echo "  - guacadmin default password CHANGED"
echo "  - TOTP enrolled for every helper account"
[ "$FAIL" -eq 0 ]
