# Kea DHCPv4 Server Guide

## 1. Overview
Document your modern ISC Kea DHCPv4 configuration. Kea allocates dynamic IPv4 addresses to client devices on your isolated private VLAN (`ens19`).

## 2. Configuration Files Included
* `kea-dhcp4.conf`: Configuration file for `/etc/kea/kea-dhcp4.conf`.

## 3. Scope & Option Architecture
* **Listening Interface:** `ens19` (bound exclusively to LAN).
* **Subnet:** `10.<YourID>.0.0/24`
* **Dynamic Pool:** `10.<YourID>.0.10 - 10.<YourID>.0.200`
* **Default Router (Option 3):** `10.<YourID>.0.250` (Server `ens19` IP)
* **Domain Name Server (Option 6):** `10.<YourID>.0.250` (Internal BIND9 IP)

## 4. Recovery & Deployment Steps
```bash
# 1. Install Kea DHCPv4 Server
sudo apt update
sudo apt install kea-dhcp4-server -y

# 2. Deploy sanitized configuration
sudo cp kea-dhcp4.conf /etc/kea/kea-dhcp4.conf

# 3. Test configuration syntax
sudo kea-dhcp4 -t /etc/kea/kea-dhcp4.conf

# 4. Restart and enable Kea service
sudo systemctl restart kea-dhcp4-server
sudo systemctl enable kea-dhcp4-server
```

## 5. Client Verification & Alpine Linux Notes
On your **Alpine Linux Client VM** (`OSYS3030-<username>-client` / VM `91<ID>`):

> [!NOTE]
> Alpine Linux uses BusyBox `udhcpc`. BusyBox requires `eth0` to be administratively `UP` before broadcasting!

```bash
# 1. Acquire DHCP lease on client
ip link set eth0 up
udhcpc -i eth0

# 2. Verify IP and default route
ip a show eth0
ip route

# 3. Verify pushed DNS nameserver
cat /etc/resolv.conf
```

## 6. Server Lease Inspection
Inspect active leases recorded by Kea:
```bash
sudo cat /var/lib/kea/kea-leases4.csv
```
