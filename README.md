# Locked-down RDP kiosk server

Debian + xrdp + Openbox + Chromium + Squid + nftables + Tailscale.

Multiple users connect over RDP via Tailscale. Each gets an independent
fullscreen browser that can only reach a whitelisted set of domains.
The whitelist is enforced twice: in the browser (policy) and at the
network layer (Squid, with nftables making the proxy the only route out).

Runs on bare metal today, on a VM guest later, from the same code.

---

## Quick start

**On your workstation** (not the kiosk box):

```bash
pip install ansible-core
git clone <your-repo> && cd kiosk-server
```

**On the kiosk box**: install Debian 13 minimal. At the software selection
screen uncheck everything except *SSH server* and *standard system utilities*.
No desktop environment. Then:

```bash
sudo apt install -y python3 sudo
sudo usermod -aG sudo max
```

Copy your SSH key up: `ssh-copy-id max@192.168.1.50`

**Then, back on your workstation:**

1. Edit `inventory.ini` — set the IP and admin username.
2. Edit `group_vars/all.yml` — set `whitelist_domains`, `start_page`, `kiosk_users`.
3. Dry run: `ansible-playbook kiosk.yml --check --diff`
4. Build: `ansible-playbook kiosk.yml`

**Finally, on the box:**

```bash
sudo passwd kiosk1          # repeat per user
sudo tailscale up
sudo ./verify.sh kiosk1
```

Then disable key expiry for this node in the Tailscale admin console.
The default 180-day expiry will silently drop it off the tailnet otherwise.

Connect from any RDP client to `kioskbox:3389` over Tailscale.

---

## Adding or removing a domain

Edit `whitelist_domains` in `group_vars/all.yml`. One list drives both the
Squid ACL and the Chromium policy, so they cannot drift apart.

```bash
ansible-playbook kiosk.yml --tags never --check   # preview
ansible-playbook kiosk.yml
```

Users must reconnect their RDP session for the browser policy to reload.

**If a whitelisted page renders broken**, it is pulling assets from a domain
you have not listed. Find it:

```bash
sudo tail -f /var/log/squid/access.log | grep DENIED
```

This is why `squid_access_log: true` is the default. Flip it off once the
whitelist has settled.

---

## Redeploying to new hardware

```bash
# 1. Install Debian minimal on the new box, add your SSH key
# 2. Point inventory.ini at it
# 3. Run
ansible-playbook kiosk.yml
```

That is the whole disaster-recovery procedure. Nothing here is
hardware-specific — no disk UUIDs, no interface names, no MAC addresses.
The `iifname "tailscale0"` firewall rule is the only interface reference and
Tailscale always names it that.

---

## Moving to a VM later

When you build the real home server, set `target_type: vm` in
`group_vars/all.yml` and raise `max_sessions` to match the RAM you give the
guest. That is the only change.

`target_type: vm` skips the laptop lid/sleep handling, which is meaningless
in a guest. Leave `enable_zram` on — it costs nothing and helps under
memory pressure regardless.

Recommended guest shape:

| Host RAM | Guest RAM | `max_sessions` |
|---|---|---|
| 16 GB | 8 GB | 5 |
| 32 GB | 16 GB | 10 |

Give the guest a **bridged** interface (not NAT) so it gets a real LAN
address, and run Tailscale **inside the guest** — the guest is the thing
you are migrating, so its network identity should travel with it. The
hypervisor host stays LAN-only with no Tailscale and no exposure.

Do not overcommit RAM or enable ballooning. Chromium under memory pressure
becomes unusable long before it OOMs.

---

## File map

| Path | What it is |
|---|---|
| `group_vars/all.yml` | **The only file you normally edit** |
| `kiosk.yml` | The build |
| `inventory.ini` | Target host |
| `verify.sh` | Run on the box to confirm lockdown holds |
| `templates/chromium-policy.json.j2` | Browser policy (soft whitelist) |
| `templates/squid.conf.j2` | Proxy (hard whitelist) |
| `templates/nftables.conf.j2` | Firewall — makes the proxy unavoidable |
| `templates/xsession.j2` | What each RDP session launches |
| `templates/sesman.ini.j2` | Concurrent session limits |
| `files/openbox-rc.xml` | Stripped WM: no menu, no keybindings |

---

## How the lockdown actually works

Four independent layers. Any one failing does not open the box.

1. **Openbox with empty `<keyboard>` and `<mouse>` sections** — no window
   manager shortcuts, no right-click root menu, no way to launch anything.
2. **Chromium managed policy** — `URLBlocklist: ["*"]` plus an explicit
   allowlist. Also kills devtools, downloads, printing, incognito, file
   pickers, extensions, and sign-in.
3. **Squid** — filters HTTPS on the `CONNECT` hostname. No TLS interception,
   no certificate to install. Catches subresources that the browser policy
   does not.
4. **nftables** — `skgid "kiosks" counter drop` in the output chain, with
   `oif lo accept` first. Kiosk users can reach Squid on loopback and
   nothing else. Squid runs as `proxy` so its own egress is unaffected.

Layer 4 is what turns the whitelist from a preference into a control. If a
user escapes the browser somehow, they still have no network.

**The rule matches the `kiosks` group, not individual users.** If you add a
user by hand, `kiosks` must be its *primary* group or the firewall misses.
`verify.sh` checks this.

---

## Troubleshooting

**Session won't start.** `sudo tail -50 /var/log/xrdp-sesman.log`. Usually
the account is not in `kiosks` (`TerminalServerUsers=kiosks` in sesman.ini
gates login).

**Blank screen after connect.** `~/.xsession` must be executable and owned by
the user. Re-run the playbook.

**Everything is blocked including whitelisted sites.** Squid is probably not
running: `systemctl status squid`. With Squid down, the browser's proxy
setting points at nothing and the firewall blocks the fallback.

**Second user gets kicked to the first user's session.** `Policy=Default` in
sesman.ini matches on username — confirm they are logging in as different
accounts.

**Out of memory.** `free -h`, then lower `max_sessions`. On 4 GB, three
concurrent sessions is the ceiling and two is comfortable.

---

## Notes

- `ansible.builtin.apt_repository` emits a deprecation warning on
  ansible-core 2.21+. It works through 2.24; switch to `deb822_repository`
  when you next touch it.
- The playbook is idempotent. Re-running it is the normal way to apply a
  change, and safe at any time.
- Both config templates carry a "Managed by Ansible" header. If you find
  yourself editing files on the box directly, that change will be reverted
  on the next run — put it in the repo instead.
