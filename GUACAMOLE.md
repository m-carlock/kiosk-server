# Guacamole gateway — setup guide

Browser-based access to the kiosk. Family opens a URL; no client
software to install, which matters given VPN and remote-access apps
are being pulled from Russian app stores.

```
helper's browser
      │  HTTPS + client certificate (mTLS)
      ▼
Caddy  ──────────── your home, port 443 forwarded
      │  localhost:8080
      ▼
Guacamole ── guacd ── RDP over Tailscale ──▶ kioskbox
      │
   Postgres (users, TOTP secrets, connections)
```

Nothing except TCP 443 is exposed. Caddy rejects any TLS connection
without a client certificate issued by your own CA, so scanners never
reach the login page.

---

## Prerequisites

- A domain you own, nameservers pointed at **Cloudflare** (free plan)
- A Cloudflare API token scoped to **Zone : DNS : Edit** on that zone only
- A second Debian 13 VM (or machine) — 2 GB RAM is plenty
- The kiosk box already built, on your tailnet, with `tailscale ip -4` noted
- Ability to forward TCP 443 on the Fios router

---

## PHASE 1 — Domain and DNS

1. Buy the domain. Point its nameservers at Cloudflare.
2. In the Cloudflare dashboard, create an **A record**:
   - Name: `remote` (giving you `remote.yourdomain.com`)
   - IPv4: any placeholder, e.g. `192.0.2.1`
   - TTL: **60 seconds** — not Auto
   - Proxy status: **DNS only (grey cloud)**

> Grey cloud matters. Proxying routes traffic through Cloudflare, and
> Cloudflare has publicly accused Russia of throttling its traffic —
> your family would inherit that. Keep the path direct.

3. Create the API token: My Profile → API Tokens → Create Token →
   Custom → Permissions `Zone / DNS / Edit`, Zone Resources → Include →
   your zone. Copy it once; it isn't shown again.

### GATE 1

```bash
dig +short remote.yourdomain.com
```
Returns your placeholder IP.

---

## PHASE 2 — Secrets

On your workstation, in the repo:

```bash
ansible-vault create group_vars/secrets.yml
```

Put exactly this inside:

```yaml
vault_cloudflare_token: "your_token_here"
vault_guac_db_password: "generate_something_long_and_random"
```

Generate the DB password with `openssl rand -base64 32`.

```bash
echo "group_vars/secrets.yml" >> .gitignore   # belt and braces
git add -A && git commit -m "Add vaulted secrets"
```

The vault file is encrypted at rest, so committing it is safe — but the
`.gitignore` line protects you if you ever decrypt it in place.

### GATE 2

```bash
ansible-vault view group_vars/secrets.yml
```
Shows your two keys after you enter the vault password.

---

## PHASE 3 — Configure

Edit `group_vars/guacamole.yml`. Five things:

```yaml
guac_domain: "remote.yourdomain.com"
cloudflare_zone: "yourdomain.com"
acme_email: "you@yourdomain.com"
kiosk_tailscale_ip: "100.101.102.103"    # tailscale ip -4 on kioskbox
mtls_clients: [helper1, helper2, helper3]
```

Optionally set `ddns_healthcheck_url` to a free healthchecks.io ping
URL. Strongly recommended — it's how you find out DDNS died before
your family does.

Point `inventory.ini`'s `[guacamole]` group at the new VM.

### GATE 3

```bash
ansible -m ping guacamole --ask-vault-pass
```

---

## PHASE 4 — Build

```bash
ansible-playbook guacamole.yml --ask-vault-pass --check --diff
ansible-playbook guacamole.yml --ask-vault-pass
```

Takes 5–10 minutes. Watch for the **client certificate import
passwords** in the output — they're printed once per cert. Save them
now; regenerating means reissuing the cert.

### GATE 4

Play recap shows `failed=0`, and the final task prints your URL.

---

## PHASE 5 — Port forward

