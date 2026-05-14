#!/usr/bin/env bash
# =============================================================================
# Script 5 : Configuration réseau Proxmox — vmbr0 (bridge public) + vmbr1 (NAT)
# =============================================================================
# vmbr0 : bridge sur l'interface physique, porte l'IP publique du serveur
# vmbr1 : bridge interne (10.10.10.0/24), toutes les VMs clients passent en NAT
#
# Schéma :
#   Internet → ens3 → vmbr0 (IP publique)
#                          ↓
#                     vmbr1 (10.10.10.1/24) ← VMs (10.10.10.x)
#                          ↓ MASQUERADE iptables
#                     Sortie Internet des VMs
# =============================================================================

set -euo pipefail

# ── Variables à modifier ──────────────────────────────────────────────────────
VM_SUBNET="${VM_SUBNET:-10.10.10.0/24}"
VM_GATEWAY="${VM_GATEWAY:-10.10.10.1}"
VM_NETMASK="${VM_NETMASK:-24}"
DNS_SERVER="${DNS_SERVER:-8.8.8.8}"
DNS_SERVER2="${DNS_SERVER2:-8.8.4.4}"
# =============================================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

check_root() {
    [[ $EUID -eq 0 ]] || { log_error "Root requis."; exit 1; }
}

save_credential() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $1: $2" >> /root/.vps-infra-credentials
}

# ── Détecter l'interface physique et l'IP courante ────────────────────────────
detect_network() {
    PHYS_IFACE=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $5; exit}')
    MAIN_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
    MAIN_CIDR=$(ip addr show "$PHYS_IFACE" | awk '/inet /{print $2; exit}')
    MAIN_NETMASK=$(echo "$MAIN_CIDR" | cut -d/ -f2)
    GATEWAY=$(ip route | awk '/^default/{print $3; exit}')

    if [[ -z "$PHYS_IFACE" || -z "$MAIN_IP" || -z "$GATEWAY" ]]; then
        log_error "Impossible de détecter les paramètres réseau."
        log_error "Interface: ${PHYS_IFACE:-?}, IP: ${MAIN_IP:-?}, GW: ${GATEWAY:-?}"
        exit 1
    fi

    log_info "Interface physique : ${PHYS_IFACE}"
    log_info "IP publique        : ${MAIN_IP}/${MAIN_NETMASK}"
    log_info "Passerelle         : ${GATEWAY}"
}

# ── Installer bridge-utils et iptables-persistent ────────────────────────────
step_install_deps() {
    log_info "Installation des dépendances réseau..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        bridge-utils \
        iptables \
        iptables-persistent \
        netfilter-persistent
    log_success "Dépendances installées."
}

