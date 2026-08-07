# Windows 11 test lab — Hyper-V setup

Build the kiosk VM on your Windows machine now, so the playbook is
already debugged when the HP 800 G6 arrives.

**This VM is disposable.** You are not going to migrate it. The point
is to get `kiosk.yml` running clean and the whitelist tuned, so that on
the G6 you install Proxmox, make a fresh Debian VM, and run one command.

Ten gates. Don't move past a failed one.

---

# PHASE W1 — Confirm your Windows edition

Hyper-V requires **Windows 11 Pro**, Enterprise, or Education. It is not
available on Home.

Press `Win + R`, type `winver`, Enter. Look at the second line.

Or in PowerShell:

```powershell
(Get-CimInstance Win32_OperatingSystem).Caption
```

### GATE W1

Output says **Pro**, **Enterprise**, or **Education**.

**If it says Home:** stop here and use VirtualBox instead. Everything
downstream is the same except the VM creation steps — download from
virtualbox.org, create a VM with 4 GB RAM and 2 CPUs, set Network →
Attached to → **Bridged Adapter**, and attach the Debian ISO. Then skip
to Phase W5.

---

# PHASE W2 — Confirm hardware virtualization

Open Task Manager (`Ctrl + Shift + Esc`) → **Performance** → **CPU**.

Look at the right-hand stats block for **Virtualization**.

### GATE W2

It reads **Enabled**.

**If it says Disabled:** reboot into your PC's BIOS/UEFI and enable
"Intel VT-x" / "Virtualization Technology" / "SVM Mode". It's usually
under Advanced or Security.

---

# PHASE W3 — Enable Hyper-V

