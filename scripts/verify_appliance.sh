#!/usr/bin/env bash
# ==============================================================================
# Script Name : verify_appliance.sh (also available as verify_applicance.sh)
# Description : Post-deployment verification and compliance audit script for
#               an Ubuntu Server 24.04 LTS Network Appliance.
# Audits      : - OpenSSH Hardening (Port 2222, effective runtime config, permissions)
#               - BIND9 DNS Server (Syntax, zone integrity, live query tests)
#               - Kea DHCPv4 Server (Syntax, socket/port 67, interface bindings)
#               - IPv4 Forwarding (Active kernel state & persistent sysctl)
#               - UFW Firewall & NAT Masquerade (Active iptables rules, open ports)
#               - Configuration File Ownership & Permission Compliance
# OS Target   : Ubuntu Server 24.04 LTS (Noble Numbat)
# Author      : Senior Linux DevOps Engineer
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. STRICT SHELL EXECUTION & TRAP HANDLING
# ------------------------------------------------------------------------------
# In verification mode, we use -u (unbound vars) and -o pipefail, but handle
# individual test exit codes manually to produce a full test summary.
set -uo pipefail

# ------------------------------------------------------------------------------
# 2. LOGGING UTILITIES & COLOR PALETTE
# ------------------------------------------------------------------------------
readonly COLOR_RESET="\033[0m"
readonly COLOR_PASS="\033[0;32m"   # Green
readonly COLOR_FAIL="\033[0;31m"   # Red
readonly COLOR_WARN="\033[1;33m"   # Yellow
readonly COLOR_INFO="\033[0;36m"   # Cyan
readonly COLOR_TITLE="\033[1;35m"  # Magenta Bold
readonly COLOR_BOLD="\033[1m"      # Bold

# Counters for final test scorecard
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNING_TESTS=0

log_section() {
    echo ""
    echo -e "${COLOR_TITLE}======================================================================${COLOR_RESET}"
    echo -e "${COLOR_TITLE}  $*${COLOR_RESET}"
    echo -e "${COLOR_TITLE}======================================================================${COLOR_RESET}"
}

check_pass() {
    local msg="$1"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    PASSED_TESTS=$((PASSED_TESTS + 1))
    echo -e "  [ ${COLOR_PASS}PASS${COLOR_RESET} ] ${msg}"
}

check_fail() {
    local msg="$1"
    local details="${2:-}"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    FAILED_TESTS=$((FAILED_TESTS + 1))
    echo -e "  [ ${COLOR_FAIL}FAIL${COLOR_RESET} ] ${COLOR_FAIL}${msg}${COLOR_RESET}"
    if [[ -n "${details}" ]]; then
        echo -e "         ${COLOR_WARN}↳ Details: ${details}${COLOR_RESET}"
    fi
}

check_warn() {
    local msg="$1"
    local details="${2:-}"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    WARNING_TESTS=$((WARNING_TESTS + 1))
    echo -e "  [ ${COLOR_WARN}WARN${COLOR_RESET} ] ${COLOR_WARN}${msg}${COLOR_RESET}"
    if [[ -n "${details}" ]]; then
        echo -e "         ${COLOR_INFO}↳ Note: ${details}${COLOR_RESET}"
    fi
}

# ------------------------------------------------------------------------------
# 3. ROOT PRIVILEGE CHECK
# ------------------------------------------------------------------------------
if [[ "${EUID}" -ne 0 ]]; then
    echo -e "${COLOR_FAIL}[ERROR] This verification script requires root privileges to inspect"
    echo -e "        sockets, firewall rules, and restricted configuration files.${COLOR_RESET}"
    echo -e "Please execute with sudo: ${COLOR_BOLD}sudo $0${COLOR_RESET}"
    exit 1
fi

echo -e "${COLOR_TITLE}"
echo "======================================================================"
echo "    UBUNTU SERVER 24.04 LTS NETWORK APPLIANCE VERIFICATION AUDIT     "
echo "======================================================================"
echo -e "${COLOR_RESET}"
echo "Audit started at: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "Host: $(hostname -f 2>/dev/null || hostname) | Kernel: $(uname -r)"

