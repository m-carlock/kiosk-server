#!/bin/bash
# Issue a client certificate for one helper.
#
#   sudo /usr/local/bin/make-client-cert.sh helper1 [days]
#
# Produces /etc/caddy/clients/<name>.p12 which the helper installs on
# their device. Caddy refuses any TLS connection without one.
#
# The CA is created on first run and reused thereafter.

set -euo pipefail

NAME="${1:-}"
DAYS="${2:-825}"
DIR=/etc/caddy/clients

[ -n "$NAME" ] || { echo "usage: $0 <name> [days]" >&2; exit 1; }
[[ "$NAME" =~ ^[a-zA-Z0-9_-]+$ ]] || { echo "name must be alphanumeric/dash/underscore" >&2; exit 1; }

mkdir -p "$DIR"
cd "$DIR"
umask 077

# --- Create the CA once ---------------------------------------------
if [ ! -f ca.crt ]; then
  echo "Creating client CA (one time)..."
  openssl genrsa -out ca.key 4096
  openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 \
    -subj "/CN=Kiosk Access CA" -out ca.crt
  chmod 600 ca.key
  chmod 644 ca.crt
  echo "CA created."
fi

if [ -f "${NAME}.p12" ]; then
  echo "A certificate for '${NAME}' already exists."
  echo "Delete ${DIR}/${NAME}.* first if you intend to reissue."
  exit 1
fi

# --- Issue the client cert -------------------------------------------
openssl genrsa -out "${NAME}.key" 2048
openssl req -new -key "${NAME}.key" -subj "/CN=${NAME}" -out "${NAME}.csr"
openssl x509 -req -in "${NAME}.csr" \
  -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out "${NAME}.crt" -days "$DAYS" -sha256

# --- Bundle as PKCS#12 for easy install ------------------------------
EXPORT_PW="$(openssl rand -base64 12)"
openssl pkcs12 -export \
  -inkey "${NAME}.key" -in "${NAME}.crt" -certfile ca.crt \
  -name "Kiosk Access - ${NAME}" \
  -out "${NAME}.p12" -passout "pass:${EXPORT_PW}"

rm -f "${NAME}.csr"
chmod 600 "${NAME}.key" "${NAME}.p12"

cat <<EOF

  Certificate issued for: ${NAME}
  File:                   ${DIR}/${NAME}.p12
  Import password:        ${EXPORT_PW}
  Valid for:              ${DAYS} days

  Send the .p12 and the password over SEPARATE channels.

  Install instructions for the helper:
    Windows  double-click the .p12, choose "Current User", enter password
    macOS    double-click, add to login keychain
    Android  Settings > Security > Encryption & credentials > Install a certificate > VPN & app user certificate
    iOS      AirDrop or email the file, then Settings > Profile Downloaded > Install

  After installing, the browser will prompt them to pick this
  certificate the first time they visit the site.

EOF
