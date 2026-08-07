# RUNBOOK — from blank USB to working kiosk

Fifteen phases. Each ends with a **GATE** — a command with expected output.
Do not proceed past a failed gate; every later phase assumes the earlier
ones held.

Total hands-on time: 2–3 hours, most of it waiting on downloads.

**Terminology used throughout:**

- **workstation** — your normal daily-driver computer
- **kioskbox** — the ASUS U38N
- **console** — physically typing on the laptop's own keyboard

---

## Before you start

Gather:

- USB stick, 2 GB or larger, **contents will be destroyed**
- The ASUS U38N, plugged into AC power
- A wired network connection if possible. If the U38N has no RJ45 port,
  a USB-ethernet adapter is a worthwhile $12 — this box is going to run
  unattended in a basement, and wifi drops are a genuinely annoying
  failure mode. Wifi will work (Debian 13's installer bundles non-free
  firmware), it's just less reliable long-term.
- Access to your router's admin page, for a DHCP reservation later

---

# PHASE 1 — Download and verify the ISO

On your **workstation**.

### 1.1 Download

```
https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.6.0-amd64-netinst.iso
```

About 750 MB. Also grab the checksum file from the same directory:

```
https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/SHA256SUMS
```

If the version number has moved past 13.6.0 by the time you read this,
use whatever is in that directory — `current` always points at the
latest point release. Point releases are just rolled-up security
updates; nothing in this build depends on the exact minor version.

### 1.2 Verify

Not optional. You are about to build a security appliance; start by
confirming you have the software you think you have.

**Windows (PowerShell):**
```powershell
Get-FileHash -Algorithm SHA256 .\debian-13.6.0-amd64-netinst.iso
```

**macOS:**
```bash
shasum -a 256 debian-13.6.0-amd64-netinst.iso
```

**Linux:**
```bash
sha256sum debian-13.6.0-amd64-netinst.iso
```

### GATE 1

Open `SHA256SUMS` in a text editor, find the line ending in
`debian-13.6.0-amd64-netinst.iso`, and confirm the hash matches your
computed value character for character.

**If it doesn't match:** re-download. Do not proceed. A mismatch means
either a corrupted transfer or something worse.

---

# PHASE 2 — Flash the USB stick

### Windows — Rufus (recommended)

1. Download Rufus from `https://rufus.ie`
2. Insert USB stick
3. Open Rufus. **Device**: your USB stick — triple-check this, Rufus
   will happily erase the wrong drive
4. **Boot selection**: SELECT → your ISO
5. **Partition scheme**: GPT. **Target system**: UEFI
6. START
7. When prompted **"ISOHybrid image detected"**, choose
   **"Write in DD Image mode"** — this matters, ISO mode produces a
   stick that boots but installs strangely
8. Confirm the destruction warning

### macOS

```bash
diskutil list                        # identify your stick, e.g. /dev/disk4
diskutil unmountDisk /dev/disk4
sudo dd if=debian-13.6.0-amd64-netinst.iso of=/dev/rdisk4 bs=4m status=progress
diskutil eject /dev/disk4
```

Note `rdisk4` not `disk4` in the `dd` line — the raw device is many
times faster.

### Linux

```bash
lsblk                                # identify your stick, e.g. /dev/sdb
sudo umount /dev/sdb*                # ignore "not mounted" errors
sudo dd if=debian-13.6.0-amd64-netinst.iso of=/dev/sdb bs=4M status=progress conv=fsync
sync
```

> **The classic disaster:** `dd` targeting your system disk instead of
> the stick. Run `lsblk` immediately before and confirm the size matches
> your USB stick, not your SSD.

### GATE 2

Re-insert the stick. Your OS should see a small volume, often labelled
something like `Debian 13.6.0 amd64 n`. If the stick appears completely
unreadable on Windows, that's normal for DD mode — proceed.

---

# PHASE 3 — BIOS setup

At the **console**.

1. Power on and immediately tap **F2** repeatedly to enter BIOS setup.
   (**Esc** at power-on gives a one-time boot menu instead, which also
   works.)
2. Under **Boot**: disable Fast Boot if present.
3. Under **Boot**: set **Launch CSM** to Disabled if you see it — you
   want pure UEFI. If the stick then refuses to boot, come back and
   enable it.
4. **Secure Boot** can stay enabled. Debian is signed and boots fine
   under it.
