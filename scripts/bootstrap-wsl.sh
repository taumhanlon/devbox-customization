#!/usr/bin/env bash
# Configure Ubuntu under WSL for Azure, Linux, networking, and HPC support.
set -Eeuo pipefail

LOG_ROOT="/mnt/c/DevBoxSetup/Logs"
mkdir -p "${LOG_ROOT}"
LOG_FILE="${LOG_ROOT}/bootstrap-wsl-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "${LOG_FILE}") 2>&1

trap 'echo "[ERROR] bootstrap-wsl.sh failed at line ${LINENO}. See ${LOG_FILE}." >&2' ERR

if [[ "${EUID}" -ne 0 ]]; then
    echo "Run this script as root, for example: sudo bash bootstrap-wsl.sh" >&2
    exit 1
fi

echo "[$(date --iso-8601=seconds)] Updating Ubuntu package metadata"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y

# dnsutils supplies dig/nslookup, iputils-ping supplies ping, openssh-client
# supplies ssh/scp, and the remaining packages cover packet and route analysis.
packages=(
    git curl wget jq dnsutils net-tools unzip zip vim nano
    python3 python3-pip python3-venv build-essential cmake gcc g++ make
    openmpi-bin libopenmpi-dev iputils-ping traceroute openssh-client tcpdump
    ca-certificates apt-transport-https gnupg lsb-release software-properties-common
)

echo "[$(date --iso-8601=seconds)] Installing Linux, network, and HPC packages"
apt-get install -y "${packages[@]}"

# Install Azure CLI from Microsoft's signed apt repository. Reusing a keyring and
# source file makes repeat execution safe and avoids the curl-to-shell installer.
echo "[$(date --iso-8601=seconds)] Configuring the Microsoft Azure CLI repository"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor --yes -o /etc/apt/keyrings/microsoft.gpg
chmod a+r /etc/apt/keyrings/microsoft.gpg

architecture="$(dpkg --print-architecture)"
codename="$(lsb_release -cs)"
printf 'Types: deb\nURIs: https://packages.microsoft.com/repos/azure-cli/\nSuites: %s\nComponents: main\nArchitectures: %s\nSigned-by: /etc/apt/keyrings/microsoft.gpg\n' \
    "${codename}" "${architecture}" > /etc/apt/sources.list.d/azure-cli.sources
apt-get update
apt-get install -y azure-cli

# Make aliases available globally and explicitly source them from the invoking
# account's ~/.bashrc. Future Ubuntu users also receive them through /etc/profile.d.
alias_file="/etc/profile.d/azure-support-aliases.sh"
cat > "${alias_file}" <<'ALIASES'
alias k=kubectl
alias ll='ls -al'
alias azs='az account show'
alias azg='az group list -o table'
ALIASES
chmod 0644 "${alias_file}"

user_home="${HOME:-/root}"
bashrc="${user_home}/.bashrc"
touch "${bashrc}"
source_line="source ${alias_file}"
if ! grep -Fqx "${source_line}" "${bashrc}"; then
    printf '\n# Azure Support / HPC aliases\n%s\n' "${source_line}" >> "${bashrc}"
fi

echo "[$(date --iso-8601=seconds)] Verifying core Linux tooling"
az version
mpirun --version | head -n 1
for command_name in nslookup dig ping traceroute ssh scp tcpdump; do
    command -v "${command_name}" >/dev/null
    echo "PASS: ${command_name} -> $(command -v "${command_name}")"
done

echo "WSL bootstrap completed successfully. Log: ${LOG_FILE}"
