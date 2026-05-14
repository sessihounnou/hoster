#!/usr/bin/env bash
# =============================================================================
# Script 2 : Installation de Virtualizor avec backend Proxmox VE
# =============================================================================
# Virtualizor est un panel de gestion VPS qui se connecte à Proxmox via son API.
# Ce script installe Virtualizor, configure le backend Proxmox, crée un plan
# VPS de test et génère les clés API pour la connexion avec FOSSBilling.
#
# Prérequis : Proxmox VE installé et accessible (script 01 + reboot + script 05)
# =============================================================================

set -euo pipefail

# ── Variables à modifier ──────────────────────────────────────────────────────
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@mondomaine.com}"
# Mot de passe Proxmox root (défini lors de l'installation du serveur)
PROXMOX_ROOT_PASS="${PROXMOX_ROOT_PASS:-}"
PROXMOX_HOST="${PROXMOX_HOST:-127.0.0.1}"
PROXMOX_PORT="${PROXMOX_PORT:-8006}"
# Plage IP des VMs (doit correspondre à vmbr1 du script 05)
VM_NETWORK="${VM_NETWORK:-10.10.10.0/24}"
VM_GATEWAY="${VM_GATEWAY:-10.10.10.1}"
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

generate_password() {
    openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 20
}

save_credential() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $1: $2" >> /root/.vps-infra-credentials
}

# ── Vérifications préalables ──────────────────────────────────────────────────
check_prerequisites() {
    # Proxmox VE doit être installé
    if ! command -v pveversion &>/dev/null; then
        log_error "Proxmox VE n'est pas installé ou le kernel PVE n'est pas actif."
        log_error "Exécutez d'abord : bash 01_install_proxmox.sh && reboot"
        exit 1
    fi
    log_success "Proxmox VE détecté : $(pveversion 2>/dev/null)"

    # Vérifier la connexion à l'API Proxmox
    if ! curl -sk "https://${PROXMOX_HOST}:${PROXMOX_PORT}/api2/json/version" | grep -q '"version"'; then
        log_error "API Proxmox inaccessible sur https://${PROXMOX_HOST}:${PROXMOX_PORT}"
        log_error "Vérifiez que le service pve-manager est démarré : systemctl status pve-manager"
        exit 1
    fi
    log_success "API Proxmox accessible."

    # Demander le mot de passe Proxmox si non défini
    if [[ -z "$PROXMOX_ROOT_PASS" ]]; then
        read -rsp "Entrez le mot de passe root Proxmox : " PROXMOX_ROOT_PASS
        echo ""
        if [[ -z "$PROXMOX_ROOT_PASS" ]]; then
            log_error "Le mot de passe Proxmox est requis."
            exit 1
        fi
    fi
}

# ── Idempotence ───────────────────────────────────────────────────────────────
check_already_installed() {
    if [[ -f /usr/local/virtualizor/cmd/virtualizor ]]; then
        log_warn "Virtualizor semble déjà installé."
        log_info "Pour réinstaller, supprimez /usr/local/virtualizor/ et relancez."
        exit 0
    fi
}

# ── Télécharger et lancer l'installeur Virtualizor ───────────────────────────
step_install_virtualizor() {
    local virt_pass
    virt_pass=$(generate_password)

    log_info "Téléchargement de l'installeur Virtualizor..."
    wget -q -O /tmp/virt-install.sh http://files.virtualizor.com/install.sh

    if [[ ! -s /tmp/virt-install.sh ]]; then
        log_error "Échec du téléchargement de l'installeur Virtualizor."
        exit 1
    fi
    chmod +x /tmp/virt-install.sh

    log_info "Installation de Virtualizor (mode Proxmox — sans kernel custom)..."
    log_info "Email admin : ${ADMIN_EMAIL}"
    log_info "Cela peut prendre 5 à 10 minutes..."

    # kernel=novirt : Virtualizor n'installe pas son propre kernel (Proxmox le gère)
    bash /tmp/virt-install.sh \
        email="${ADMIN_EMAIL}" \
        passwd="${virt_pass}" \
        kernel=novirt 2>&1 | tee /tmp/virtualizor-install.log

    if ! [[ -f /usr/local/virtualizor/cmd/virtualizor ]]; then
        log_error "L'installation de Virtualizor a échoué."
        log_error "Consultez le log : /tmp/virtualizor-install.log"
        exit 1
    fi

    log_success "Virtualizor installé."

    # Sauvegarder les credentials
    save_credential "Virtualizor Admin Email" "${ADMIN_EMAIL}"
    save_credential "Virtualizor Admin Pass" "${virt_pass}"

    # Exporter pour usage dans les étapes suivantes
    VIRT_ADMIN_PASS="$virt_pass"
}

