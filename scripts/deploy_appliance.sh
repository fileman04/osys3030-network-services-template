#!/usr/bin/env bash
# ==============================================================================
# Script Name : deploy_appliance.sh
# Description : Production-grade idempotent deployment script for an
#               Ubuntu Server 24.04 LTS network appliance.
# Services    : - OpenSSH Hardening (Port 2222, Socket activation / Daemon)
#               - BIND9 Authoritative DNS & Forwarding (Zone: innovate.lab)
#               - Kea DHCPv4 Server (Subnet: 172.168.0.0/24 on ens19)
#               - UFW Firewall & NAT Masquerading (LAN ens19 -> WAN ens18)
#               - Kernel IPv4 Packet Forwarding (sysctl)
# OS Target   : Ubuntu Server 24.04 LTS (Noble Numbat)
# Author      : Senior Linux DevOps Engineer
# Architecture: Dual-NIC Gateway (WAN: ens18, LAN: ens19)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. STRICT SHELL EXECUTION & DEFENSIVE ERROR HANDLING
# ------------------------------------------------------------------------------
# -e          : Exit immediately if any command returns a non-zero exit status.
# -u          : Treat references to unset variables as an error.
# -o pipefail : The return value of a pipeline is the status of the last command
#               to exit with a non-zero status.
set -euo pipefail

# Error trap handler: captures the failing command, line number, and exit code
error_trap() {
    local exit_code="$1"
    local line_num="$2"
    local command="$3"
    echo "" >&2
    log_error "======================================================================"
    log_error "CRITICAL FAILURE: Command '${command}' failed at line ${line_num} with exit code ${exit_code}."
    log_error "Deployment halted to maintain appliance stability. Review errors above."
    log_error "======================================================================"
    exit "${exit_code}"
}
trap 'error_trap $? $LINENO "$BASH_COMMAND"' ERR

# ------------------------------------------------------------------------------
# 2. LOGGING UTILITIES & COLORIZED OUTPUT
# ------------------------------------------------------------------------------
# Terminal ANSI color codes for enhanced readability during manual & CI runs
readonly COLOR_RESET="\033[0m"
readonly COLOR_INFO="\033[0;36m"    # Cyan
readonly COLOR_SUCCESS="\033[0;32m" # Green
readonly COLOR_WARN="\033[1;33m"    # Yellow
readonly COLOR_ERROR="\033[0;31m"   # Red
readonly COLOR_HEADER="\033[1;35m"  # Magenta Bold

timestamp() {
    date +"%Y-%m-%d %H:%M:%S"
}

log_header() {
    echo -e "${COLOR_HEADER}\n[$(timestamp)] ====================================================${COLOR_RESET}"
    echo -e "${COLOR_HEADER}[$(timestamp)]  $*${COLOR_RESET}"
    echo -e "${COLOR_HEADER}[$(timestamp)] ====================================================${COLOR_RESET}"
}

log_info() {
    echo -e "${COLOR_INFO}[$(timestamp)] [INFO]    $*${COLOR_RESET}"
}

log_success() {
    echo -e "${COLOR_SUCCESS}[$(timestamp)] [SUCCESS] $*${COLOR_RESET}"
}

log_warn() {
    echo -e "${COLOR_WARN}[$(timestamp)] [WARN]   $*${COLOR_RESET}" >&2
}

log_error() {
    echo -e "${COLOR_ERROR}[$(timestamp)] [ERROR]  $*${COLOR_RESET}" >&2
}

# ------------------------------------------------------------------------------
# 3. PRIVILEGE & OS ENVIRONMENT VERIFICATION
# ------------------------------------------------------------------------------
# Root access is required for package management, network stack, and permissions
if [[ "${EUID}" -ne 0 ]]; then
    log_error "This script must be executed with root privileges (e.g., sudo $0)."
    exit 1
fi

# Confirm target operating system matches Ubuntu Server 24.04 LTS
if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    if [[ "${ID:-}" != "ubuntu" ]]; then
        log_warn "Host OS '${NAME:-Unknown}' is not Ubuntu. This script is optimized for Ubuntu Server 24.04 LTS."
    elif [[ "${VERSION_ID:-}" != "24.04" ]]; then
        log_warn "Detected Ubuntu version '${VERSION_ID:-}'. Note: Configuration and socket activation targets 24.04 LTS."
    else
        log_info "Verified operating environment: ${PRETTY_NAME}"
    fi