# Expected Network Configuration Variables
readonly WAN_IF="ens18"
readonly LAN_IF="ens19"
readonly LAN_SUBNET="172.168.0.0/24"
readonly SSH_PORT="2222"
readonly DNS_ZONE="innovate.lab"

# ------------------------------------------------------------------------------
# SECTION 1: SYSTEM ENVIRONMENT & INTERFACES
# ------------------------------------------------------------------------------
log_section "Section 1: Host Environment & Network Interfaces"

# 1.1 OS Release Verification
if grep -q "Ubuntu 24.04" /etc/os-release 2>/dev/null; then
    check_pass "Operating System verified: Ubuntu 24.04 LTS."
else
    check_warn "Host is not Ubuntu 24.04 LTS" "$(grep PRETTY_NAME /etc/os-release 2>/dev/null || echo 'Unknown')"
fi

# 1.2 WAN Interface Check (ens18)
if ip link show "${WAN_IF}" >/dev/null 2>&1; then
    WAN_STATE="$(ip -br link show "${WAN_IF}" | awk '{print $2}')"
    check_pass "WAN Interface '${WAN_IF}' detected (State: ${WAN_STATE})."
else
    check_fail "WAN Interface '${WAN_IF}' does not exist on this host."
fi

# 1.3 LAN Interface Check (ens19)
if ip link show "${LAN_IF}" >/dev/null 2>&1; then
    LAN_STATE="$(ip -br link show "${LAN_IF}" | awk '{print $2}')"
    LAN_IP="$(ip -br addr show "${LAN_IF}" 2>/dev/null | awk '{print $3}' | tr '\n' ' ')"
    check_pass "LAN Interface '${LAN_IF}' detected (State: ${LAN_STATE}, IP: ${LAN_IP:-None})."
else
    check_fail "LAN Interface '${LAN_IF}' does not exist on this host."
fi

# ------------------------------------------------------------------------------
# SECTION 2: OPENSSH HARDENING AUDIT
# ------------------------------------------------------------------------------
log_section "Section 2: OpenSSH Hardening & Listening State"

# 2.1 Service / Socket Status
if systemctl is-active --quiet ssh.socket; then
    check_pass "OpenSSH systemd socket activation ('ssh.socket') is ACTIVE."
elif systemctl is-active --quiet ssh.service; then
    check_pass "OpenSSH daemon service ('ssh.service') is ACTIVE."
else
    check_fail "Neither ssh.socket nor ssh.service is currently running!"
fi

# 2.2 Listening Port Verification (Port 2222)
if ss -tulpn | grep -qE ":${SSH_PORT}\s"; then
    check_pass "OpenSSH is listening on hardened port TCP/${SSH_PORT}."
else
    check_fail "OpenSSH is NOT listening on port TCP/${SSH_PORT}." "$(ss -tulpn | grep ssh || echo 'No SSH socket bound')"
fi

# 2.3 Verify Legacy Port 22 is NOT active
if ss -tulpn | grep -qE ":22\s"; then
    check_warn "Legacy Port TCP/22 is still active. Ensure default port 22 is decommissioned."
else
    check_pass "Standard Port TCP/22 is closed."
fi

# 2.4 Configuration Syntax Test
if /usr/sbin/sshd -t -f /etc/ssh/sshd_config 2>/dev/null; then
    check_pass "/etc/ssh/sshd_config passes syntax validation (sshd -t)."
else
    check_fail "/etc/ssh/sshd_config syntax test failed!" "$(/usr/sbin/sshd -t -f /etc/ssh/sshd_config 2>&1)"
fi

# 2.5 Effective Runtime Security Parameter Audit (sshd -T)
# Tests the actual compiled runtime settings to catch any drop-in overrides
SSHD_RUNTIME_OPTS="$(/usr/sbin/sshd -T 2>/dev/null || true)"

if echo "${SSHD_RUNTIME_OPTS}" | grep -qi "^permitrootlogin no"; then
    check_pass "PermitRootLogin is effectively set to 'no'."
else
    check_fail "PermitRootLogin is NOT disabled!" "$(echo "${SSHD_RUNTIME_OPTS}" | grep -i permitrootlogin || echo 'Unset')"
fi