5. Look for a power option along the lines of **"Restore on AC Power
   Loss"** or **"Power On By AC"** and set it to **Power On**. This is
   what gets your basement box back up after an outage. Not all ASUS
   consumer BIOSes expose it; don't worry if it isn't there.
6. Save and exit (**F10**).

Insert the USB stick, power on, tap **Esc** for the boot menu, and
select the USB device (usually listed as `UEFI: <stick name>`).

### GATE 3

You see the Debian installer boot menu with options including
**"Install"** and **"Graphical install"**.

**If the stick doesn't appear in the boot menu:** re-check that you
used DD mode in Rufus, and try toggling CSM.

---

# PHASE 4 — Install Debian

Choose **Graphical install**.

Most screens are self-explanatory. Here are the ones that matter, in
order:

| Screen | What to do |
|---|---|
| Language / Location / Keyboard | Your choices, no consequences |
| Configure the network — hostname | **`kioskbox`** |
| Domain name | Leave **blank** |
| Root password | **LEAVE BOTH FIELDS EMPTY**, press Continue |
| Full name for the new user | Your name |
| Username | **`max`** |
| User password | Pick a strong one; you'll use it for `sudo` |
| Configure the clock | Your timezone |

> **Why blank root password:** when you leave it empty, Debian disables
> the root account and automatically adds your first user to the `sudo`
> group. This is the modern, correct setup and saves you a step. If you
> set a root password instead, you'll have to add `max` to `sudo`
> manually in Phase 5.

**Wifi note:** if you're installing over wifi, the network step will ask
you to pick an SSID and enter the passphrase. Debian 13 includes
non-free firmware on the installer, so most chipsets are detected
without intervention.

### Partitioning

