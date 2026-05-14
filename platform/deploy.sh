#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Installation de la plateforme VPS sur Ubuntu 24.04 LTS
# =============================================================================
# Installe dans /opt/hoster :
#   - Node.js 20 LTS
#   - PM2 (process manager)
#   - Nginx (reverse proxy + serveur statique Vue.js)
#   - Certbot (SSL Let's Encrypt)
#   - Le projet cloné depuis GitHub
#   - Le service démarré automatiquement au boot
#
# Usage :
#   curl -fsSL https://raw.githubusercontent.com/sessihounnou/hoster/main/platform/deploy.sh | bash
# ou :
#   bash deploy.sh
# =============================================================================

set -euo pipefail

# ── Variables à modifier ──────────────────────────────────────────────────────
DOMAIN="${DOMAIN:-billing.mondomaine.com}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@mondomaine.com}"
REPO_URL="${REPO_URL:-https://github.com/sessihounnou/hoster.git}"
APP_DIR="/opt/hoster"
APP_PORT="3000"
# =============================================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

check_root() {
    [[ $EUID -eq 0 ]] || { log_error "Ce script doit être exécuté en root. Utilisez : sudo bash deploy.sh"; exit 1; }
}

# ── Demander les variables si non définies ────────────────────────────────────
prompt_variables() {
    if [[ "$DOMAIN" == "billing.mondomaine.com" ]]; then
        read -rp "Votre domaine (ex: billing.monsite.com) : " DOMAIN
        [[ -z "$DOMAIN" ]] && { log_error "Domaine requis."; exit 1; }
    fi
    if [[ "$ADMIN_EMAIL" == "admin@mondomaine.com" ]]; then
        read -rp "Email admin (pour SSL + compte admin) : " ADMIN_EMAIL
        [[ -z "$ADMIN_EMAIL" ]] && { log_error "Email requis."; exit 1; }
    fi

    # Générer des secrets aléatoires
    JWT_SECRET=$(openssl rand -hex 32)
    ENCRYPTION_KEY=$(openssl rand -hex 32)
    ADMIN_PASSWORD=$(openssl rand -base64 12 | tr -dc 'A-Za-z0-9' | head -c 14)

    log_info "Domaine       : ${DOMAIN}"
    log_info "Email admin   : ${ADMIN_EMAIL}"
    log_info "Répertoire    : ${APP_DIR}"
}

# ── Étape 1 : Mise à jour système ─────────────────────────────────────────────
step_system_update() {
    log_info "Mise à jour du système..."
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
    apt-get install -y -qq curl wget git unzip openssl ufw
    log_success "Système à jour."
}

# ── Étape 2 : Node.js 20 LTS ──────────────────────────────────────────────────
step_install_nodejs() {
    if command -v node &>/dev/null && [[ "$(node -e 'process.exit(parseInt(process.version.slice(1)) < 20 ? 1 : 0)' 2>/dev/null; echo $?)" == "0" ]]; then
        log_warn "Node.js $(node -v) déjà installé."
        return 0
    fi

    log_info "Installation de Node.js 20 LTS..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1
    apt-get install -y -qq nodejs
    log_success "Node.js $(node -v) installé."
}

# ── Étape 3 : PM2 ─────────────────────────────────────────────────────────────
step_install_pm2() {
    if command -v pm2 &>/dev/null; then
        log_warn "PM2 déjà installé."
        return 0
    fi
    log_info "Installation de PM2..."
    npm install -g pm2 --silent
    log_success "PM2 installé."
}

# ── Étape 4 : Nginx ───────────────────────────────────────────────────────────
step_install_nginx() {
    if command -v nginx &>/dev/null; then
        log_warn "Nginx déjà installé."
        return 0
    fi
    log_info "Installation de Nginx..."
    apt-get install -y -qq nginx
    systemctl enable nginx --now
    log_success "Nginx installé."
}

# ── Étape 5 : Certbot ─────────────────────────────────────────────────────────
step_install_certbot() {
    if command -v certbot &>/dev/null; then
        log_warn "Certbot déjà installé."
        return 0
    fi
    log_info "Installation de Certbot..."
    apt-get install -y -qq certbot python3-certbot-nginx
    log_success "Certbot installé."
}

# ── Étape 6 : Cloner / mettre à jour le projet ───────────────────────────────
step_clone_project() {
    if [[ -d "${APP_DIR}/.git" ]]; then
        log_info "Mise à jour du dépôt existant..."
        git -C "${APP_DIR}" pull origin main
        log_success "Projet mis à jour."
    else
        log_info "Clonage du projet dans ${APP_DIR}..."
        git clone "${REPO_URL}" "${APP_DIR}"
        log_success "Projet cloné."
    fi
}

