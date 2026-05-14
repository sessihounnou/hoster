#!/usr/bin/env bash
# =============================================================================
# Script 3 : Installation de FOSSBilling avec Nginx + PHP 8.2 + MariaDB + SSL
# =============================================================================
# FOSSBilling est la plateforme de facturation open-source qui permettra à vos
# clients de commander, payer et gérer leurs VPS.
#
# Ce script installe :
#   - Nginx (serveur web)
#   - PHP 8.2-FPM + extensions requises par FOSSBilling
#   - MariaDB (base de données)
#   - Certbot + plugin Nginx (SSL Let's Encrypt)
#   - FOSSBilling (dernière version GitHub)
#
# Prérequis :
#   - Le domaine DNS doit déjà pointer sur l'IP du serveur (A record)
#   - Ports 80 et 443 ouverts et accessibles depuis Internet
# =============================================================================

set -euo pipefail

# ── Variables à modifier AVANT d'exécuter ────────────────────────────────────
DOMAIN="${DOMAIN:-billing.mondomaine.com}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@mondomaine.com}"
COMPANY_NAME="${COMPANY_NAME:-Mon Hébergeur VPS}"
CURRENCY="${CURRENCY:-EUR}"
WEBROOT="/var/www/fossbilling"
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
    if [[ "$DOMAIN" == "billing.mondomaine.com" ]]; then
        log_error "Vous devez configurer la variable DOMAIN dans ce script."
        log_error "Exemple : DOMAIN=billing.votredomaine.com bash 03_install_fossbilling.sh"
        exit 1
    fi

    # Vérifier que le domaine pointe sur ce serveur
    local server_ip
    server_ip=$(hostname -I | awk '{print $1}')
    local dns_ip
    dns_ip=$(dig +short "$DOMAIN" A 2>/dev/null | tail -1 || true)

    if [[ -z "$dns_ip" ]]; then
        log_warn "Impossible de résoudre ${DOMAIN}. Vérifiez vos DNS."
        log_warn "Let's Encrypt nécessite que le domaine pointe sur ce serveur."
        read -rp "Continuer quand même ? [o/N] " ans
        [[ "${ans,,}" == "o" ]] || exit 1
    elif [[ "$dns_ip" != "$server_ip" ]]; then
        log_warn "Le domaine ${DOMAIN} pointe sur ${dns_ip}, mais ce serveur est ${server_ip}."
        read -rp "Continuer quand même (SSL échouera si DNS incorrect) ? [o/N] " ans
        [[ "${ans,,}" == "o" ]] || exit 1
    else
        log_success "DNS OK : ${DOMAIN} → ${server_ip}"
    fi
}

# ── Étape 1 : Installer les dépôts et paquets ─────────────────────────────────
step_install_packages() {
    log_info "Ajout du dépôt PHP 8.2 (ondrej/php)..."

    # Ajouter le dépôt PHP si PHP 8.2 n'est pas disponible nativement
    if ! apt-cache show php8.2-fpm &>/dev/null 2>&1; then
        apt-get install -y -qq software-properties-common
        add-apt-repository -y ppa:ondrej/php
    fi

    log_info "Installation de Nginx, PHP 8.2, MariaDB, Certbot..."
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        nginx \
        php8.2-fpm \
        php8.2-cli \
        php8.2-mysql \
        php8.2-curl \
        php8.2-gd \
        php8.2-mbstring \
        php8.2-xml \
        php8.2-zip \
        php8.2-intl \
        php8.2-bcmath \
        php8.2-soap \
        php8.2-pdo \
        mariadb-server \
        mariadb-client \
        certbot \
        python3-certbot-nginx \
        unzip \
        curl \
        wget \
        dnsutils

    log_success "Paquets installés."
}

