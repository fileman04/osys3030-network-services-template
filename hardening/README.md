# System & SSH Hardening Guide

## 1. Overview
This server uses OpenSSH for remote administration. Security hardening was applied to reduce the attack surface and protect against unauthorized access.

Implemented hardening measures include:

Disabled direct root login
Public key authentication enabled
Reduced brute-force attack opportunities
Restricted unnecessary SSH features
Verified configuration before deployment

## 2. Configuration Files Included
* `sshd_config`: Hardened configuration for `/etc/ssh/sshd_config`.

## 3. Key Security Settings Explained
* **Root Login Policy:** `PermitRootLogin no` 
* **Authentication:** PasswordAuthentication no PubkeyAuthentication yes
* **Port / Protocol:** Protocol 2, port selection 2222

## 4. Recovery & Deployment Steps
run sudo apt update -> sudo apt install openssh-server -y
systemctl status ssh

```bash
# 1. Back up default configuration
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.orig

# 2. Deploy hardened configuration
sudo cp sshd_config /etc/ssh/sshd_config

# 3. Test syntax before restarting
sudo sshd -t

# 4. Restart SSH service
sudo systemctl restart ssh
```

## 5. Verification & Troubleshooting
* Check service status: `sudo systemctl status ssh`
* Check active listening port: `sudo ss -tulpn | grep sshd`
* Test login from client or management host. ssh mcnea@10.20.0.38