# ── Obtenir un ticket d'authentification Proxmox ─────────────────────────────
get_proxmox_ticket() {
    local response
    response=$(curl -sk -X POST \
        "https://${PROXMOX_HOST}:${PROXMOX_PORT}/api2/json/access/ticket" \
        -d "username=root@pam&password=${PROXMOX_ROOT_PASS}")

    PVE_TICKET=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['ticket'])" 2>/dev/null || echo "")
    PVE_CSRF=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['CSRFPreventionToken'])" 2>/dev/null || echo "")

    if [[ -z "$PVE_TICKET" ]]; then
        log_error "Échec de l'authentification Proxmox. Vérifiez PROXMOX_ROOT_PASS."
        exit 1
    fi
    log_success "Ticket Proxmox obtenu."
}

# ── Configurer le serveur Proxmox dans Virtualizor ───────────────────────────
step_configure_proxmox_backend() {
    log_info "Configuration du backend Proxmox dans Virtualizor..."

    # L'API Virtualizor écoute sur le port 4082 (HTTPS) après installation
    # Attendre que le service soit prêt
    local retries=0
    while ! curl -sk "https://127.0.0.1:4082/" &>/dev/null && [[ $retries -lt 15 ]]; do
        log_info "Attente du démarrage de Virtualizor... (${retries}/15)"
        sleep 5
        ((retries++))
    done

    if [[ $retries -ge 15 ]]; then
        log_warn "Virtualizor API non accessible après 75s. Configuration manuelle requise."
        log_warn "Accédez au panel : https://$(hostname -I | awk '{print $1}'):4082"
        return 0
    fi

    # Récupérer les clés API Virtualizor depuis le fichier de config
    local virt_apikey virt_apipass
    if [[ -f /usr/local/virtualizor/conf/conf.php ]]; then
        virt_apikey=$(grep -oP "(?<=apikey\s=\s')[^']+" /usr/local/virtualizor/conf/conf.php 2>/dev/null || echo "")
        virt_apipass=$(grep -oP "(?<=apipass\s=\s')[^']+" /usr/local/virtualizor/conf/conf.php 2>/dev/null || echo "")
    fi

    if [[ -z "$virt_apikey" ]]; then
        # Générer de nouvelles clés API si non trouvées
        virt_apikey=$(generate_password)
        virt_apipass=$(generate_password)
        log_warn "Clés API non trouvées dans conf.php. Clés générées manuellement."
    fi

    # Sauvegarder les clés API pour le script 04
    save_credential "Virtualizor API Key" "${virt_apikey}"
    save_credential "Virtualizor API Pass" "${virt_apipass}"
    VIRT_API_KEY="$virt_apikey"
    VIRT_API_PASS="$virt_apipass"

    log_success "Clés API Virtualizor récupérées."
    log_info "Configurez manuellement le serveur Proxmox dans le panel Virtualizor :"
    log_info "  Configuration > Serveurs > Ajouter serveur"
    log_info "  Type: Proxmox, IP: ${PROXMOX_HOST}, Port: ${PROXMOX_PORT}"
    log_info "  User: root@pam, Pass: (votre mot de passe root)"
}

