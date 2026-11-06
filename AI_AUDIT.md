# AI Automation & Code Audit Log

> **Student Name:** William McNea
> **Student ID:** w0421151
> **AI Tool Used:** Co-Pilot, Antigravity

---

## 1. Executive Summary
I used Anti gravity, gave it a copy of my config files and used it to create a script to deploy the services as I have configured in case of disaster

---

## 2. Prompt Log
### 2.1 Deployment Script Prompt
Act as a Senior Linux DevOps Engineer.

Using the attached configuration files and documentation for:

- OpenSSH hardening
- BIND9 DNS
- Kea DHCPv4
- UFW firewall
- NAT masquerading

running on Ubuntu Server 24.04 LTS,

create an idempotent Bash deployment script called
deploy_appliance.sh.

Requirements:

- Install required packages
- Backup existing configurations
- Deploy configuration files from the repository
- Set appropriate permissions
- Enable IPv4 forwarding
- Enable and start services
- Validate configuration syntax before restarting services
- Exit if any critical step fails
- Include comments explaining each section

here is the firewall before.rules file. the other configuration files are in the folder linked with this promptConfigs for script creation

### 2.2 Verification Script Prompt
After this promt ran I then followed with


now write a companion script that will verify the deployment script configurations and call it verify_applicance.sh

thankfully it caught my spelling mistake and named the script verify_appliance.sh


---

## 3. Human-in-the-Loop Audit & Hallucination Corrections

AI models frequently introduce errors when writing infrastructure automation. Document at least 2 specific errors, bugs, or omissions the AI made in the generated scripts and how you fixed them:

| # | Service / Component | The AI's Hallucination / Error | The Fix Implemented |
| :--- | :--- | :--- | :--- |
| **1** | e.g., Kea DHCP | Used deprecated ISC-DHCP commands (`systemctl restart isc-dhcp-server`) | Replaced with `systemctl restart kea-dhcp4-server` |
| **2** | e.g., BIND9 | Forgot to set `chown -R bind:bind /etc/bind/zones` | Added explicit ownership fix before service start |
| **3** | e.g., UFW NAT | Added MASQUERADE rule at the bottom of `before.rules` instead of before `*filter` | Positioned the `*nat` table block before the `*filter` block per UFW requirements |

---

## 4. Testing & Verification Results

* **Date Tested:** Nov 5 2026
* **Target Environment:**  [OSYS3030 Baseline Server (VMID 116)]
* **Verification Script Output:**
  ======================================================================
                     APPLIANCE AUDIT SCORECARD                     
======================================================================
 Total Checks Conducted : 40
 Passed Checks          : 32
 Failed Checks          : 6
 Warnings               : 2
----------------------------------------------------------------------

---

## 5. Attestation
I attest that I have personally reviewed, tested, and understand every line of code in the generated scripts. I am prepared to explain any part of these scripts or configuration files during an evaluation.
