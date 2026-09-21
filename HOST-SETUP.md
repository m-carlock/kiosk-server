# Hypervisor host setup

The Fedora box that runs the VMs. Unlike the VMs, **this machine is not
managed by Ansible** — everything here was done by hand. This file is the
record, so the host can be rebuilt without rediscovering any of it.

| | |
|---|---|
| Hardware | HP EliteDesk 800 G6 Mini, i5-10500T, 16 GB |
| OS | Fedora KDE |
| Host IP | `192.168.1.53` (DHCP reservation on the Fios router) |
| kioskbox VM | `192.168.1.55` |
| guacbox VM | `192.168.1.57` |

---

## 1. Virtualization

```bash
sudo dnf install -y @virtualization virt-manager
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt $USER
```

Log out and back in for the group change.

Make `virsh` default to the system connection, where the VMs live:

```bash
echo 'export LIBVIRT_DEFAULT_URI=qemu:///system' >> ~/.bashrc
source ~/.bashrc
```

Without this, `virsh list --all` shows nothing and `virsh autostart Kiosk`
fails with "failed to get domain."

---

## 2. Network bridge

The VMs need real LAN addresses, so they attach to a bridge rather than
libvirt's default NAT network. Do this at the physical console — the host
loses network briefly.

```bash
sudo nmcli connection add type bridge con-name br0 ifname br0 ipv4.method auto
sudo nmcli connection add type bridge-slave con-name br0-slave ifname eno1 master br0
sudo nmcli connection down "Wired connection 1"
sudo nmcli connection up br0
```

Remove the original profile so it can't compete for `eno1` at boot:

```bash
sudo nmcli connection delete "Wired connection 1"
```

Disable Spanning Tree — with a single bridge port it only adds a 30-second
delay before traffic flows after any link change:

```bash
sudo nmcli connection modify br0 bridge.stp no
```

Verify:

```bash
ip -brief addr show br0                 # should hold 192.168.1.53
ip -brief link show master br0          # eno1 plus one vnetN per running VM
```

> **Known gotcha:** if `br0` is taken down and brought back up while VMs
> are running, their `vnet` tap devices detach and don't reattach. Fully
> stop and start each VM (not a reboot from inside the guest) to recover.

---

## 3. Firewall

```bash
sudo firewall-cmd --zone=trusted --change-interface=br0 --permanent
sudo firewall-cmd --add-service=ssh --permanent
sudo firewall-cmd --reload
```

---

## 4. SSH

Fedora Workstation ships with sshd disabled.

```bash
sudo dnf install -y openssh-server
sudo systemctl enable --now sshd
```

---

## 5. VM autostart

```bash
virsh autostart Kiosk
virsh autostart Guac
virsh list --all --autostart            # both should be listed
```

VM settings for reference: UEFI firmware, CPU model `host-passthrough`,
NIC on bridge `br0` with model `virtio`, ballooning off.

---

## 6. ⚠ HARDWARE-SPECIFIC: Intel i219 NIC hang (e1000e driver)

**Applies to this machine's Intel i219 network chip only.** A replacement
host with a different NIC may not need this — or may need something
entirely different. Check the symptom before applying it elsewhere.

### Symptom

Every few hours the whole host drops off the network. Both VMs and
Guacamole become unreachable; the router shows the host and VMs as
inactive. The box itself keeps running normally — lights on, disk active.
Unplugging and replugging the ethernet cable, or rebooting, brings it back.

### Diagnosis

```bash
journalctl -b --no-pager | grep -iE "e1000e|hang|link is" | tail -40
```

The signature is a long run of:

```
e1000e 0000:00:1f.6 eno1: Detected Hardware Unit Hang:
```

followed by `NIC Link is Down`. This is a long-standing bug in the
`e1000e` driver with i219 chips, made more likely by bridging and heavier
traffic. The NIC locks up and stays dead until its link is reset.

### Fix

Disable the hardware offload features that trigger the hang. Negligible
CPU cost on this machine.

Apply immediately, without dropping the connection:

```bash
sudo ethtool -K eno1 tso off gso off gro off
```

Make it persistent across reboots:

```bash
sudo nmcli connection modify br0-slave ethtool.feature-tso off ethtool.feature-gso off ethtool.feature-gro off
```

Verify:

```bash
ethtool -k eno1 | grep -E "tcp-segmentation-offload|generic-segmentation|generic-receive"
nmcli connection show br0-slave | grep -i ethtool.feature
```

All three should read `off` in both.

### Confirming it's fixed

```bash
journalctl -k -b | grep -c "Unit Hang"
```

Should stay at zero. UptimeRobot will also alert if the host drops again.

### If hangs continue anyway

Some i219 revisions keep hanging even with offloads off. The reliable
fallback is a USB 3 gigabit adapter with a Realtek **RTL8153** chip (about
$15), which avoids the `e1000e` driver entirely. Move the bridge slave to
the new interface:

```bash
sudo nmcli connection modify br0-slave connection.interface-name <new-iface>
```

---

## 7. Monitoring

UptimeRobot polls `https://kiosk.salesinusa.com/guacamole/` every 5
minutes from outside the network, testing the full path helpers use: DNS,
Fios, port forward, Caddy, Guacamole.

**When it alerts, don't reboot first.** Work inward and note what fails:

```bash
ping -c3 192.168.1.53       # host on the network?
ping -c3 192.168.1.57       # Guac VM reachable?
curl -sk -o /dev/null -w '%{http_code}\n' https://192.168.1.57/guacamole/
```

| Symptom | Likely cause |
|---|---|
| Host unreachable, box visibly running | NIC hang — see section 6 |
| Host pings, Guac VM doesn't | `vnet` detached from `br0` — see section 2 |
| Guac VM pings, containers down | Docker firewall chains wiped by an nftables reload |
| Everything up internally, external fails | DDNS stale or port forward lost |

Fedora keeps logs across reboots, so if you do have to reboot, the
previous boot is still readable with `journalctl -b -1`.

---

## Rebuilding the host from scratch

1. Install Fedora
2. Sections 1–5 above
3. Check the NIC: `lspci | grep -i ethernet`. If it's an Intel i219, apply
   section 6 pre-emptively rather than waiting for the outages
4. Restore VM disk images, or rebuild the VMs and run the playbooks per
   `RUNBOOK.md`