# ── Étape 2 : Configurer MariaDB ──────────────────────────────────────────────
step_configure_mariadb() {
    local db_name="fossbilling"
    local db_user="fossuser"
    local db_pass
    db_pass=$(generate_password)

    log_info "Configuration de MariaDB..."
    systemctl enable mariadb --now

    # Idempotence : vérifier si la base existe déjà
    if mysql -e "USE ${db_name};" &>/dev/null 2>&1; then
        log_warn "La base de données '${db_name}' existe déjà. Ignoré."
        # Lire le mot de passe existant depuis les credentials
        DB_PASS=$(grep "FOSSBilling DB Pass" /root/.vps-infra-credentials 2>/dev/null | tail -1 | awk -F': ' '{print $2}' || echo "$db_pass")
        DB_NAME="$db_name"
        DB_USER="$db_user"
        return 0
    fi

    # Sécuriser MariaDB et créer la base
    mysql -e "
        -- Sécuriser l'installation
        DELETE FROM mysql.user WHERE User='';
        DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
        DROP DATABASE IF EXISTS test;
        DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';

        -- Créer la base et l'utilisateur FOSSBilling
        CREATE DATABASE IF NOT EXISTS \`${db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
        CREATE USER IF NOT EXISTS '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';
        GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'localhost';
        FLUSH PRIVILEGES;
    "

    log_success "Base de données '${db_name}' créée avec l'utilisateur '${db_user}'."
    save_credential "FOSSBilling DB Name" "${db_name}"
    save_credential "FOSSBilling DB User" "${db_user}"
    save_credential "FOSSBilling DB Pass" "${db_pass}"

    DB_NAME="$db_name"
    DB_USER="$db_user"
    DB_PASS="$db_pass"
}

# ── Étape 3 : Télécharger et installer FOSSBilling ───────────────────────────
step_install_fossbilling() {
    if [[ -f "${WEBROOT}/index.php" ]]; then
        log_warn "FOSSBilling semble déjà installé dans ${WEBROOT}. Ignoré."
        return 0
    fi

    log_info "Téléchargement de la dernière version de FOSSBilling..."

    local release_url
    release_url=$(curl -s https://api.github.com/repos/FOSSBilling/FOSSBilling/releases/latest \
        | python3 -c "import sys,json; assets=json.load(sys.stdin)['assets']; \
          url=[a['browser_download_url'] for a in assets if a['name'].endswith('.zip')]; \
          print(url[0] if url else '')" 2>/dev/null || echo "")

    if [[ -z "$release_url" ]]; then
        log_error "Impossible de récupérer l'URL de la dernière release FOSSBilling."
        log_error "Vérifiez votre connexion Internet et relancez le script."
        exit 1
    fi

    log_info "URL : ${release_url}"
    wget -q --show-progress -O /tmp/fossbilling.zip "$release_url"

    log_info "Extraction dans ${WEBROOT}..."
    mkdir -p "${WEBROOT}"
    unzip -q /tmp/fossbilling.zip -d "${WEBROOT}"
    rm -f /tmp/fossbilling.zip

    # Certaines archives extraient dans un sous-dossier
    if [[ -d "${WEBROOT}/FOSSBilling" ]]; then
        mv "${WEBROOT}/FOSSBilling"/* "${WEBROOT}/"
        rmdir "${WEBROOT}/FOSSBilling"
    fi

    # Configurer les permissions
    chown -R www-data:www-data "${WEBROOT}"
    chmod -R 755 "${WEBROOT}"
    chmod -R 775 "${WEBROOT}/data" 2>/dev/null || mkdir -p "${WEBROOT}/data" && chmod 775 "${WEBROOT}/data"

    log_success "FOSSBilling extrait dans ${WEBROOT}."
}

# ── Étape 4 : Créer le fichier de configuration FOSSBilling ──────────────────
step_configure_fossbilling() {
    local config_file="${WEBROOT}/config.php"

    if [[ -f "$config_file" ]]; then
        log_warn "config.php existe déjà. Ignoré."
        return 0
    fi

    log_info "Création du fichier config.php FOSSBilling..."

    cat > "$config_file" <<EOF
<?php
// FOSSBilling configuration — généré par 03_install_fossbilling.sh
return [
    'url'                    => 'https://${DOMAIN}/',
    'admin_area_prefix'      => 'admin',
    'log_stacktrace'         => false,
    'stacktrace_length'      => 25,
    'debug'                  => false,
    'db' => [
        'type'     => 'mysql',
        'host'     => '127.0.0.1',
        'port'     => '3306',
        'name'     => '${DB_NAME}',
        'user'     => '${DB_USER}',
        'password' => '${DB_PASS}',
    ],
    'i18n' => [
        'locale'   => 'fr_FR',
        'timezone' => 'Europe/Paris',
        'date_format' => 'medium',
        'time_format' => 'medium',
    ],
    'twig' => [
        'debug'            => false,
        'auto_reload'      => true,
        'cache'            => false,
    ],
];
EOF

    chown www-data:www-data "$config_file"
    chmod 640 "$config_file"
    log_success "config.php créé."
}

# ── Étape 5 : Configurer Nginx (HTTP d'abord pour Certbot) ───────────────────
step_configure_nginx_http() {
    local vhost_file="/etc/nginx/sites-available/fossbilling"

    if [[ -f "$vhost_file" ]]; then
        log_warn "Vhost Nginx FOSSBilling déjà configuré."
        return 0
    fi

    log_info "Configuration du vhost Nginx (HTTP)..."

    cat > "$vhost_file" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    root ${WEBROOT};
    index index.php index.html;

    # Logs
    access_log /var/log/nginx/fossbilling-access.log;
    error_log  /var/log/nginx/fossbilling-error.log;

    # FOSSBilling : toutes les requêtes passent par index.php
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    # Traitement PHP
    location ~ \.php$ {
        fastcgi_pass   unix:/run/php/php8.2-fpm.sock;
        fastcgi_index  index.php;
        fastcgi_param  SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include        fastcgi_params;
        fastcgi_read_timeout 300;
    }

    # Protéger les fichiers sensibles
    location ~ /\. {
        deny all;
    }

    location ~* \.(env|log|conf|bak|sql)$ {
        deny all;
    }

    # Taille max upload
    client_max_body_size 50M;
}
EOF

    ln -sf "$vhost_file" /etc/nginx/sites-enabled/fossbilling
    rm -f /etc/nginx/sites-enabled/default

    nginx -t && systemctl reload nginx
    log_success "Vhost Nginx HTTP configuré."
}

# ── Étape 6 : Obtenir le certificat SSL Let's Encrypt ────────────────────────
step_obtain_ssl() {
    local cert_dir="/etc/letsencrypt/live/${DOMAIN}"

    if [[ -d "$cert_dir" ]]; then
        log_warn "Certificat SSL déjà présent pour ${DOMAIN}. Ignoré."
        return 0
    fi

    log_info "Obtention du certificat SSL Let's Encrypt pour ${DOMAIN}..."

    certbot --nginx \
        -d "${DOMAIN}" \
        --non-interactive \
        --agree-tos \
        -m "${ADMIN_EMAIL}" \
        --redirect

    log_success "Certificat SSL obtenu et Nginx reconfiguré avec HTTPS."

    # Configurer le renouvellement automatique
    systemctl enable certbot.timer 2>/dev/null || \
        (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet") | crontab -
    log_success "Renouvellement automatique SSL configuré."
}

# ── Étape 7 : Optimiser PHP 8.2 pour FOSSBilling ─────────────────────────────
step_configure_php() {
    local php_ini="/etc/php/8.2/fpm/php.ini"

    log_info "Optimisation de PHP 8.2..."

    # Paramètres recommandés pour FOSSBilling
    declare -A php_settings=(
        ["memory_limit"]="256M"
        ["max_execution_time"]="300"
        ["upload_max_filesize"]="50M"
        ["post_max_size"]="50M"
        ["max_input_vars"]="5000"
        ["date.timezone"]="Europe/Paris"
    )

    for key in "${!php_settings[@]}"; do
        local value="${php_settings[$key]}"
        if grep -q "^;*${key}" "$php_ini" 2>/dev/null; then
            sed -i "s|^;*${key}\s*=.*|${key} = ${value}|" "$php_ini"
        else
            echo "${key} = ${value}" >> "$php_ini"
        fi
    done

    systemctl restart php8.2-fpm
    log_success "PHP 8.2 optimisé."
}

# ── Étape 8 : Configurer le cron FOSSBilling ─────────────────────────────────
step_configure_cron() {
    local cron_cmd="* * * * * php ${WEBROOT}/cron.php > /dev/null 2>&1"

    if crontab -l 2>/dev/null | grep -q "fossbilling\|cron.php"; then
        log_warn "Cron FOSSBilling déjà configuré."
    else
        (crontab -l 2>/dev/null; echo "$cron_cmd") | crontab -
        log_success "Cron FOSSBilling configuré (toutes les minutes)."
    fi
}

# ── Résumé final ──────────────────────────────────────────────────────────────
print_summary() {
    save_credential "FOSSBilling URL" "https://${DOMAIN}"
    save_credential "FOSSBilling Admin URL" "https://${DOMAIN}/admin"
    save_credential "FOSSBilling Admin Email" "${ADMIN_EMAIL}"

    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║           FOSSBILLING - INSTALLATION TERMINÉE           ║${NC}"
    echo -e "${BOLD}╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}║${NC}  URL Panel Client : ${GREEN}https://${DOMAIN}${NC}"
    echo -e "${BOLD}║${NC}  URL Admin        : ${GREEN}https://${DOMAIN}/admin${NC}"
    echo -e "${BOLD}║${NC}  Email admin      : ${GREEN}${ADMIN_EMAIL}${NC}"
    echo -e "${BOLD}║${NC}"
    echo -e "${BOLD}║${NC}  Base de données  : ${GREEN}${DB_NAME}${NC}"
    echo -e "${BOLD}║${NC}  DB User          : ${GREEN}${DB_USER}${NC}"
    echo -e "${BOLD}║${NC}  DB Pass          : ${YELLOW}${DB_PASS}${NC}"
    echo -e "${BOLD}║${NC}"
    echo -e "${BOLD}║${NC}  ${YELLOW}⚠  ÉTAPE MANUELLE REQUISE :${NC}"
    echo -e "${BOLD}║${NC}  Ouvrez https://${DOMAIN} dans votre navigateur"
    echo -e "${BOLD}║${NC}  et suivez l'assistant d'installation web pour :"
    echo -e "${BOLD}║${NC}    - Configurer le compte administrateur"
    echo -e "${BOLD}║${NC}    - Renseigner les infos société (${COMPANY_NAME})"
    echo -e "${BOLD}║${NC}    - Définir la devise (${CURRENCY})"
    echo -e "${BOLD}║${NC}    - Configurer le SMTP"
    echo -e "${BOLD}╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}║${NC}  Vérifications :"
    echo -e "${BOLD}║${NC}    certbot certificates      # SSL valide"
    echo -e "${BOLD}║${NC}    systemctl status nginx    # Nginx actif"
    echo -e "${BOLD}║${NC}    systemctl status php8.2-fpm  # PHP actif"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Tous les credentials sont sauvegardés dans : ${YELLOW}/root/.vps-infra-credentials${NC}"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo -e "${BOLD}=== Installation FOSSBilling (Nginx + PHP 8.2 + MariaDB + SSL) ===${NC}"
    echo ""

    check_root
    check_prerequisites
    step_install_packages
    step_configure_mariadb
    step_install_fossbilling
    step_configure_fossbilling
    step_configure_nginx_http
    step_obtain_ssl
    step_configure_php
    step_configure_cron
    print_summary
}

main "$@"
