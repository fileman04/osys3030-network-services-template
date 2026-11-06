# BIND9 Domain Name System (DNS) Guide

## 1. Overview
Document your BIND9 DNS architecture. This server acts as:
1. **Authoritative Nameserver:** Hosts the internal forward lookup zone (`innovate.lab`) and reverse lookup zone (`0.<YourID>.10.in-addr.arpa`).
2. **Caching / Recursive Resolver:** Forwards external DNS queries to upstream nameservers (e.g. NSCC / 8.8.8.8).

## 2. Configuration Files Included
* `named.conf.local`: Internal zone declarations for forward and reverse lookups.
* `named.conf.options`: Forwarders, access control lists (ACLs), and recursion settings.
* `db.innovate.lab`: Forward zone records.
* `db.10.<YourID>.0`: Reverse zone records (PTR).

## 3. Recovery & Deployment Steps
```bash
# 1. Install BIND9 and utility packages
sudo apt update
sudo apt install bind9 bind9utils bind9-doc dnsutils -y

# 2. Deploy configuration files
sudo cp named.conf.options /etc/bind/named.conf.options
sudo cp named.conf.local /etc/bind/named.conf.local
sudo cp db.innovate.lab /etc/bind/zones/db.innovate.lab
sudo cp db.10.<YourID>.0 /etc/bind/zones/db.10.<YourID>.0

# 3. Set proper ownership and permissions
sudo chown -R bind:bind /etc/bind/zones
sudo chmod 644 /etc/bind/zones/*

# 4. Check configuration syntax
sudo named-checkconf
sudo named-checkzone innovate.lab /etc/bind/zones/db.innovate.lab
sudo named-checkzone 0.<YourID>.10.in-addr.arpa /etc/bind/zones/db.10.<YourID>.0

# 5. Restart BIND9 service
sudo systemctl restart named
sudo systemctl enable named
```

## 4. Verification & Troubleshooting
* Check service status: `sudo systemctl status named`
* Test local resolution:
  ```bash
  dig @127.0.0.1 ns1.innovate.lab +short
  dig @10.<YourID>.0.250 www.innovate.lab +short
  dig @10.<YourID>.0.250 -x 10.<YourID>.0.250 +short
  ```
* Check query logs: `sudo journalctl -u named -n 50 --no-pager`