# ── Étape 7 : Créer le fichier .env ──────────────────────────────────────────
step_create_env() {
    local env_file="${APP_DIR}/platform/server/.env"

    if [[ -f "$env_file" ]]; then
        log_warn ".env déjà présent — non écrasé. Editez ${env_file} si nécessaire."
        return 0
    fi

    log_info "Création du fichier .env..."
    cat > "$env_file" <<EOF
# Généré automatiquement par deploy.sh le $(date '+%Y-%m-%d %H:%M:%S')

PORT=${APP_PORT}
NODE_ENV=production
JWT_SECRET=${JWT_SECRET}
APP_URL=https://${DOMAIN}
FRONTEND_URL=https://${DOMAIN}

# FedaPay — remplacez par vos vraies clés sur https://fedapay.com
FEDAPAY_SECRET_KEY=sk_sandbox_xxxx
FEDAPAY_ENV=sandbox

# Virtualizor — remplir après installation Virtualizor
VIRTUALIZOR_IP=127.0.0.1
VIRTUALIZOR_API_KEY=
VIRTUALIZOR_API_PASS=

# SMTP — configurez votre service email
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_SECURE=false
SMTP_USER=${ADMIN_EMAIL}
SMTP_PASS=
SMTP_FROM="MonVPS <${ADMIN_EMAIL}>"

# Compte admin créé au premier démarrage
ADMIN_EMAIL=${ADMIN_EMAIL}
ADMIN_PASSWORD=${ADMIN_PASSWORD}

# Chiffrement mots de passe VPS en DB
ENCRYPTION_KEY=${ENCRYPTION_KEY}
EOF

    chmod 600 "$env_file"
    log_success ".env créé dans ${env_file}"

    # Sauvegarder les credentials générés
    mkdir -p /root
    cat >> /root/.hoster-credentials <<EOF
$(date '+%Y-%m-%d %H:%M:%S')
  URL           : https://${DOMAIN}
  Admin email   : ${ADMIN_EMAIL}
  Admin pass    : ${ADMIN_PASSWORD}
  JWT Secret    : ${JWT_SECRET}
  Encrypt Key   : ${ENCRYPTION_KEY}
  Fichier .env  : ${env_file}
EOF
    chmod 600 /root/.hoster-credentials
}

# ── Étape 8 : Installer les dépendances Node ──────────────────────────────────
step_install_deps() {
    log_info "Installation des dépendances backend..."
    cd "${APP_DIR}/platform/server" && npm install --omit=dev --silent
    log_success "Dépendances backend installées."

    log_info "Installation des dépendances frontend..."
    cd "${APP_DIR}/platform/client" && npm install --silent
    log_success "Dépendances frontend installées."
}

# ── Étape 9 : Build Vue.js ────────────────────────────────────────────────────
step_build_frontend() {
    log_info "Build du frontend Vue.js..."
    cd "${APP_DIR}/platform/client"

    # Injecter l'URL de l'API dans le build
    VITE_API_URL="https://${DOMAIN}" npx vite build --silent

    log_success "Frontend compilé dans ${APP_DIR}/platform/client/dist/"
}

# ── Étape 10 : Configurer Nginx ───────────────────────────────────────────────
step_configure_nginx() {
    local vhost="/etc/nginx/sites-available/hoster"

    log_info "Configuration du vhost Nginx pour ${DOMAIN}..."

    cat > "$vhost" <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    # Fichiers statiques Vue.js
    root ${APP_DIR}/platform/client/dist;
    index index.html;

    # SPA routing — toutes les routes renvoient index.html sauf /api
    location / {
        try_files \$uri \$uri/ /index.html;
    }

    # Proxy vers l'API Express.js
    location /api/ {
        proxy_pass         http://127.0.0.1:${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_read_timeout 60s;
    }

    # Sécurité
    add_header X-Frame-Options       "SAMEORIGIN"  always;
    add_header X-Content-Type-Options "nosniff"    always;
    add_header Referrer-Policy       "no-referrer" always;

    client_max_body_size 10M;
}
NGINX

    ln -sf "$vhost" /etc/nginx/sites-enabled/hoster
    rm -f /etc/nginx/sites-enabled/default

    nginx -t && systemctl reload nginx
    log_success "Nginx configuré pour ${DOMAIN}."
}