else
    log_warn "Cannot verify /etc/os-release. Proceeding with caution."
fi

# ------------------------------------------------------------------------------
# 4. ENVIRONMENT VARIABLES & PATH DISCOVERY
# ------------------------------------------------------------------------------
# Determine the absolute directory where this deployment script resides
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve the source configuration directory. Users may pass a directory as $1.
CONFIG_SRC_DIR="${1:-${SCRIPT_DIR}}"

# If passed dir doesn't exist or is missing configs, search common relative paths
if [[ ! -f "${CONFIG_SRC_DIR}/sshd_config" ]]; then
    if [[ -f "${SCRIPT_DIR}/Configs for script creation/sshd_config" ]]; then
        CONFIG_SRC_DIR="${SCRIPT_DIR}/Configs for script creation"
    elif [[ -f "${SCRIPT_DIR}/configs/sshd_config" ]]; then
        CONFIG_SRC_DIR="${SCRIPT_DIR}/configs"
    fi
fi

# Centralized backup directory with microsecond precision timestamp
readonly BACKUP_TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
readonly BACKUP_DIR="/var/backups/appliance_deploy_${BACKUP_TIMESTAMP}"

# Expected network appliance hardware/virtual interfaces
readonly WAN_IF="ens18"
readonly LAN_IF="ens19"
readonly LAN_SUBNET="172.168.0.0/24"
readonly SSH_PORT="2222"

# Map of required repository configuration files
readonly CONFIG_SSHD="${CONFIG_SRC_DIR}/sshd_config"
readonly CONFIG_NAMED_LOCAL="${CONFIG_SRC_DIR}/named.conf.local"
readonly CONFIG_NAMED_OPTIONS="${CONFIG_SRC_DIR}/named.conf.options"
readonly CONFIG_NAMED_ZONE="${CONFIG_SRC_DIR}/db.innovate.lab"
readonly CONFIG_KEA_DHCP4="${CONFIG_SRC_DIR}/kea-dhcp4.conf"
readonly CONFIG_UFW_BEFORE="${CONFIG_SRC_DIR}/before.rules"

log_info "Configuration source directory : ${CONFIG_SRC_DIR}"
log_info "Configuration backup directory : ${BACKUP_DIR}"

# ------------------------------------------------------------------------------
# 5. PRE-FLIGHT REPOSITORY CONFIGURATION VERIFICATION
# ------------------------------------------------------------------------------
log_header "Phase 1: Validating Repository Artifacts"

REQUIRED_FILES=(
    "${CONFIG_SSHD}"
    "${CONFIG_NAMED_LOCAL}"
    "${CONFIG_NAMED_OPTIONS}"
    "${CONFIG_NAMED_ZONE}"
    "${CONFIG_KEA_DHCP4}"
    "${CONFIG_UFW_BEFORE}"
)

MISSING_FILES=0
for cfg_file in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "${cfg_file}" ]]; then
        log_error "Missing required repository configuration file: ${cfg_file}"
        MISSING_FILES=$((MISSING_FILES + 1))
    else
        log_info "Found valid source artifact: $(basename "${cfg_file}")"
    fi
done

if [[ "${MISSING_FILES}" -gt 0 ]]; then
    log_error "Pre-flight validation failed: ${MISSING_FILES} configuration file(s) missing from '${CONFIG_SRC_DIR}'."
    log_error "Ensure all 6 repository configuration files exist before running deployment."
    exit 1
fi
log_success "All required configuration files exist in source repository."

# ------------------------------------------------------------------------------
# 6. PACKAGE INSTALLATION (IDEMPOTENT)
# ------------------------------------------------------------------------------
log_header "Phase 2: Installing Required Packages"

# Required packages for OpenSSH, BIND9, Kea DHCPv4, UFW, NAT & routing utilities
PACKAGES=(
    "openssh-server"
    "bind9"
    "bind9utils"
    "bind9-dnsutils"
    "kea-dhcp4-server"
    "ufw"
    "iptables"
    "procps"
    "curl"
    "ca-certificates"
)

# Identify which packages are not currently installed
PKGS_TO_INSTALL=()
for pkg in "${PACKAGES[@]}"; do
    if ! dpkg-query -W -f='${Status}' "${pkg}" 2>/dev/null | grep -q "install ok installed"; then
        PKGS_TO_INSTALL+=("${pkg}")
    fi