if echo "${SSHD_RUNTIME_OPTS}" | grep -qi "^passwordauthentication no"; then
    check_pass "PasswordAuthentication is effectively set to 'no'."
else
    check_fail "PasswordAuthentication is NOT disabled!" "$(echo "${SSHD_RUNTIME_OPTS}" | grep -i passwordauthentication || echo 'Unset')"
fi

if echo "${SSHD_RUNTIME_OPTS}" | grep -qi "^kbdinteractiveauthentication no"; then
    check_pass "KbdInteractiveAuthentication is effectively set to 'no'."
else
    check_fail "KbdInteractiveAuthentication is NOT disabled!" "$(echo "${SSHD_RUNTIME_OPTS}" | grep -i kbdinteractiveauthentication || echo 'Unset')"
fi

# ------------------------------------------------------------------------------
# SECTION 3: BIND9 DNS SERVER AUDIT & LIVE QUERY TESTS
# ------------------------------------------------------------------------------
log_section "Section 3: BIND9 DNS Server & Query Validation"

# 3.1 Service Status
if systemctl is-active --quiet named || systemctl is-active --quiet bind9; then
    check_pass "BIND9 service ('named') is ACTIVE."
else
    check_fail "BIND9 service is NOT active!"
fi

# 3.2 Listening Ports (53 TCP & UDP)
if ss -ulpn | grep -qE ":53\s"; then
    check_pass "BIND9 is listening on UDP port 53."
else
    check_fail "BIND9 is NOT listening on UDP port 53."
fi

if ss -tlpn | grep -qE ":53\s"; then
    check_pass "BIND9 is listening on TCP port 53."
else
    check_fail "BIND9 is NOT listening on TCP port 53."
fi

# 3.3 Configuration File Syntax Validation
if named-checkconf /etc/bind/named.conf 2>/dev/null; then
    check_pass "BIND9 configuration syntax validation passed (named-checkconf)."
else
    check_fail "named-checkconf reported syntax errors!" "$(named-checkconf /etc/bind/named.conf 2>&1)"
fi

# 3.4 Zone File Syntax Validation
if [[ -f /etc/bind/db.innovate.lab ]]; then
    if named-checkzone "${DNS_ZONE}" /etc/bind/db.innovate.lab >/dev/null 2>&1; then
        ZONE_SERIAL="$(named-checkzone "${DNS_ZONE}" /etc/bind/db.innovate.lab 2>/dev/null | grep -i "serial" || echo "OK")"
        check_pass "Zone '${DNS_ZONE}' is valid (${ZONE_SERIAL})."
    else
        check_fail "named-checkzone failed for zone '${DNS_ZONE}'!" "$(named-checkzone "${DNS_ZONE}" /etc/bind/db.innovate.lab 2>&1)"
    fi
else
    check_fail "Zone file /etc/bind/db.innovate.lab does not exist."
fi

# 3.5 Functional DNS Query Resolution Tests
if command -v dig >/dev/null 2>&1; then
    # Query ns1.innovate.lab
    NS1_RES="$(dig @127.0.0.1 -p 53 "ns1.${DNS_ZONE}" +short +time=2 +tries=1 2>/dev/null || true)"
    if [[ "${NS1_RES}" == "10.20.0.38" ]]; then
        check_pass "DNS Query: ns1.${DNS_ZONE} -> ${NS1_RES} (Authoritative match)."
    else
        check_fail "DNS Query: ns1.${DNS_ZONE} returned '${NS1_RES}', expected '10.20.0.38'."
    fi

    # Query www.innovate.lab
    WWW_RES="$(dig @127.0.0.1 -p 53 "www.${DNS_ZONE}" +short +time=2 +tries=1 2>/dev/null || true)"
    if [[ "${WWW_RES}" == "10.20.0.38" ]]; then
        check_pass "DNS Query: www.${DNS_ZONE} -> ${WWW_RES} (A record match)."
    else
        check_fail "DNS Query: www.${DNS_ZONE} returned '${WWW_RES}', expected '10.20.0.38'."
    fi

    # Query resolver.innovate.lab (CNAME -> ns1)
    RESOLVER_RES="$(dig @127.0.0.1 -p 53 "resolver.${DNS_ZONE}" +short +time=2 +tries=1 2>/dev/null | tail -n1 || true)"
    if [[ "${RESOLVER_RES}" == "10.20.0.38" ]]; then
        check_pass "DNS Query: resolver.${DNS_ZONE} (CNAME) -> ${RESOLVER_RES}."
    else
        check_fail "DNS Query: resolver.${DNS_ZONE} returned '${RESOLVER_RES}', expected '10.20.0.38'."
    fi

    # Query wildcard (*.innovate.lab -> 10.10.10.50)
    WILD_RES="$(dig @127.0.0.1 -p 53 "test99.${DNS_ZONE}" +short +time=2 +tries=1 2>/dev/null || true)"
    if [[ "${WILD_RES}" == "10.10.10.50" ]]; then
        check_pass "DNS Query: Wildcard test99.${DNS_ZONE} -> ${WILD_RES} (Wildcard match)."
    else
        check_fail "DNS Query: Wildcard test99.${DNS_ZONE} returned '${WILD_RES}', expected '10.10.10.50'."
    fi