# ── Étape 11 : SSL Let's Encrypt ──────────────────────────────────────────────
step_obtain_ssl() {
    local cert_dir="/etc/letsencrypt/live/${DOMAIN}"

    if [[ -d "$cert_dir" ]]; then
        log_warn "Certificat SSL déjà présent pour ${DOMAIN}."
        return 0
    fi

    log_info "Obtention du certificat SSL pour ${DOMAIN}..."

    certbot --nginx \
        -d "${DOMAIN}" \
        --non-interactive \
        --agree-tos \
        -m "${ADMIN_EMAIL}" \
        --redirect

    # Renouvellement auto
    systemctl enable certbot.timer 2>/dev/null || \
        (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet && systemctl reload nginx") | crontab -

    log_success "SSL configuré. Renouvellement automatique activé."
}

# ── Étape 12 : Démarrer avec PM2 ─────────────────────────────────────────────
step_start_pm2() {
    log_info "Démarrage de l'API Express avec PM2..."

    cd "${APP_DIR}/platform/server"

    # Arrêter l'ancienne instance si elle tourne
    pm2 delete hoster-api 2>/dev/null || true

    pm2 start index.js \
        --name "hoster-api" \
        --env production \
        --max-memory-restart 300M \
        --restart-delay 3000

    # Sauvegarder et activer au démarrage
    pm2 save
    pm2 startup | tail -1 | bash 2>/dev/null || \
        env PATH=$PATH:/usr/bin pm2 startup systemd -u root --hp /root

    pm2 save
    log_success "API démarrée et configurée pour redémarrer au boot."
}

# ── Étape 13 : Configurer UFW ────────────────────────────────────────────────
step_configure_firewall() {
    log_info "Configuration du pare-feu UFW..."
    ufw allow OpenSSH    > /dev/null
    ufw allow 'Nginx Full' > /dev/null
    ufw --force enable   > /dev/null
    log_success "Pare-feu activé (SSH + HTTP/HTTPS autorisés)."
}

# ── Résumé final ──────────────────────────────────────────────────────────────
print_summary() {
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║         PLATEFORME HOSTER — DÉPLOIEMENT TERMINÉ             ║${NC}"
    echo -e "${BOLD}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}║${NC}  URL             : ${GREEN}https://${DOMAIN}${NC}"
    echo -e "${BOLD}║${NC}  Admin           : ${GREEN}https://${DOMAIN}/admin${NC}"
    echo -e "${BOLD}║${NC}  Email admin     : ${GREEN}${ADMIN_EMAIL}${NC}"
    echo -e "${BOLD}║${NC}  Mot de passe    : ${YELLOW}${ADMIN_PASSWORD}${NC}"
    echo -e "${BOLD}║${NC}"
    echo -e "${BOLD}║${NC}  Répertoire app  : ${GREEN}${APP_DIR}${NC}"
    echo -e "${BOLD}║${NC}  Fichier .env    : ${GREEN}${APP_DIR}/platform/server/.env${NC}"
    echo -e "${BOLD}║${NC}  Logs PM2        : ${GREEN}pm2 logs hoster-api${NC}"
    echo -e "${BOLD}║${NC}  Statut PM2      : ${GREEN}pm2 status${NC}"
    echo -e "${BOLD}║${NC}"
    echo -e "${BOLD}║${NC}  ${YELLOW}À faire après déploiement :${NC}"
    echo -e "${BOLD}║${NC}    1. Editez ${APP_DIR}/platform/server/.env"
    echo -e "${BOLD}║${NC}       → Ajoutez vos clés FedaPay (sk_live_...)"
    echo -e "${BOLD}║${NC}       → Ajoutez votre config SMTP"
    echo -e "${BOLD}║${NC}       → Ajoutez les clés API Virtualizor"
    echo -e "${BOLD}║${NC}    2. Relancez : pm2 restart hoster-api"
    echo -e "${BOLD}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}║${NC}  Credentials sauvegardés dans : ${YELLOW}/root/.hoster-credentials${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo -e "${BOLD}=== Déploiement Plateforme Hoster sur Ubuntu 24.04 ===${NC}"
    echo ""

    check_root
    prompt_variables

    step_system_update
    step_install_nodejs
    step_install_pm2
    step_install_nginx
    step_install_certbot
    step_clone_project
    step_create_env
    step_install_deps
    step_build_frontend
    step_configure_nginx
    step_obtain_ssl
    step_start_pm2
    step_configure_firewall

    print_summary
}

main "$@"