| Prompt | Choose |
|---|---|
| Partitioning method | **Guided — use entire disk** |
| Select disk | The internal drive (only one, unless you've added an SSD) |
| Partitioning scheme | **All files in one partition** |
| Finish partitioning and write changes to disk | **Yes** |

### Package manager

| Prompt | Choose |
|---|---|
| Scan extra installation media | No |
| Debian archive mirror country | United States |
| Mirror | **`deb.debian.org`** |
| HTTP proxy | Leave blank |
| Participate in package usage survey | Either; doesn't matter |

### Software selection — THE IMPORTANT SCREEN

You'll see a checklist. By default **"Debian desktop environment"**,
**"GNOME"**, and **"standard system utilities"** are checked.

Use **Spacebar** to toggle, arrow keys to move.

**Uncheck:**
- [ ] Debian desktop environment
- [ ] GNOME
- [ ] any other desktop environment
- [ ] web server

**Leave checked / check:**
- [x] SSH server
- [x] standard system utilities

Everything else unchecked. Then Continue.

> Getting this wrong isn't fatal but it wastes ~2 GB of disk and leaves
> a desktop environment installed that partially defeats the lockdown.
> If you slip, you can remove it later, but it's cleaner to get it right
> here.

### Bootloader

| Prompt | Choose |
|---|---|
| Install GRUB bootloader | **Yes** |
| Device for bootloader installation | The internal disk (e.g. `/dev/sda`), **not** the USB stick |

Then **Continue** to reboot. **Remove the USB stick** as it reboots.

### GATE 4

The laptop boots to a plain text login prompt:

```
Debian GNU/Linux 13 kioskbox tty1

kioskbox login:
```

No graphical login. If you see a desktop, you left the DE checked —
easiest fix is to reinstall, it's only 20 minutes.

---

# PHASE 5 — First boot checks

At the **console**, log in as `max`.

```bash
# Confirm sudo works
sudo whoami
# expect: root

# Confirm network and get your IP
ip -brief addr
# expect a line like: enp2s0  UP  192.168.1.50/24 ...

# Confirm DNS and internet
ping -c3 deb.debian.org

# Confirm apt works
sudo apt update

# Ansible needs this; usually already present
sudo apt install -y python3 sudo
```

Note the IP address and the interface name — you'll need both.

### GATE 5

All five commands succeed. `sudo whoami` prints `root`.

**If `sudo` says `max is not in the sudoers file`:** you set a root
password during install. Fix it:

```bash
su -                      # enter the root password you set
/usr/sbin/usermod -aG sudo max
exit
exit                      # log out fully, then log back in
```

---

# PHASE 6 — DHCP reservation

In your **router's admin page**, find the DHCP or LAN settings and
create a **reservation** (sometimes called "static lease" or "address
binding") pinning the kioskbox's MAC address to a fixed IP.

Get the MAC from the console:

```bash
ip -brief link
```

This matters less than it would normally — Tailscale means you'll
mostly reach the box by name — but a stable LAN IP makes the Ansible
inventory reliable and saves confusion later.

### GATE 6

Reboot the laptop (`sudo reboot`) and confirm `ip -brief addr` shows
the same address.

---

# PHASE 7 — Workstation: SSH key access

Back on your **workstation**.

### 7.1 Generate a key if you don't have one

```bash
ls ~/.ssh/id_ed25519.pub || ssh-keygen -t ed25519 -C "kioskbox admin"
```

### 7.2 Copy it up

```bash
ssh-copy-id max@192.168.1.50
```

**Windows without `ssh-copy-id`:**
```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh max@192.168.1.50 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

### 7.3 Test

```bash
ssh max@192.168.1.50 "hostname; uptime"
```

### GATE 7

You get `kioskbox` and an uptime line **without being asked for a
password**. This is a hard gate — Ansible depends on it, and you'll be
locking down SSH later.

---

# PHASE 8 — Workstation: install Ansible

### macOS
```bash
brew install pipx && pipx install ansible-core
```

### Linux
```bash
sudo apt install -y pipx && pipx install ansible-core
```

### Windows

Ansible does not run natively on Windows. Use WSL2:

```powershell
wsl --install -d Ubuntu
```

Reboot, open the Ubuntu terminal, then:

```bash
sudo apt update && sudo apt install -y pipx openssh-client
pipx install ansible-core
```

You'll need to redo Phase 7 from inside WSL, since it has its own
`~/.ssh`.

### GATE 8

```bash
ansible --version
# expect: ansible [core 2.x.x] or newer
```

---

# PHASE 9 — Configure the playbook

Put the `kiosk-server` folder somewhere sensible and `cd` into it.

### 9.1 Initialize git — do this now, not later

```bash
git init
git add -A
git commit -m "Initial kiosk build"
```

### 9.2 Edit `inventory.ini`

```ini
[kiosk]
kioskbox ansible_host=192.168.1.50 ansible_user=max
```

Use your actual reserved IP.

### 9.3 Edit `group_vars/all.yml`

The three things that matter:

```yaml
whitelist_domains:
  - yoursite.com
  - anothersite.org

start_page: "https://yoursite.com"

kiosk_users:
  - kiosk1
  - kiosk2
  - kiosk3
```

Leave `max_sessions: 3`, `target_type: baremetal`, `enable_zram: true`,
and `allow_lan_ssh: true` as they are.

> Start with a **deliberately minimal** whitelist — just your primary
> domains, no CDNs. Phase 13 is where you discover what else the sites
> actually need, and it's much easier to add than to work out which of
> twenty entries was unnecessary.

### GATE 9

```bash
ansible -m ping kiosk
```

Expected:
```
kioskbox | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

**If you get a sudo password prompt:** that's `become_ask_pass = True`
in `ansible.cfg` doing its job. Type your `max` password.

**If it hangs or refuses:** Phase 7 didn't actually hold. Go back.

---

# PHASE 10 — Dry run

```bash
ansible-playbook kiosk.yml --check --diff
```

This changes nothing. It reports what *would* change and shows you diffs
of every file it would write.

Read the diffs. This is your last easy chance to catch a typo in the
whitelist.

### GATE 10

The run reaches the end with `failed=0`.

Some tasks will show as `skipped` (the ones gated on `target_type`) and
that's correct.

> **Expect some `--check` noise.** A few tasks can't be fully simulated
> because they depend on files earlier tasks would have created. If you
> see failures in the Tailscale repository tasks specifically, that's a
> known `--check` artifact — proceed to Phase 11 and evaluate the real
> run.

---

# PHASE 11 — Build

Have the laptop physically accessible for this one. The playbook
installs a default-drop firewall; the ruleset is validated before it's
applied and established connections survive the reload, but there's no
reason to be clever about it when the machine is ten feet away.

```bash
ansible-playbook kiosk.yml
```

Takes 10–20 minutes, mostly downloading Chromium and Xorg.

### GATE 11

The play recap shows `failed=0`:

```
kioskbox : ok=38  changed=32  unreachable=0  failed=0  skipped=2
```

And the final debug task prints your next steps.

**If a task fails,** the error output names it. Re-run the whole
playbook after fixing — it's idempotent, so re-running is always safe
and only re-does what's wrong.

---

# PHASE 12 — Passwords, Tailscale, first connection

### 12.1 Set kiosk passwords

SSH in and set one per account. The playbook created them with locked
passwords deliberately, so nothing lands in your git repo.

```bash
ssh max@192.168.1.50
sudo passwd kiosk1
sudo passwd kiosk2
sudo passwd kiosk3
```

These are what your users type at the RDP login screen.

### 12.2 Join the tailnet

```bash
sudo tailscale up
```

It prints a URL. Open it in a browser, authenticate, done.

```bash
tailscale status
tailscale ip -4
```

### 12.3 Turn off key expiry

In the Tailscale admin console (`login.tailscale.com`), find `kioskbox`
in the machine list, open the `...` menu, and select **Disable key
expiry**.

Skip this and your basement box silently falls off the tailnet in 180
days. It is the single most common way these setups break.

### 12.4 Enable MagicDNS

Also in the admin console, under **DNS**, enable **MagicDNS**. Now the
box is reachable as `kioskbox` rather than `100.x.y.z`.

### GATE 12

From your **workstation**, with Tailscale installed and logged in to
the same tailnet:

```bash
tailscale ping kioskbox
ssh max@kioskbox "hostname"
```

Both succeed.

---

# PHASE 13 — Verify the lockdown

```bash
ssh max@kioskbox
cd /path/to/wherever/you/put/verify.sh    # or scp it up
sudo ./verify.sh kiosk1
```

To get the script onto the box:

```bash
# from your workstation
scp verify.sh max@kioskbox:~
```

### GATE 13

```
  9 passed, 0 failed
```

The two that matter most:

- **`PASS  Direct egress blocked`** — the kiosk user cannot reach the
  internet without the proxy. If this fails, the whole security model
  is off. Check `id kiosk1` shows `gid=...(kiosks)`.
- **`PASS  Non-whitelisted domain denied by Squid`** — the whitelist
  is actually enforcing.

Also note the `free -h` output at the end. That's your baseline with
zero sessions running.

---

# PHASE 14 — First RDP session and whitelist tuning

### 14.1 Connect

- **Windows:** Win+R → `mstsc` → Computer: `kioskbox` → Connect
- **macOS/iOS:** Windows App (formerly Microsoft Remote Desktop) → add
  PC `kioskbox`
- **Linux:** `remmina` or `xfreerdp /v:kioskbox`

You'll get a certificate warning on first connect — xrdp generates a
self-signed cert. Accept it.

At the xrdp login screen: session **Kiosk**, username `kiosk1`, the
password you set.

### GATE 14a

Within about 10 seconds you land in a **fullscreen browser showing your
start page**. No taskbar, no window decorations, no address bar
chrome beyond the page itself.

**Blank grey screen instead?** Check the log:
```bash
sudo tail -50 /var/log/xrdp-sesman.log
```

**Login rejected?** The account must be in the `kiosks` group —
`sesman.ini` enforces this. Confirm with `id kiosk1`.

### 14.2 Tune the whitelist

Your sites will almost certainly render partially broken on the first
try, because they pull fonts, scripts, or images from CDNs you haven't
listed.

Leave this running in an SSH window while you browse:

```bash
sudo tail -f /var/log/squid/access.log | grep DENIED
```

Every blocked domain appears there. Collect them, then add the ones you
recognize as legitimate to `whitelist_domains` in `group_vars/all.yml`:

```yaml
whitelist_domains:
  - yoursite.com
  - googleapis.com      # fonts
  - gstatic.com         # fonts
  - jsdelivr.net        # js libraries
```

Re-run:
```bash
ansible-playbook kiosk.yml
git commit -am "Add CDN domains discovered during tuning"
```

**Disconnect and reconnect** the RDP session — Chromium reads policy at
launch.

> **Add domains one batch at a time and re-test.** Resist the urge to
> whitelist everything that appears in the log; some of it is analytics
> and ad infrastructure you're better off leaving blocked.

> **Optional debugging aid:** `chrome://policy` is blocked by default,
> which means you can't inspect loaded policy from inside the kiosk. If
> you need to during tuning, remove the `"chrome://policy",` line from
> `templates/chromium-policy.json.j2`, re-run the playbook, inspect,
> then put it back.

### GATE 14b

Your sites render correctly, and typing a non-whitelisted domain in the
address bar produces a block page.

---

# PHASE 15 — Concurrent sessions, resilience, final lockdown

### 15.1 Concurrency test

From two different devices, connect simultaneously as `kiosk1` and
`kiosk2`. Navigate to different pages in each.

On the box:

```bash
ps -eo user,comm | grep Xorg
# expect one Xorg per active session

free -h
```

### GATE 15a

Two independent sessions, neither affecting the other. Check `free -h`:
if **available** memory is under ~400 MB with two sessions running,
lower `max_sessions` to 2 and tell your users so.

> With 4 GB, two sessions is comfortable and three is tight. If three
> is a hard requirement, an SSD swap (the U38N shipped with a spinning
> disk) is the upgrade that makes it tolerable, since zram overflow
> lands on disk.

### 15.2 Reboot resilience

```bash
sudo reboot
```

Wait two minutes, then from your workstation:

```bash
ssh max@kioskbox "systemctl is-active squid nftables xrdp xrdp-sesman tailscaled"
```

### GATE 15b

Five lines, all `active`. Then reconnect over RDP and confirm you land
in the browser.

This proves the box recovers unattended — which is the whole point of a
basement server.

### 15.3 Lid test

Close the laptop lid. From your workstation, `ssh max@kioskbox
"uptime"`. It should still respond. Reconnect over RDP; the session
should still work.

If RDP shows a black screen with the lid closed, the display output is
being disabled and xrdp's virtual display is being affected. An
inexpensive HDMI dummy plug resolves it, or just run lid-open.

### 15.4 Final lockdown (optional)

Only after everything above passes, and only if you're comfortable that
Tailscale access is solid:

```yaml
# group_vars/all.yml
allow_lan_ssh: false
```

```bash
ansible-playbook kiosk.yml
```

Now the box has **zero** exposed surface on your LAN. Everything goes
through Tailscale.

> **Before you do this**, confirm `ssh max@kioskbox` works over
> Tailscale with the LAN route unavailable — e.g. from your phone on
> cellular with Tailscale on. If you lock LAN SSH and Tailscale then
> breaks, your recovery path is carrying a keyboard to the basement.

### GATE 15c

```bash
ssh max@kioskbox "hostname"          # over Tailscale — works
ssh max@192.168.1.50 "hostname"      # over LAN — times out
```

---

# Done. Now protect the work.

```bash
git add -A
git commit -m "Working kiosk configuration"
git remote add origin <your-private-repo>
git push -u origin main
```

**This repo is the machine.** The laptop is disposable hardware running
a build defined entirely in these files. When it dies — and a 2013
ultrabook eventually will — you install Debian on whatever replaces it,
change one line in `inventory.ini`, and run the playbook.

---

# Ongoing operation

| Task | How |
|---|---|
| Add a whitelist domain | Edit `group_vars/all.yml`, `ansible-playbook kiosk.yml`, reconnect sessions |
| Add a user | Add to `kiosk_users`, run playbook, `sudo passwd newuser` |
| Remove a user | `sudo userdel -r olduser` on the box, remove from `kiosk_users` |
| Change start page | Edit `start_page`, run playbook |
| OS security updates | Automatic. Reboots at 04:30 when the kernel updates |
| Check health | `sudo ./verify.sh` |
| Quiet the Squid log | Set `squid_access_log: false` once tuning is done |

Re-running the playbook is always the right way to change anything. If
you edit a config file directly on the box, the next run reverts it —
that's the design, not a bug.

---

# Quick troubleshooting index

| Symptom | Look at |
|---|---|
| RDP login rejected | `id <user>` — primary group must be `kiosks` |
| Blank/grey screen after login | `/var/log/xrdp-sesman.log`; `~/.xsession` must be executable |
| Everything blocked, including allowed sites | `systemctl status squid` — if Squid is down, nothing works |
| Site renders broken | `tail -f /var/log/squid/access.log \| grep DENIED` |
| Second user lands in first user's session | Confirm they're using different accounts |
| Sessions sluggish / swapping hard | `free -h`, lower `max_sessions` |
| Box unreachable after reboot | Physical console; check `tailscale status` |
| Tailscale stopped working after months | Key expiry. Disable it in the admin console |
