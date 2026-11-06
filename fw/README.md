# Firewall & NAT Masquerade Gateway Guide

## 1. Overview
Document your security policy using **UFW** (Uncomplicated Firewall) and packet forwarding with **iptables NAT masquerading**. This transforms your Linux server into a secure router allowing private LAN clients on `ens19` to access the internet via `ens18`.

## 2. Configuration Files Included
* `before.rules`: Custom iptables rules placed at the top of `/etc/ufw/before.rules` to enable NAT masquerading.
* `sysctl.conf` snippet: Kernel packet forwarding setting (`net.ipv4.ip_forward = 1`).
* `ufw.conf` / UFW rules: Allowlist rules for SSH, DNS, and DHCP.

## 3. Kernel Forwarding Configuration
In `/etc/sysctl.conf`:
```ini
net.ipv4.ip_forward=1
```
Apply without rebooting:
```bash
sudo sysctl -p
```

## 4. NAT Masquerading Rules (`/etc/ufw/before.rules`)
Add the `*nat` table block before the `*filter` block:
```ini
# NAT table rules
*nat
:POSTROUTING ACCEPT [0:0]

# Forward traffic from LAN (ens19) out WAN (ens18)
-A POSTROUTING -s 10.<YourID>.0.0/24 -o ens18 -j MASQUERADE

# Commit the NAT rules
COMMIT
```

## 5. UFW Policy & Port Allowlist
```bash
# Default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw default allow routed

# Service rules
sudo ufw allow in on ens18 to any port 22 proto tcp comment 'SSH Admin'
sudo ufw allow in on ens19 to any port 53 comment 'BIND9 DNS'
sudo ufw allow in on ens19 to any port 67 proto udp comment 'Kea DHCP'

# Enable UFW
sudo ufw enable
```

## 6. Verification & Troubleshooting
* Check firewall status: `sudo ufw status verbose`
* Check active NAT masquerading rules: `sudo iptables -t nat -L -v -n`
* From Alpine Client VM (`91<ID>`):
  ```bash
  # Must succeed if NAT is functional:
  ping -c 3 8.8.8.8
  ping -c 3 google.com
  ```