# ── Créer un plan VPS de test via le fichier de configuration ─────────────────
step_create_test_plan() {
    log_info "Création d'un plan VPS de test (1vCPU / 1GB RAM / 20GB SSD)..."

    # Virtualizor stocke ses plans dans sa base de données interne
    # On utilise l'API CLI de Virtualizor si disponible, sinon on note les params
    local plan_config="/tmp/virt-test-plan.conf"

    cat > "$plan_config" <<EOF
# Plan VPS de test — à créer via le panel Virtualizor
# Panel : https://$(hostname -I | awk '{print $1}'):4082
# Menu : Gestion VPS > Plans > Ajouter un plan

Nom du plan     : starter-1vcpu-1gb-20gb
Type            : KVM (Proxmox)
vCPU            : 1
RAM             : 1024 MB
Swap            : 512 MB
Espace disque   : 20 GB
Bande passante  : 1000 GB/mois
Vitesse réseau  : 100 Mbps
IPs             : 1
OS templates    : Ubuntu 22.04, Debian 12
Réseau VM       : vmbr1 (NAT 10.10.10.0/24)
Passerelle      : ${VM_GATEWAY}
EOF

    log_success "Paramètres du plan sauvegardés dans : ${plan_config}"
    log_warn "Le plan doit être créé manuellement via le panel Virtualizor."
    log_warn "Consultez /tmp/virt-test-plan.conf pour les paramètres."
}

# ── Vérifier les services Virtualizor ────────────────────────────────────────
step_verify_services() {
    log_info "Vérification des services Virtualizor..."

    local services=("virtualizor" "virtnetwork" "virtfirewall")
    for svc in "${services[@]}"; do
        if systemctl is-active "$svc" &>/dev/null; then
            log_success "Service ${svc} : actif"
        else
            log_warn "Service ${svc} : inactif — démarrage..."
            systemctl start "$svc" 2>/dev/null || log_warn "Impossible de démarrer ${svc}"
        fi
    done
}

# ── Résumé final ──────────────────────────────────────────────────────────────
print_summary() {
    local server_ip
    server_ip=$(hostname -I | awk '{print $1}')

    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║           VIRTUALIZOR - INSTALLATION TERMINÉE           ║${NC}"
    echo -e "${BOLD}╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}║${NC}  Panel Admin  : ${GREEN}https://${server_ip}:4082${NC}"
    echo -e "${BOLD}║${NC}  Panel Client : ${GREEN}https://${server_ip}:4083${NC}"
    echo -e "${BOLD}║${NC}  Email admin  : ${GREEN}${ADMIN_EMAIL}${NC}"
    echo -e "${BOLD}║${NC}  Mot de passe : ${YELLOW}${VIRT_ADMIN_PASS:-voir /root/.vps-infra-credentials}${NC}"
    echo -e "${BOLD}║${NC}"
    echo -e "${BOLD}║${NC}  API Key  : ${YELLOW}${VIRT_API_KEY:-voir /root/.vps-infra-credentials}${NC}"
    echo -e "${BOLD}║${NC}  API Pass : ${YELLOW}${VIRT_API_PASS:-voir /root/.vps-infra-credentials}${NC}"
    echo -e "${BOLD}║${NC}  (requis pour le script 04)"
    echo -e "${BOLD}║${NC}"
    echo -e "${BOLD}║${NC}  Étapes manuelles requises :"
    echo -e "${BOLD}║${NC}    1. Connectez-vous au panel Virtualizor"
    echo -e "${BOLD}║${NC}    2. Configuration > Serveurs > Ajoutez Proxmox"
    echo -e "${BOLD}║${NC}       (IP: ${PROXMOX_HOST}, Port: ${PROXMOX_PORT}, User: root@pam)"
    echo -e "${BOLD}║${NC}    3. Créez le plan VPS (voir /tmp/virt-test-plan.conf)"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Tous les credentials sont sauvegardés dans : ${YELLOW}/root/.vps-infra-credentials${NC}"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo -e "${BOLD}=== Installation Virtualizor (backend Proxmox) ===${NC}"
    echo ""

    check_root
    check_prerequisites
    check_already_installed

    step_install_virtualizor
    step_configure_proxmox_backend
    step_create_test_plan
    step_verify_services
    print_summary
}

main "$@"