done

if [[ ${#PKGS_TO_INSTALL[@]} -gt 0 ]]; then
    log_info "Installing missing packages: ${PKGS_TO_INSTALL[*]}"
    export DEBIAN_FRONTEND=noninteractive
    
    # Refresh apt cache only when packages need to be installed
    log_info "Updating apt package index..."
    apt-get update -y
    
    # Install with recommended flags for non-interactive server deployment
    apt-get install -y --no-install-recommends \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        "${PKGS_TO_INSTALL[@]}"
    log_success "Package installation completed successfully."
else
    log_success "All required packages are already installed. Skipping apt-get install."
fi

# Detect system service account for Kea (Ubuntu 24.04 uses '_kea', fallback 'kea')
KEA_USER="_kea"
if ! id "${KEA_USER}" >/dev/null 2>&1; then
    if id "kea" >/dev/null 2>&1; then
        KEA_USER="kea"
    else
        KEA_USER="root"
    fi
fi
readonly KEA_USER
readonly KEA_GROUP="${KEA_USER}"
log_info "Detected Kea daemon runtime identity: ${KEA_USER}:${KEA_GROUP}"

# Detect system service account for BIND9 (Debian/Ubuntu uses 'bind')
BIND_USER="root"
BIND_GROUP="bind"
if ! getent group "${BIND_GROUP}" >/dev/null 2>&1; then
    BIND_GROUP="root"
fi
readonly BIND_USER
readonly BIND_GROUP
log_info "Detected BIND9 daemon group identity: ${BIND_USER}:${BIND_GROUP}"

# ------------------------------------------------------------------------------
# 7. BACKUP & DEPLOYMENT ENGINE (IDEMPOTENT FILE SYNC)
# ------------------------------------------------------------------------------
log_header "Phase 3: Deploying Configurations with Idempotent Backups"

# Helper function: idempotent deployment of a single file
# Arguments: $1 = source_path, $2 = target_path, $3 = owner, $4 = group, $5 = mode
deploy_file() {
    local src="$1"
    local dest="$2"
    local owner="$3"
    local group="$4"
    local mode="$5"
    local dest_dir
    dest_dir="$(dirname "${dest}")"

    # Ensure destination directory exists with proper traversal permissions
    if [[ ! -d "${dest_dir}" ]]; then
        log_info "Creating directory: ${dest_dir}"
        mkdir -p "${dest_dir}"
    fi

    # Check if target already exists and is identical
    if [[ -f "${dest}" ]]; then
        if cmp -s "${src}" "${dest}"; then
            # File contents match. Ensure permissions and ownership are strictly enforced.
            chown "${owner}:${group}" "${dest}"
            chmod "${mode}" "${dest}"
            log_info "Target '${dest}' is already up-to-date. Enforced permissions (${owner}:${group} ${mode})."
            return 0
        fi

        # File contents differ: create timestamped backup
        mkdir -p "${BACKUP_DIR}/${dest_dir}"
        cp -p "${dest}" "${BACKUP_DIR}/${dest}"
        log_warn "Existing file differed. Created backup at: ${BACKUP_DIR}/${dest}"
    else
        log_info "Deploying new configuration file: ${dest}"
    fi

    # Atomically install new configuration with specified permissions
    install -m "${mode}" -o "${owner}" -g "${group}" "${src}" "${dest}"
    log_success "Successfully deployed ${src} -> ${dest} [${owner}:${group} ${mode}]"
}

# 7.1 Deploy OpenSSH hardened configuration
deploy_file "${CONFIG_SSHD}" "/etc/ssh/sshd_config" "root" "root" "0600"

# Ubuntu 24.04 OpenSSH Override Protection:
# Ubuntu 24.04 includes /etc/ssh/sshd_config.d/*.conf by default.
# Default drop-ins (such as 50-cloud-init.conf) often re-enable PasswordAuthentication
# or conflict with Port 2222. We neutralize any conflicting drop-ins idempotently.
if compgen -G "/etc/ssh/sshd_config.d/*.conf" > /dev/null; then
    for dropin in /etc/ssh/sshd_config.d/*.conf; do
        if [[ -f "${dropin}" ]]; then
            log_warn "Disabling conflicting OpenSSH drop-in snippet: ${dropin}"
            mkdir -p "${BACKUP_DIR}/etc/ssh/sshd_config.d"
            cp -p "${dropin}" "${BACKUP_DIR}/etc/ssh/sshd_config.d/"
            mv "${dropin}" "${dropin}.disabled"
        fi
    done
fi

# 7.2 Deploy BIND9 configuration files
deploy_file "${CONFIG_NAMED_OPTIONS}" "/etc/bind/named.conf.options" "${BIND_USER}" "${BIND_GROUP}" "0644"
deploy_file "${CONFIG_NAMED_LOCAL}" "/etc/bind/named.conf.local" "${BIND_USER}" "${BIND_GROUP}" "0644"
deploy_file "${CONFIG_NAMED_ZONE}" "/etc/bind/db.innovate.lab" "${BIND_USER}" "${BIND_GROUP}" "0644"

# Ensure /var/cache/bind exists and is writable by bind
mkdir -p /var/cache/bind
chown -R "${BIND_USER}:${BIND_GROUP}" /var/cache/bind
chmod 0775 /var/cache/bind

# 7.3 Deploy Kea DHCPv4 configuration
# Ensure /etc/kea directory has appropriate ownership
mkdir -p /etc/kea
chown "${KEA_USER}:${KEA_GROUP}" /etc/kea
chmod 0750 /etc/kea
deploy_file "${CONFIG_KEA_DHCP4}" "/etc/kea/kea-dhcp4.conf" "${KEA_USER}" "${KEA_GROUP}" "0640"

# Ensure Kea logging and runtime directories exist
mkdir -p /var/log/kea /var/run/kea
chown -R "${KEA_USER}:${KEA_GROUP}" /var/log/kea /var/run/kea

# 7.4 Deploy UFW Firewall & NAT Masquerading Rules
deploy_file "${CONFIG_UFW_BEFORE}" "/etc/ufw/before.rules" "root" "root" "0640"

# ------------------------------------------------------------------------------
# 8. KERNEL IPV4 FORWARDING CONFIGURATION
# ------------------------------------------------------------------------------
log_header "Phase 4: Configuring IPv4 Packet Forwarding"

# Deploy dedicated sysctl drop-in file for kernel packet routing
SYSCTL_FORWARD_FILE="/etc/sysctl.d/99-ipforward.conf"
if [[ ! -f "${SYSCTL_FORWARD_FILE}" ]] || ! grep -q "net.ipv4.ip_forward = 1" "${SYSCTL_FORWARD_FILE}"; then
    log_info "Writing sysctl packet forwarding drop-in: ${SYSCTL_FORWARD_FILE}"
    echo "net.ipv4.ip_forward = 1" > "${SYSCTL_FORWARD_FILE}"
    chmod 0644 "${SYSCTL_FORWARD_FILE}"
else
    log_info "Sysctl drop-in ${SYSCTL_FORWARD_FILE} is already configured."
fi

# Ensure UFW's internal sysctl configuration allows IP forwarding as well
if [[ -f /etc/ufw/sysctl.conf ]]; then
    if grep -q "^#net/ipv4/ip_forward=1" /etc/ufw/sysctl.conf; then
        log_info "Uncommenting net/ipv4/ip_forward in /etc/ufw/sysctl.conf..."
        sed -i 's|^#net/ipv4/ip_forward=1|net/ipv4/ip_forward=1|' /etc/ufw/sysctl.conf
    fi
fi

# Apply kernel parameters immediately without reboot
log_info "Applying active sysctl kernel parameters..."
sysctl -p "${SYSCTL_FORWARD_FILE}" >/dev/null

# Validate that the active kernel parameter is strictly 1
ACTIVE_FORWARD="$(cat /proc/sys/net/ipv4/ip_forward)"
if [[ "${ACTIVE_FORWARD}" -ne 1 ]]; then
    log_error "Kernel IPv4 forwarding failed to activate! Current value: ${ACTIVE_FORWARD}"
    exit 1
fi
log_success "IPv4 Packet Forwarding is active in kernel (net.ipv4.ip_forward=1)."

# ------------------------------------------------------------------------------
# 9. UFW FIREWALL & NAT MASQUERADING DEPLOYMENT
# ------------------------------------------------------------------------------
log_header "Phase 5: Configuring UFW Firewall Policies"

# 9.1 Set Default Forward Policy in /etc/default/ufw to ACCEPT (Idempotent)
# This allows packets to be forwarded through the gateway between ens19 and ens18.
if grep -q '^DEFAULT_FORWARD_POLICY="DROP"' /etc/default/ufw; then
    log_info "Updating UFW DEFAULT_FORWARD_POLICY from DROP to ACCEPT..."
    sed -i 's/^DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
fi

# 9.2 Configure Baseline Policies
ufw default deny incoming >/dev/null 2>&1 || true
ufw default allow outgoing >/dev/null 2>&1 || true
ufw default allow routed >/dev/null 2>&1 || true

# 9.3 Open Required Application Ports
# Port 2222/tcp: Hardened OpenSSH management port (Prevents administrative lockout)
log_info "Opening port ${SSH_PORT}/tcp for Hardened SSH..."
ufw allow "${SSH_PORT}/tcp" comment "Hardened OpenSSH Port" >/dev/null 2>&1 || true

# Port 53 (TCP/UDP): BIND9 DNS service for the appliance and local clients
log_info "Opening port 53 (TCP/UDP) for BIND9 DNS resolution..."
ufw allow 53/tcp comment "BIND9 DNS TCP" >/dev/null 2>&1 || true
ufw allow 53/udp comment "BIND9 DNS UDP" >/dev/null 2>&1 || true

# Port 67/udp: Kea DHCPv4 service (accepting broadcasts from LAN clients)
log_info "Opening port 67/udp for Kea DHCPv4 Server on LAN..."
ufw allow 67/udp comment "Kea DHCPv4 Server" >/dev/null 2>&1 || true

# 9.4 Validate iptables rule syntax in before.rules before enabling
log_info "Validating /etc/ufw/before.rules NAT table syntax..."
if ! iptables-restore --test < /etc/ufw/before.rules 2>&1; then
    log_error "Syntax error detected in /etc/ufw/before.rules. Aborting firewall activation."
    exit 1
fi

# 9.5 Enable UFW Firewall Non-Interactively
log_info "Enabling UFW firewall service..."
ufw --force enable >/dev/null 2>&1
log_success "UFW firewall and NAT masquerading configured and enabled."

# ------------------------------------------------------------------------------
# 10. PRE-RESTART CONFIGURATION SYNTAX VALIDATION
# ------------------------------------------------------------------------------
log_header "Phase 6: Validating Service Configuration Syntax"

# 10.1 Validate OpenSSH Configuration
log_info "Validating OpenSSH configuration syntax (/etc/ssh/sshd_config)..."
if ! /usr/sbin/sshd -t -f /etc/ssh/sshd_config; then
    log_error "OpenSSH syntax validation failed! Service restart aborted to prevent lockout."
    exit 1
fi
log_success "OpenSSH syntax is valid."

# 10.2 Validate BIND9 Configuration & Zone Files
log_info "Validating BIND9 named.conf syntax..."
if ! named-checkconf /etc/bind/named.conf; then
    log_error "BIND9 configuration check failed (/etc/bind/named.conf)!"
    exit 1
fi

log_info "Validating BIND9 zone file syntax (innovate.lab)..."
if ! named-checkzone innovate.lab /etc/bind/db.innovate.lab; then
    log_error "BIND9 zone validation failed for innovate.lab (/etc/bind/db.innovate.lab)!"
    exit 1
fi
log_success "BIND9 configuration and zone files are valid."

# 10.3 Validate Kea DHCPv4 Configuration
log_info "Validating Kea DHCPv4 JSON configuration syntax..."
# Check if physical/virtual interface ens19 is available on host
if ! ip link show "${LAN_IF}" >/dev/null 2>&1; then
    log_warn "Network interface '${LAN_IF}' not detected on this system!"
    log_warn "Kea raw socket binding may fail unless '${LAN_IF}' is brought up."
fi

# Execute Kea's built-in syntax parser (-t)
if ! kea-dhcp4 -t /etc/kea/kea-dhcp4.conf; then
    log_error "Kea DHCPv4 configuration syntax check failed (/etc/kea/kea-dhcp4.conf)!"
    exit 1
fi
log_success "Kea DHCPv4 configuration syntax is valid."

# ------------------------------------------------------------------------------
# 11. SERVICE ACTIVATION & RESTART
# ------------------------------------------------------------------------------
log_header "Phase 7: Enabling and Starting Appliance Services"

# Reload systemd manager configuration for changed units and generators
systemctl daemon-reload

# 11.1 Restart OpenSSH (Handling Ubuntu 24.04 Socket Activation)
# On Ubuntu 24.04 LTS, OpenSSH defaults to systemd socket activation (ssh.socket).
# The systemd-ssh-generator reads Port 2222 from sshd_config on daemon-reload.
if systemctl is-active --quiet ssh.socket || systemctl is-enabled --quiet ssh.socket; then
    log_info "Restarting OpenSSH systemd socket (ssh.socket) on port ${SSH_PORT}..."
    systemctl enable ssh.socket
    systemctl restart ssh.socket
else
    log_info "Managing OpenSSH via standalone service unit (ssh.service)..."
    systemctl enable ssh.service
    systemctl restart ssh.service
fi
log_success "OpenSSH service successfully reloaded/restarted."

# 11.2 Enable and Restart BIND9 DNS
log_info "Enabling and restarting BIND9 (named)..."
systemctl enable named
systemctl restart named
log_success "BIND9 service successfully restarted."

# 11.3 Enable and Restart Kea DHCPv4
log_info "Enabling and restarting Kea DHCPv4 server..."
systemctl enable kea-dhcp4-server
systemctl restart kea-dhcp4-server
log_success "Kea DHCPv4 server successfully restarted."

# 11.4 Reload UFW Firewall
log_info "Reloading UFW firewall rules..."
ufw reload >/dev/null
log_success "UFW firewall successfully reloaded."

# ------------------------------------------------------------------------------
# 12. POST-DEPLOYMENT HEALTH AUDIT & VERIFICATION
# ------------------------------------------------------------------------------
log_header "Phase 8: Post-Deployment Appliance Health Audit"

# Function to verify that a systemd unit is active and healthy
verify_service() {
    local service_name="$1"
    if systemctl is-active --quiet "${service_name}"; then
        log_success "Service unit '${service_name}' is ACTIVE (running)."
    else
        log_error "Service unit '${service_name}' is INACTIVE or FAILED!"
        systemctl status "${service_name}" --no-pager -l || true
        return 1
    fi
}

SERVICES_OK=0

# Verify SSH (either socket or service)
if systemctl is-active --quiet ssh.socket; then
    verify_service "ssh.socket" || SERVICES_OK=1
else
    verify_service "ssh.service" || SERVICES_OK=1
fi

# Verify BIND9
verify_service "named" || SERVICES_OK=1

# Verify Kea DHCPv4
verify_service "kea-dhcp4-server" || SERVICES_OK=1

# Verify UFW
verify_service "ufw" || SERVICES_OK=1

if [[ "${SERVICES_OK}" -ne 0 ]]; then
    log_error "Post-deployment health audit identified failing services! Review output above."
    exit 1
fi

echo ""
echo -e "${COLOR_SUCCESS}======================================================================"
echo -e "      NETWORK APPLIANCE DEPLOYMENT COMPLETED SUCCESSFULLY"
echo -e "======================================================================${COLOR_RESET}"
echo ""
echo "Deployment Summary:"
echo "----------------------------------------------------------------------"
echo "  * OpenSSH Server    : Listening on Port ${SSH_PORT} (PermitRootLogin: no, PasswordAuth: no)"
echo "  * BIND9 DNS Server  : Authoritative for 'innovate.lab', Forwarders (1.1.1.1, 10.20.0.1)"
echo "  * Kea DHCPv4 Server : Interface ${LAN_IF}, Subnet ${LAN_SUBNET}, Pool 172.168.0.100-200"
echo "  * IPv4 Forwarding   : net.ipv4.ip_forward = 1 (Kernel active)"
echo "  * NAT Masquerade    : POSTROUTING ${LAN_SUBNET} via ${WAN_IF} MASQUERADE"
echo "  * UFW Firewall      : Active (Allowed: ${SSH_PORT}/tcp, 53/tcp+udp, 67/udp)"
echo "  * Configuration Baks: ${BACKUP_DIR}"
echo "----------------------------------------------------------------------"
echo ""
log_info "Active Listening Ports:"
ss -tulpn | grep -E "(:${SSH_PORT}|:53|:67)" || true
echo ""
log_info "Active NAT Postrouting Table:"
iptables -t nat -L POSTROUTING -n -v --line-numbers
echo ""
log_success "All systems operational. Network appliance is ready for traffic."
exit 0
