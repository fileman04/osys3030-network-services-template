# Kea DHCPv4 Server Guide

## 1. Overview
This server provides Dynamic Host Configuration Protocol (DHCP) services to clients on the internal LAN network using Kea DHCPv4. The service automatically assigns IP addresses and distributes required network information including the default gateway, DNS server address, and subnet mask.

The DHCP service supports the internal client subnet and works alongside the BIND9 DNS service and UFW/NAT routing configuration

## 2. Configuration Files Included
* `kea-dhcp4.conf`: Configuration file for `/etc/kea/kea-dhcp4.conf`.

## 3. Scope & Option Architecture
* **Listening Interface:** `ens19` (bound exclusively to LAN).
* **Subnet:** `172.168.0.0/24`
* **Dynamic Pool:** `172.168.0.100 - 172.168.0.200`
* **Default Router (Option 3):** `172.168.0.250` (Server `ens19` IP)
* **Domain Name Server (Option 6):** `172.168.0.250` (Internal BIND9 IP)

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
On your **Alpine Linux Client VM** (`OSYS3030-william.mcnea-client` / VM `9116`):

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
