# System & SSH Hardening Guide

## 1. Overview
Document the security baseline established on your server, including OpenSSH hardening, user access controls, and administrative protections.

## 2. Configuration Files Included
* `sshd_config`: Hardened configuration for `/etc/ssh/sshd_config`.

## 3. Key Security Settings Explained
* **Root Login Policy:** `PermitRootLogin no` (or `prohibit-password`).
* **Authentication:** Password vs. Public Key authentication.
* **Port / Protocol:** Protocol 2, port selection.

## 4. Recovery & Deployment Steps
Step-by-step instructions for an administrator to apply this configuration to a newly provisioned server:

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
* Test login from client or management host.