On the Fios router: forward **TCP 443** to the Guacamole VM's LAN IP.
Do not forward 80 — the DNS-01 challenge means it's never needed, and
leaving it closed is one less thing exposed.

### GATE 5

From a network **outside** your home (phone on cellular):

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://remote.yourdomain.com/
```

You should get a **TLS error**, not a page. That's success — it means
mTLS is rejecting you for having no client certificate. A `200` here
would mean mTLS is not enforcing.

---

## PHASE 6 — Guacamole configuration

Install one of the `.p12` certs on your own machine first (see the
script output for the import password), then visit the URL.

1. Log in as `guacadmin` / `guacadmin`.
2. **Change that password immediately.** Settings → Preferences.
3. Settings → Connections → New Connection:
   - Name: `Kiosk`
   - Protocol: **RDP**
   - Network → Hostname: your `kiosk_tailscale_ip`, Port `3389`
   - Authentication → Username: `kiosk1`, Password: the kiosk password
   - Security mode: **NLA** (or `Any` if NLA negotiation fails)
   - Check **Ignore server certificate** — xrdp uses a self-signed cert
   - Display → Width `1920`, Height `1080`, Colour depth `24`
4. Repeat per kiosk user, so each helper has their own.
5. Settings → Users → create one Guacamole account per helper, grant
   each **only** their own connection.
6. Each helper enrolls TOTP on first login — they'll be shown a QR code.

> Setting a fixed 1920×1080 in the connection rather than letting the
> browser negotiate keeps the screen resolution constant, which matters
> for the marketplace fingerprint consistency discussed separately.

### GATE 6

Log in as a helper account, open the Kiosk connection, land in the
locked browser.

---

## PHASE 7 — Distribute certificates

For each helper, send:

- their `.p12` file from `/etc/caddy/clients/`
- the import password

**over separate channels.** The file by one route, the password by
another.

To reissue or add someone later:

```bash
sudo /usr/local/bin/make-client-cert.sh helper4 825
```

To revoke: delete `/etc/caddy/clients/<name>.*` and rebuild the CA
bundle — note that with a file-based trust pool, revoking one client
currently means reissuing the CA and all certs. For three helpers
that's acceptable; if you grow past a handful, move to a proper CRL.

### GATE 7

Run the verification script on the box:

```bash
sudo ./verify-guac.sh
```

---

## Operations

| Task | How |
|---|---|
| Add a helper | Add to `mtls_clients`, re-run playbook, create Guacamole user |
| Check DDNS | `systemctl status ddns-update.timer`, `journalctl -t ddns` |
| Force DDNS now | `sudo /usr/local/bin/ddns-update.sh` |
| See banned IPs | `sudo fail2ban-client status guacamole` |
| Update Guacamole | Bump the image tags in `docker-compose.yml.j2`, re-run |
| Caddy logs | `/var/log/caddy/access.log` (JSON) |

---

## Things that will bite you eventually

**DDNS fails silently.** The script dies or the token gets rotated, and
nothing tells you until your family is locked out. This is the single
most likely failure mode. Set `ddns_healthcheck_url`.

**Guacamole needs patching.** `unattended-upgrades` covers the OS but
not the containers. Guacamole has had remotely exploitable bugs in its
RDP handling, and this is an internet-facing service sitting in front of
a machine holding marketplace credentials. Put a quarterly reminder in
your calendar to bump the image tags.

**Client certs expire** after `mtls_cert_days` (825 by default, roughly
27 months). They'll expire silently and simultaneously. Note the date.

**The CA private key is the keys to the kingdom.** `/etc/caddy/clients/ca.key`
— anyone with it can issue themselves access. It's mode 600 root-owned;
keep it that way and don't back it up anywhere casual.

**Keep a fallback path.** Home internet outages, ISP maintenance, and
DDNS failure all look identical from Russia: locked out, no way to tell
you except channels that may themselves be blocked. Agree a
side-channel with your family in advance.