else
    check_warn "'dig' tool not found. Install bind9-dnsutils for live DNS resolution testing."
fi

# ------------------------------------------------------------------------------
# SECTION 4: KEA DHCPv4 SERVER AUDIT
# ------------------------------------------------------------------------------
log_section "Section 4: Kea DHCPv4 Server & Lease Subnet Configuration"

# 4.1 Service Status
if systemctl is-active --quiet kea-dhcp4-server; then
    check_pass "Kea DHCPv4 service ('kea-dhcp4-server') is ACTIVE."
else
    check_fail "Kea DHCPv4 service is NOT active!" "$(systemctl status kea-dhcp4-server --no-pager -l 2>&1 | tail -n 5)"
fi

# 4.2 Configuration Syntax Test (kea-dhcp4 -t)
if command -v kea-dhcp4 >/dev/null 2>&1; then
    if kea-dhcp4 -t /etc/kea/kea-dhcp4.conf >/dev/null 2>&1; then
        check_pass "Kea configuration syntax validation passed (kea-dhcp4 -t)."
    else
        check_fail "kea-dhcp4 -t detected configuration errors!" "$(kea-dhcp4 -t /etc/kea/kea-dhcp4.conf 2>&1)"
    fi
else
    check_warn "kea-dhcp4 binary not found in PATH."
fi

# 4.3 DHCP Socket / Process Binding
# Kea typically listens on raw sockets or UDP port 67
if ss -ulpn | grep -qE ":67\s" || pgrep -f "kea-dhcp4" >/dev/null 2>&1; then
    check_pass "Kea DHCPv4 process is running and bound to DHCP socket."
else
    check_fail "No active Kea DHCPv4 process or UDP:67 socket found."
fi

# 4.4 Config File Parameter Integrity Checks
if [[ -f /etc/kea/kea-dhcp4.conf ]]; then
    if grep -q "\"${LAN_IF}\"" /etc/kea/kea-dhcp4.conf; then
        check_pass "Kea is configured to listen on interface '${LAN_IF}'."
    else
        check_fail "Kea configuration does not reference interface '${LAN_IF}'."
    fi

    if grep -q "\"${LAN_SUBNET}\"" /etc/kea/kea-dhcp4.conf; then
        check_pass "Kea declares the correct subnet '${LAN_SUBNET}'."
    else
        check_fail "Subnet '${LAN_SUBNET}' not found in /etc/kea/kea-dhcp4.conf."
    fi

    if grep -q "172.168.0.100 - 172.168.0.200" /etc/kea/kea-dhcp4.conf; then
        check_pass "Kea defines the correct pool (172.168.0.100 - 172.168.0.200)."
    else
        check_fail "Pool '172.168.0.100 - 172.168.0.200' not found in /etc/kea/kea-dhcp4.conf."
    fi
fi

# ------------------------------------------------------------------------------
# SECTION 5: KERNEL IPV4 PACKET FORWARDING
# ------------------------------------------------------------------------------
log_section "Section 5: Kernel IPv4 Packet Forwarding State"

