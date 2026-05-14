#!/usr/bin/env bash
# =============================================================================
# Script 1 : Installation de Proxmox VE 8.x sur Ubuntu 22.04 LTS
# =============================================================================
# Ce script migre un serveur Ubuntu 22.04 (Jammy) vers Proxmox VE en ajoutant
# les dépôts officiels Proxmox (compatibles Bookworm au niveau APT).
# Un REBOOT est obligatoire à la fin pour booter sur le kernel PVE.
# =============================================================================

set -euo pipefail

# ── Variables à modifier ──────────────────────────────────────────────────────
PVE_HOSTNAME="${PVE_HOSTNAME:-pve.monserveur.com}"
# L'IP sera détectée automatiquement si laissée à "AUTO"
MAIN_IP="${MAIN_IP:-AUTO}"
# =============================================================================

# ── Couleurs ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── Fonctions utilitaires ─────────────────────────────────────────────────────
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Ce script doit être exécuté en tant que root."
        exit 1
    fi
}

generate_password() {
    openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 20
}

detect_main_ip() {
    ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}'
}

save_credential() {
    local label="$1"
    local value="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | ${label}: ${value}" >> /root/.vps-infra-credentials
}

check_ubuntu_22() {
    if ! grep -qi "ubuntu 22.04" /etc/os-release 2>/dev/null; then
        log_error "Ce script requiert Ubuntu 22.04 LTS. Distribution détectée :"
        cat /etc/os-release | grep PRETTY_NAME || true
        exit 1
    fi
    log_success "Ubuntu 22.04 LTS détecté."
}

# ── Idempotence : vérifier si Proxmox est déjà installé ──────────────────────
check_already_installed() {
    if dpkg -l proxmox-ve &>/dev/null 2>&1; then
        log_warn "proxmox-ve est déjà installé. Exécution ignorée."
        log_info "Version : $(pveversion 2>/dev/null || echo 'inconnue')"
        exit 0
    fi
}

# ── Étape 1 : Prérequis système ───────────────────────────────────────────────
step_prerequisites() {
    log_info "Mise à jour des paquets système..."
    apt-get update -qq
    apt-get install -y -qq \
        curl wget gnupg2 apt-transport-https \
        ca-certificates lsb-release software-properties-common \
        postfix open-iscsi

    # Désactiver os-prober pour éviter les conflits GRUB dans un environnement virtualisé
    if ! grep -q "^GRUB_DISABLE_OS_PROBER=true" /etc/default/grub 2>/dev/null; then
        echo 'GRUB_DISABLE_OS_PROBER=true' >> /etc/default/grub
    fi
}

# ── Étape 2 : Configurer /etc/hosts avec le FQDN ────────────────────────────
step_configure_hosts() {
    local ip
    if [[ "$MAIN_IP" == "AUTO" ]]; then
        ip=$(detect_main_ip)
    else
        ip="$MAIN_IP"
    fi

    if [[ -z "$ip" ]]; then
        log_error "Impossible de détecter l'IP principale. Définissez MAIN_IP manuellement."
        exit 1
    fi

    log_info "Configuration de /etc/hosts avec IP=${ip} FQDN=${PVE_HOSTNAME}"

    # Retirer les anciennes entrées PVE si elles existent déjà
    sed -i "/# PVE-ENTRY/d" /etc/hosts

    local short_hostname
    short_hostname=$(echo "$PVE_HOSTNAME" | cut -d. -f1)

    echo "${ip}  ${PVE_HOSTNAME} ${short_hostname}  # PVE-ENTRY" >> /etc/hosts

    # Mettre à jour le hostname
    hostnamectl set-hostname "${short_hostname}"
    log_success "Hostname configuré : ${PVE_HOSTNAME}"
}

# ── Étape 3 : Ajouter le dépôt Proxmox VE ────────────────────────────────────
step_add_proxmox_repo() {
    local keyring="/etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg"
    local sources_file="/etc/apt/sources.list.d/pve-no-subscription.list"

    if [[ -f "$keyring" ]]; then
        log_warn "Clé GPG Proxmox déjà présente, passage à l'étape suivante."
    else
        log_info "Téléchargement de la clé GPG Proxmox VE..."
        wget -q -O "$keyring" \
            https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg
        log_success "Clé GPG installée."
    fi

    if [[ -f "$sources_file" ]]; then
        log_warn "Dépôt Proxmox déjà configuré."
    else
        log_info "Ajout du dépôt Proxmox VE (no-subscription)..."
        echo "deb [arch=amd64] http://download.proxmox.com/debian/pve bookworm pve-no-subscription" \
            > "$sources_file"
        log_success "Dépôt Proxmox ajouté."
    fi

    # Désactiver le dépôt enterprise (nécessite un abonnement payant)
    if [[ ! -f /etc/apt/sources.list.d/pve-enterprise.list ]]; then
        echo "# deb https://enterprise.proxmox.com/debian/pve bookworm pve-enterprise" \
            > /etc/apt/sources.list.d/pve-enterprise.list
    fi
}