# ── Configurer /etc/network/interfaces ───────────────────────────────────────
step_configure_interfaces() {
    local interfaces_file="/etc/network/interfaces"
    local backup_file="/etc/network/interfaces.bak.$(date +%Y%m%d%H%M%S)"

    # Sauvegarde de la configuration existante
    if [[ -f "$interfaces_file" ]]; then
        cp "$interfaces_file" "$backup_file"
        log_info "Sauvegarde : ${backup_file}"
    fi

    # Idempotence : ne pas réécrire si vmbr1 est déjà configuré
    if grep -q "^auto vmbr1" "$interfaces_file" 2>/dev/null; then
        log_warn "vmbr1 déjà configuré dans ${interfaces_file}. Ignoré."
        return 0
    fi

    log_info "Écriture de /etc/network/interfaces..."

    cat > "$interfaces_file" <<EOF
# /etc/network/interfaces — généré par 05_network_config.sh
# NE PAS MODIFIER MANUELLEMENT (relancez le script pour régénérer)

source /etc/network/interfaces.d/*

# Loopback
auto lo
iface lo inet loopback

# Interface physique — devient esclave du bridge vmbr0
auto ${PHYS_IFACE}
iface ${PHYS_IFACE} inet manual

# vmbr0 : bridge public (porte l'IP publique du serveur)
# Les VMs avec IPs additionnelles Contabo se connectent ici
auto vmbr0
iface vmbr0 inet static
    address ${MAIN_IP}/${MAIN_NETMASK}
    gateway ${GATEWAY}
    bridge-ports ${PHYS_IFACE}
    bridge-stp off
    bridge-fd 0
    bridge-maxwait 0
    dns-nameservers ${DNS_SERVER} ${DNS_SERVER2}

# vmbr1 : bridge interne NAT pour les VMs clients (10.10.10.0/24)
# Les VMs obtiennent des IPs 10.10.10.2 à 10.10.10.254
# Le serveur hôte est 10.10.10.1 (passerelle des VMs)
auto vmbr1
iface vmbr1 inet static
    address ${VM_GATEWAY}/${VM_NETMASK}
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    post-up   echo 1 > /proc/sys/net/ipv4/ip_forward
    post-up   iptables -t nat -A POSTROUTING -s ${VM_SUBNET} -o vmbr0 -j MASQUERADE
    post-up   iptables -A FORWARD -i vmbr1 -o vmbr0 -j ACCEPT
    post-up   iptables -A FORWARD -i vmbr0 -o vmbr1 -m state --state RELATED,ESTABLISHED -j ACCEPT
    post-down iptables -t nat -D POSTROUTING -s ${VM_SUBNET} -o vmbr0 -j MASQUERADE || true
    post-down iptables -D FORWARD -i vmbr1 -o vmbr0 -j ACCEPT || true
    post-down iptables -D FORWARD -i vmbr0 -o vmbr1 -m state --state RELATED,ESTABLISHED -j ACCEPT || true
EOF

    log_success "/etc/network/interfaces configuré."
}

# ── Activer le routage IP en permanence ───────────────────────────────────────
step_enable_ip_forwarding() {
    if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
        log_success "IP forwarding activé dans /etc/sysctl.conf."
    else
        log_warn "IP forwarding déjà activé."
    fi

    sysctl -w net.ipv4.ip_forward=1 > /dev/null
}

# ── Appliquer les règles iptables et les persister ────────────────────────────
step_configure_iptables() {
    log_info "Application des règles iptables NAT..."

    # Éviter les doublons avec -C (check) avant d'ajouter
    iptables -t nat -C POSTROUTING -s "${VM_SUBNET}" -o vmbr0 -j MASQUERADE 2>/dev/null || \
        iptables -t nat -A POSTROUTING -s "${VM_SUBNET}" -o vmbr0 -j MASQUERADE

    iptables -C FORWARD -i vmbr1 -o vmbr0 -j ACCEPT 2>/dev/null || \
        iptables -A FORWARD -i vmbr1 -o vmbr0 -j ACCEPT

    iptables -C FORWARD -i vmbr0 -o vmbr1 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
        iptables -A FORWARD -i vmbr0 -o vmbr1 -m state --state RELATED,ESTABLISHED -j ACCEPT

    # Ouvrir le port du panel Proxmox (8006)
    iptables -C INPUT -p tcp --dport 8006 -j ACCEPT 2>/dev/null || \
        iptables -A INPUT -p tcp --dport 8006 -j ACCEPT

    # Ouvrir les ports Virtualizor
    iptables -C INPUT -p tcp --dport 4082 -j ACCEPT 2>/dev/null || \
        iptables -A INPUT -p tcp --dport 4082 -j ACCEPT
    iptables -C INPUT -p tcp --dport 4083 -j ACCEPT 2>/dev/null || \
        iptables -A INPUT -p tcp --dport 4083 -j ACCEPT

    log_info "Persistance des règles iptables..."
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4

    # Activer netfilter-persistent au démarrage
    systemctl enable netfilter-persistent 2>/dev/null || true

    log_success "Règles iptables appliquées et persistées."
}

# ── Configurer le DNS pour les VMs ────────────────────────────────────────────
step_configure_dnsmasq_hint() {
    # On ne force pas l'install de dnsmasq ici, mais on laisse une note
    log_info "Conseil DNS : installez dnsmasq sur le serveur hôte pour fournir"
    log_info "  le DHCP/DNS aux VMs sur vmbr1 (10.10.10.0/24)."
    log_info "  Commande : apt-get install -y dnsmasq"
    log_info "  Config minimale /etc/dnsmasq.conf :"
    log_info "    interface=vmbr1"
    log_info "    dhcp-range=10.10.10.50,10.10.10.200,12h"
    log_info "    dhcp-option=3,10.10.10.1"
    log_info "    dhcp-option=6,${DNS_SERVER}"
}

# ── Vérification post-configuration ──────────────────────────────────────────
step_verify() {
    log_info "Vérification de la configuration..."

    # Essayer d'activer les bridges (peut échouer sans reboot si l'iface est active)
    if ip link show vmbr0 &>/dev/null; then
        log_success "vmbr0 déjà actif."
    else
        log_info "Activation de vmbr0..."
        ifup vmbr0 2>/dev/null || log_warn "Impossible d'activer vmbr0 sans redémarrage."
    fi

    if ip link show vmbr1 &>/dev/null; then
        log_success "vmbr1 déjà actif."
    else
        log_info "Activation de vmbr1..."
        ifup vmbr1 2>/dev/null || log_warn "Impossible d'activer vmbr1 sans redémarrage."
    fi

    # Vérifier IP forwarding
    local fwd
    fwd=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "0")
    if [[ "$fwd" == "1" ]]; then
        log_success "IP forwarding actif."
    else
        log_warn "IP forwarding non actif. Un reboot activera la règle sysctl."
    fi
}

# ── Résumé final ──────────────────────────────────────────────────────────────
print_summary() {
    save_credential "vmbr0 IP publique" "${MAIN_IP}"
    save_credential "vmbr1 Passerelle VMs" "${VM_GATEWAY}"
    save_credential "Plage IPs VMs" "10.10.10.2 - 10.10.10.254"

    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║           RÉSEAU PROXMOX - CONFIGURATION TERMINÉE       ║${NC}"
    echo -e "${BOLD}╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}║${NC}  Interface physique : ${GREEN}${PHYS_IFACE}${NC}"
    echo -e "${BOLD}║${NC}  vmbr0 (public)     : ${GREEN}${MAIN_IP}/${MAIN_NETMASK}${NC}"
    echo -e "${BOLD}║${NC}  vmbr1 (NAT interne): ${GREEN}${VM_GATEWAY}/${VM_NETMASK}${NC}"
    echo -e "${BOLD}║${NC}  Plage IPs VMs      : ${GREEN}10.10.10.2 – 10.10.10.254${NC}"
    echo -e "${BOLD}║${NC}  NAT MASQUERADE     : ${GREEN}actif${NC}"
    echo -e "${BOLD}║${NC}"
    echo -e "${BOLD}║${NC}  Vérifications :"
    echo -e "${BOLD}║${NC}    ip a                     # voir vmbr0 et vmbr1"
    echo -e "${BOLD}║${NC}    sysctl net.ipv4.ip_forward  # doit afficher 1"
    echo -e "${BOLD}║${NC}    iptables -t nat -L -n -v    # voir règle MASQUERADE"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    log_warn "Si vmbr0/vmbr1 ne sont pas actifs, redémarrez : reboot"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo -e "${BOLD}=== Configuration réseau Proxmox (vmbr0 + vmbr1 NAT) ===${NC}"
    echo ""

    check_root
    detect_network
    step_install_deps
    step_configure_interfaces
    step_enable_ip_forwarding
    step_configure_iptables
    step_configure_dnsmasq_hint
    step_verify
    print_summary
}

main "$@"