# 5.1 Active Kernel Forwarding State
ACTIVE_FORWARD="$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo "0")"
if [[ "${ACTIVE_FORWARD}" -eq 1 ]]; then
    check_pass "Active kernel IPv4 forwarding is ENABLED (/proc/sys/net/ipv4/ip_forward = 1)."
else
    check_fail "Active kernel IPv4 forwarding is DISABLED! Current value: ${ACTIVE_FORWARD}."
fi

# 5.2 Persistent Sysctl Configuration
SYSCTL_CONF_FOUND=0
if [[ -f /etc/sysctl.d/99-ipforward.conf ]] && grep -q "net.ipv4.ip_forward = 1" /etc/sysctl.d/99-ipforward.conf; then
    SYSCTL_CONF_FOUND=1
elif grep -qE "^[[:space:]]*net\.ipv4\.ip_forward[[:space:]]*=[[:space:]]*1" /etc/sysctl.conf 2>/dev/null; then
    SYSCTL_CONF_FOUND=1
fi

if [[ "${SYSCTL_CONF_FOUND}" -eq 1 ]]; then
    check_pass "Persistent sysctl drop-in configured for IPv4 forwarding."
else
    check_fail "Persistent sysctl configuration for net.ipv4.ip_forward=1 was not found!"
fi

# 5.3 UFW Internal Sysctl Setting
if [[ -f /etc/ufw/sysctl.conf ]] && grep -qE "^[[:space:]]*net/ipv4/ip_forward=1" /etc/ufw/sysctl.conf; then
    check_pass "/etc/ufw/sysctl.conf has 'net/ipv4/ip_forward=1' enabled."
else
    check_warn "net/ipv4/ip_forward=1 is commented out or missing in /etc/ufw/sysctl.conf."
fi

# ------------------------------------------------------------------------------
# SECTION 6: UFW FIREWALL & NAT MASQUERADING AUDIT
# ------------------------------------------------------------------------------
log_section "Section 6: UFW Firewall & NAT Masquerade Verification"

# 6.1 UFW Service State
if ufw status | grep -qw "active"; then
    check_pass "UFW firewall service is ACTIVE."
else
    check_fail "UFW firewall is INACTIVE or disabled!" "$(ufw status)"
fi

# 6.2 Default Forward Policy
if grep -q '^DEFAULT_FORWARD_POLICY="ACCEPT"' /etc/default/ufw 2>/dev/null; then
    check_pass "UFW DEFAULT_FORWARD_POLICY is set to 'ACCEPT' for packet routing."
else
    CURRENT_FWD="$(grep '^DEFAULT_FORWARD_POLICY=' /etc/default/ufw 2>/dev/null || echo 'Not found')"
    check_fail "UFW forward policy is not ACCEPT (${CURRENT_FWD}). NAT traffic will be dropped!"
fi

# 6.3 Required Port Rules Check in UFW
UFW_RULES="$(ufw status 2>/dev/null || true)"

# Port 2222/tcp
if echo "${UFW_RULES}" | grep -qE "${SSH_PORT}/tcp.*ALLOW"; then
    check_pass "UFW rule present: ALLOW TCP/${SSH_PORT} (Hardened SSH)."
else
    check_fail "Missing UFW allow rule for port TCP/${SSH_PORT}! Administrative lockout risk."
fi

# Port 53
if echo "${UFW_RULES}" | grep -qE "53.*ALLOW"; then
    check_pass "UFW rule present: ALLOW port 53 (BIND9 DNS)."
else
    check_fail "Missing UFW allow rule for port 53 (DNS)."
fi

# Port 67/udp
if echo "${UFW_RULES}" | grep -qE "67/udp.*ALLOW"; then
    check_pass "UFW rule present: ALLOW UDP/67 (Kea DHCPv4)."
else
    check_fail "Missing UFW allow rule for UDP/67 (DHCP)."
fi

# 6.4 Active IPTables NAT Masquerade Rule
NAT_RULES="$(iptables -t nat -L POSTROUTING -n -v 2>/dev/null || true)"
if echo "${NAT_RULES}" | grep -qE "MASQUERADE.*${WAN_IF}.*172\.168\.0\.0/24" || \
   echo "${NAT_RULES}" | grep -E "MASQUERADE" | grep -q "172.168.0.0/24"; then
    check_pass "Active iptables NAT MASQUERADE rule confirmed in POSTROUTING chain:"
    echo "         ↳ $(echo "${NAT_RULES}" | grep -E "MASQUERADE.*172\.168\.0\.0/24" | head -n 1)"