# ── Étape 4 : Installer Proxmox VE ───────────────────────────────────────────
step_install_proxmox() {
    log_info "Mise à jour des dépôts..."
    apt-get update -qq

    log_info "Installation de proxmox-ve (cela peut prendre plusieurs minutes)..."
    # DEBIAN_FRONTEND=noninteractive pour éviter les prompts interactifs
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        proxmox-ve \
        pve-manager \
        pve-kernel-6.8 \
        libpve-storage-perl \
        bridge-utils

    log_success "Proxmox VE installé."
}

# ── Étape 5 : Supprimer les meta-packages Ubuntu ─────────────────────────────
step_remove_ubuntu_kernel() {
    log_info "Suppression des meta-packages kernel Ubuntu..."

    for pkg in linux-image-generic linux-headers-generic linux-image-virtual; do
        if dpkg -l "$pkg" &>/dev/null 2>&1; then
            apt-get remove -y "$pkg" || log_warn "Impossible de supprimer $pkg"
        fi
    done

    apt-get autoremove -y
    log_success "Meta-packages Ubuntu supprimés."
}

# ── Étape 6 : Configurer GRUB ─────────────────────────────────────────────────
step_configure_grub() {
    log_info "Mise à jour de GRUB pour booter sur le kernel PVE..."
    update-grub
    log_success "GRUB mis à jour."
}

# ── Étape 7 : Désactiver le firewall UFW (Proxmox gère ses propres règles) ───
step_disable_ufw() {
    if systemctl is-active ufw &>/dev/null; then
        log_warn "Désactivation d'UFW (Proxmox gère ses propres règles iptables)..."
        ufw disable || true
    fi
}

# ── Résumé final ──────────────────────────────────────────────────────────────
print_summary() {
    local ip
    if [[ "$MAIN_IP" == "AUTO" ]]; then
        ip=$(detect_main_ip)
    else
        ip="$MAIN_IP"
    fi

    # Sauvegarder les credentials
    save_credential "Proxmox Web UI" "https://${ip}:8006"
    save_credential "Proxmox Root User" "root"
    save_credential "Proxmox Root Pass" "(mot de passe root système actuel)"

    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║           PROXMOX VE - INSTALLATION TERMINÉE            ║${NC}"
    echo -e "${BOLD}╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}║${NC}  Panel Web  : ${GREEN}https://${ip}:8006${NC}"
    echo -e "${BOLD}║${NC}  Login      : ${GREEN}root${NC}"
    echo -e "${BOLD}║${NC}  Mot de passe : ${YELLOW}(votre mot de passe root actuel)${NC}"
    echo -e "${BOLD}║${NC}"
    echo -e "${BOLD}║${NC}  ${RED}⚠  UN REBOOT EST OBLIGATOIRE POUR ACTIVER LE KERNEL PVE${NC}"
    echo -e "${BOLD}╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}║${NC}  Après reboot, exécutez dans l'ordre :"
    echo -e "${BOLD}║${NC}    1. bash 05_network_config.sh"
    echo -e "${BOLD}║${NC}    2. bash 02_install_virtualizor.sh"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo -e "${BOLD}=== Installation Proxmox VE sur Ubuntu 22.04 ===${NC}"
    echo ""

    check_root
    check_ubuntu_22
    check_already_installed

    step_prerequisites
    step_configure_hosts
    step_add_proxmox_repo
    step_install_proxmox
    step_remove_ubuntu_kernel
    step_configure_grub
    step_disable_ufw

    print_summary

    read -rp "Voulez-vous redémarrer maintenant ? [o/N] " answer
    if [[ "${answer,,}" == "o" ]]; then
        log_info "Redémarrage dans 5 secondes..."
        sleep 5
        reboot
    else
        log_warn "N'oubliez pas de redémarrer manuellement avec : reboot"
    fi
}

main "$@"
