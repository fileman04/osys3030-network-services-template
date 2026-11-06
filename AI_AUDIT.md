# AI Automation & Code Audit Log

> **Student Name:** [Your Name]  
> **Student ID:** [Your ID]  
> **AI Tool Used:** [e.g., ChatGPT 4o / Claude 3.5 Sonnet / Gemini 1.5 Pro]  

---

## 1. Executive Summary
Briefly explain how you used AI as an engineering tool to translate your Markdown documentation into executable Bash scripts (`deploy_appliance.sh` and `verify_appliance.sh`).

---

## 2. Prompt Log

### 2.1 Deployment Script Prompt
Paste the exact prompt you gave the AI to generate `deploy_appliance.sh`:

```text
[Paste your prompt here]
```

### 2.2 Verification Script Prompt
Paste the exact prompt you gave the AI to generate `verify_appliance.sh`:

```text
[Paste your prompt here]
```

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

* **Date Tested:** [YYYY-MM-DD]
* **Target Environment:** [e.g., OSYS3030 Baseline Server (VMID 106)]
* **Verification Script Output:**
  ```text
  [Paste the terminal output of running sudo ./scripts/verify_appliance.sh showing PASS]
  ```

---

## 5. Attestation
I attest that I have personally reviewed, tested, and understand every line of code in the generated scripts. I am prepared to explain any part of these scripts or configuration files during an evaluation.