else
    check_fail "No active NAT MASQUERADE rule found in POSTROUTING chain for ${LAN_SUBNET} -> ${WAN_IF}!"
fi

# ------------------------------------------------------------------------------
# SECTION 7: FILE OWNERSHIP & PERMISSION COMPLIANCE
# ------------------------------------------------------------------------------
log_section "Section 7: File Ownership & Permissions Compliance"

audit_permission() {
    local path="$1"
    local expected_owner="$2"
    local expected_group="$3"
    local max_mode="$4"

    if [[ ! -e "${path}" ]]; then
        check_fail "Expected file '${path}' does not exist!"
        return
    fi

    local actual_owner
    local actual_group
    local actual_mode
    actual_owner="$(stat -c '%U' "${path}")"
    actual_group="$(stat -c '%G' "${path}")"
    actual_mode="$(stat -c '%a' "${path}")"

    local ok=1
    local details=""

    if [[ "${actual_owner}" != "${expected_owner}" ]]; then
        ok=0
        details="Owner is '${actual_owner}', expected '${expected_owner}'. "
    fi

    if [[ "${actual_group}" != "${expected_group}" && "${expected_group}" != "*" ]]; then
        ok=0
        details+="Group is '${actual_group}', expected '${expected_group}'. "
    fi

    # Check that permissions are not broader than max_mode
    if [[ "${actual_mode}" -gt "${max_mode}" ]]; then
        ok=0
        details+="Mode is '${actual_mode}', expected <= '${max_mode}'."
    fi

    if [[ "${ok}" -eq 1 ]]; then
        check_pass "Security permissions compliant: ${path} [${actual_owner}:${actual_group} ${actual_mode}]"
    else
        check_fail "Security permissions violation on ${path}!" "${details}"
    fi
}

audit_permission "/etc/ssh/sshd_config" "root" "root" "600"
audit_permission "/etc/bind/named.conf.options" "root" "*" "644"
audit_permission "/etc/bind/named.conf.local" "root" "*" "644"
audit_permission "/etc/bind/db.innovate.lab" "root" "*" "644"
audit_permission "/etc/kea/kea-dhcp4.conf" "*" "*" "640"
audit_permission "/etc/ufw/before.rules" "root" "root" "640"

# ------------------------------------------------------------------------------
# 8. FINAL SCORECARD & AUDIT SUMMARY
# ------------------------------------------------------------------------------
echo ""
echo -e "${COLOR_TITLE}======================================================================${COLOR_RESET}"
echo -e "${COLOR_TITLE}                     APPLIANCE AUDIT SCORECARD                        ${COLOR_RESET}"
echo -e "${COLOR_TITLE}======================================================================${COLOR_RESET}"
echo -e " Total Checks Conducted : ${COLOR_BOLD}${TOTAL_TESTS}${COLOR_RESET}"
echo -e " Passed Checks          : ${COLOR_PASS}${PASSED_TESTS}${COLOR_RESET}"
echo -e " Failed Checks          : ${COLOR_FAIL}${FAILED_TESTS}${COLOR_RESET}"
echo -e " Warnings               : ${COLOR_WARN}${WARNING_TESTS}${COLOR_RESET}"
echo -e "${COLOR_TITLE}----------------------------------------------------------------------${COLOR_RESET}"

if [[ "${FAILED_TESTS}" -eq 0 ]]; then
    echo -e "${COLOR_PASS}${COLOR_BOLD}OVERALL VERIFICATION STATUS: PASSED${COLOR_RESET}"
    echo -e "${COLOR_PASS}All appliance services, hardening policies, and routing rules are compliant.${COLOR_RESET}"
    exit 0
else
    echo -e "${COLOR_FAIL}${COLOR_BOLD}OVERALL VERIFICATION STATUS: FAILED (${FAILED_TESTS} failures)${COLOR_RESET}"
    echo -e "${COLOR_FAIL}Appliance configuration drift or service degradation detected. Review failures above.${COLOR_RESET}"
    exit 1
fi