Open PowerShell **as Administrator** (right-click Start → Terminal
(Admin)):

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
```

Reboot when prompted. The reboot takes longer than usual — Windows is
inserting a hypervisor underneath itself.

> **If you have VirtualBox or VMware installed**, be aware Hyper-V takes
> ownership of the virtualization layer and the others will stop working
> or run very slowly. Pick one.

### GATE W3

After reboot, press Start and type `Hyper-V Manager`. It opens and shows
your computer name in the left pane.

---

# PHASE W4 — Create an External virtual switch

This is the step people get wrong, and it costs an afternoon. Hyper-V's
"Default Switch" is NAT'd with a subnet that changes on reboot. You need
the VM to have a **real LAN IP** that Ansible can reach.

1. In Hyper-V Manager, look at the **Actions** pane on the far right.
2. Click **Virtual Switch Manager…**
3. Select **New virtual network switch** → **External** → **Create Virtual Switch**
4. Configure:
   - **Name:** `LAN`
   - **External network:** select your **physical Ethernet adapter** from the dropdown
   - **Check** "Allow management operating system to share this network adapter"
5. Click **OK**. Accept the warning about network disruption.

Your host's network will drop for a few seconds while Windows rebinds
the adapter. This is normal.

> **Use Ethernet, not Wi-Fi**, if you have the option. External switches
> over wireless work but are unreliable in ways that are hard to debug.

### GATE W4

Your Windows machine still has internet. Open a browser and load any
page.

---

# PHASE W5 — Download the Debian ISO

Same file as the runbook:

```
https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.6.0-amd64-netinst.iso
```

Save it somewhere you'll find it, e.g. `C:\ISOs\`.

Verify it:

```powershell
Get-FileHash -Algorithm SHA256 C:\ISOs\debian-13.6.0-amd64-netinst.iso
```

Compare against `SHA256SUMS` from the same directory.

### GATE W5

Hash matches. No USB stick needed this time — Hyper-V boots the ISO
directly.

---

# PHASE W6 — Create the VM

In Hyper-V Manager: **Action** → **New** → **Virtual Machine**.

Walk the wizard:

| Screen | Value |
|---|---|
| Name | `kiosk-test` |
| Generation | **Generation 2** |
| Startup memory | `4096` MB, and **UNCHECK** "Use Dynamic Memory" |
| Configure Networking | **LAN** (the switch from Phase W4) |
| Virtual Hard Disk | Create new, size `32` GB |
| Installation Options | Install from bootable image file → browse to your ISO |

Click **Finish**.

> **Generation 2** is UEFI, matching how you'll configure the VM on
> Proxmox later. **Dynamic Memory off** matters because it's Hyper-V's
> ballooning, and Chromium behaves badly under it.

## Now fix two settings before first boot

Right-click `kiosk-test` → **Settings**.

**Security** → **UNCHECK "Enable Secure Boot"**

The default template only trusts Microsoft-signed bootloaders and the
Debian installer will refuse to start.

**Processor** → **Number of virtual processors:** `2`

**Firmware** → confirm **DVD Drive** is at the top of the boot order.
If it isn't, select it and click **Move Up**.

Click **OK**.

### GATE W6

`kiosk-test` appears in the middle pane with state **Off**.

---

# PHASE W7 — Install Debian

Double-click `kiosk-test` → click **Start** in the connection window.

> If prompted about **Enhanced Session**, choose **Basic Session**. The
> enhanced mode is for Windows guests and will just fail here.

You should land on the Debian installer boot menu.

**From here, follow RUNBOOK.md Phase 4 exactly** — same screens, same
choices. The important ones again:

- Hostname: `kiosk-test` (distinguish it from the real box later)
- Root password: **leave both fields blank**
- Username: `max`
- Partitioning: Guided → entire disk → all files in one partition
- **Software selection: uncheck the desktop environment and GNOME,
  check SSH server and standard system utilities**
- GRUB: install to the virtual disk

The install is faster here than on the laptop — you're on an SSD with a
real network connection.

### GATE W7

VM reboots to a text login prompt. No graphical desktop.

---

# PHASE W8 — Get the VM's IP

Log in at the Hyper-V console as `max`.

```bash
sudo whoami          # expect: root
ip -brief addr       # note the 192.168.x.x address
ping -c3 deb.debian.org
sudo apt update
sudo apt install -y python3 sudo
```

Write down the IP address.

### GATE W8

All commands succeed, and the address is on your **home LAN subnet**
(likely `192.168.x.x`), not `172.x.x.x`.

**If you got a 172.x address:** the VM is on the Default Switch, not
your External switch. Shut down, Settings → Network Adapter → change to
`LAN`, start again.

> Optionally add a DHCP reservation on your router for this VM's MAC
> (`ip -brief link`), so the address doesn't move mid-project.

---

# PHASE W9 — Install WSL2 and Ansible

Ansible doesn't run natively on Windows. In an **Administrator**
PowerShell:

```powershell
wsl --install -d Ubuntu
```

Reboot if prompted. Launch **Ubuntu** from the Start menu. It'll ask you
to create a UNIX username and password — these are separate from your
Windows account.

Then inside the Ubuntu shell:

```bash
sudo apt update
sudo apt install -y pipx openssh-client git
pipx install ansible-core
pipx ensurepath
exec $SHELL
```

### GATE W9

```bash
ansible --version
```

Shows `ansible [core 2.x.x]`.

---

# PHASE W10 — SSH key access

Still in the Ubuntu (WSL) shell.

> **Put the repo inside WSL, not on `/mnt/c/`.** Windows-mounted paths
> report permissions Ansible dislikes, and SSH will reject your key as
> "too open." Use `~/kiosk-server`.

```bash
cd ~
# copy or clone your kiosk-server repo here
ssh-keygen -t ed25519 -C "kiosk lab"      # press Enter through prompts
ssh-copy-id max@192.168.1.60              # your VM's IP
ssh max@192.168.1.60 "hostname; uptime"
```

### GATE W10

You get `kiosk-test` and an uptime line **without a password prompt**.

This is the hard gate — Ansible depends entirely on it.

---

# You're ready

At this point you have:

- A Debian 13 VM on your LAN with a known IP
- Passwordless SSH to it from WSL
- Ansible installed
- The repo in your WSL home directory

That's exactly the state RUNBOOK.md assumes at the start of Phase 9.

## One thing to do before running the playbook

Take a checkpoint. Right-click `kiosk-test` → **Checkpoint**. Name it
`clean-debian`.

If a playbook run goes badly, right-click the checkpoint → **Apply** and
you're back to a fresh install in thirty seconds. You will use this more
than once while tuning.

---

## Reference: useful Hyper-V operations

| Task | How |
|---|---|
| Console access | Double-click the VM in Hyper-V Manager |
| Snapshot | Right-click VM → Checkpoint |
| Roll back | Checkpoints pane → right-click → Apply |
| Change RAM/CPU | VM must be **off** → Settings |
| Find the MAC | Settings → Network Adapter → Advanced Features |
| Clean shutdown | Right-click → Shut Down (not Turn Off) |

`Ctrl + Alt + Left Arrow` releases mouse capture from the console
window.
