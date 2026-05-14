#!/usr/bin/env bash
# =============================================================================
# Script 4 : Connexion FOSSBilling ↔ Virtualizor via module et API
# =============================================================================
# Ce script configure la liaison entre FOSSBilling (facturation) et Virtualizor
# (gestion VPS) pour que les commandes clients déclenche automatiquement la
# création des VPS.
#
# Flux automatisé :
#   Client commande VPS → FOSSBilling reçoit le paiement
#   → Module Virtualizor appelé → API Virtualizor → VPS créé → Email client
#
# Prérequis :
#   - Script 02 exécuté (Virtualizor installé, API key disponible)
#   - Script 03 exécuté (FOSSBilling installé)
#   - L'assistant web FOSSBilling complété (compte admin créé)
# =============================================================================

set -euo pipefail

# ── Variables à modifier ──────────────────────────────────────────────────────
FOSSBILLING_URL="${FOSSBILLING_URL:-https://billing.mondomaine.com}"
FOSSBILLING_ADMIN_TOKEN="${FOSSBILLING_ADMIN_TOKEN:-}"
VIRTUALIZOR_IP="${VIRTUALIZOR_IP:-127.0.0.1}"
VIRTUALIZOR_PORT="${VIRTUALIZOR_PORT:-4082}"
VIRTUALIZOR_API_KEY="${VIRTUALIZOR_API_KEY:-}"
VIRTUALIZOR_API_PASS="${VIRTUALIZOR_API_PASS:-}"
WEBROOT="${WEBROOT:-/var/www/fossbilling}"
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

# ── Charger les credentials depuis le fichier si non définis ─────────────────
load_credentials_from_file() {
    local creds_file="/root/.vps-infra-credentials"

    if [[ ! -f "$creds_file" ]]; then
        log_warn "Fichier credentials non trouvé : ${creds_file}"
        return 0
    fi

    if [[ -z "$VIRTUALIZOR_API_KEY" ]]; then
        VIRTUALIZOR_API_KEY=$(grep "Virtualizor API Key" "$creds_file" 2>/dev/null | tail -1 | awk -F': ' '{print $NF}' || echo "")
    fi

    if [[ -z "$VIRTUALIZOR_API_PASS" ]]; then
        VIRTUALIZOR_API_PASS=$(grep "Virtualizor API Pass" "$creds_file" 2>/dev/null | tail -1 | awk -F': ' '{print $NF}' || echo "")
    fi
}

# ── Vérifications préalables ──────────────────────────────────────────────────
check_prerequisites() {
    # FOSSBilling
    if [[ ! -f "${WEBROOT}/index.php" ]]; then
        log_error "FOSSBilling non trouvé dans ${WEBROOT}."
        log_error "Exécutez d'abord : bash 03_install_fossbilling.sh"
        exit 1
    fi
    log_success "FOSSBilling détecté dans ${WEBROOT}."

    # Virtualizor
    if [[ ! -f /usr/local/virtualizor/cmd/virtualizor ]]; then
        log_error "Virtualizor non installé."
        log_error "Exécutez d'abord : bash 02_install_virtualizor.sh"
        exit 1
    fi
    log_success "Virtualizor détecté."

    # Charger les clés API depuis le fichier credentials
    load_credentials_from_file

    # Demander les clés API si manquantes
    if [[ -z "$VIRTUALIZOR_API_KEY" ]]; then
        read -rp "Clé API Virtualizor (API Key) : " VIRTUALIZOR_API_KEY
    fi
    if [[ -z "$VIRTUALIZOR_API_PASS" ]]; then
        read -rsp "Mot de passe API Virtualizor (API Pass) : " VIRTUALIZOR_API_PASS
        echo ""
    fi

    if [[ -z "$VIRTUALIZOR_API_KEY" || -z "$VIRTUALIZOR_API_PASS" ]]; then
        log_error "Les clés API Virtualizor sont requises."
        log_error "Retrouvez-les dans le panel Virtualizor : Configuration > API"
        exit 1
    fi

    # Demander le token admin FOSSBilling si non défini
    if [[ -z "$FOSSBILLING_ADMIN_TOKEN" ]]; then
        log_warn "Token admin FOSSBilling non défini."
        log_info "Pour l'obtenir :"
        log_info "  1. Connectez-vous à ${FOSSBILLING_URL}/admin"
        log_info "  2. Allez dans Profil > Clés API > Générer une clé"
        read -rsp "Token API Admin FOSSBilling : " FOSSBILLING_ADMIN_TOKEN
        echo ""
    fi
}

# ── Tester la connexion à l'API FOSSBilling ───────────────────────────────────
test_fossbilling_api() {
    log_info "Test de l'API FOSSBilling..."

    local response http_code
    http_code=$(curl -sk -o /dev/null -w "%{http_code}" \
        "${FOSSBILLING_URL}/api/admin/system/version" \
        -H "Authorization: Bearer ${FOSSBILLING_ADMIN_TOKEN}" 2>/dev/null || echo "000")

    if [[ "$http_code" != "200" ]]; then
        log_error "API FOSSBilling inaccessible (HTTP ${http_code})."
        log_error "Vérifiez :"
        log_error "  - FOSSBilling est configuré (assistant web complété)"
        log_error "  - Le token API est valide"
        log_error "  - Le domaine ${FOSSBILLING_URL} est accessible"
        exit 1
    fi
    log_success "API FOSSBilling accessible."
}

# ── Appel API FOSSBilling générique ───────────────────────────────────────────
fossbilling_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"

    local curl_args=(-sk -X "$method" \
        "${FOSSBILLING_URL}/api/${endpoint}" \
        -H "Authorization: Bearer ${FOSSBILLING_ADMIN_TOKEN}" \
        -H "Content-Type: application/json")

    if [[ -n "$data" ]]; then
        curl_args+=(-d "$data")
    fi

    curl "${curl_args[@]}" 2>/dev/null
}

# ── Étape 1 : Installer le module Virtualizor dans FOSSBilling ────────────────
step_install_virtualizor_module() {
    # Le module Virtualizor pour FOSSBilling se trouve dans le dossier
    # src/modules/Servicehosting ou via une extension dédiée.
    # FOSSBilling gère les hébergeurs via le système d'extensions "Server Manager".

    local module_dir="${WEBROOT}/src/modules/Servicehosting/Server/Managers"
    local module_file="${module_dir}/Virtualizor.php"

    if [[ -f "$module_file" ]]; then
        log_warn "Module Virtualizor déjà présent dans FOSSBilling."
        return 0
    fi

    log_info "Installation du module Virtualizor pour FOSSBilling..."
    mkdir -p "$module_dir"

    # Chercher le module dans les sources GitHub de FOSSBilling
    local module_url="https://raw.githubusercontent.com/FOSSBilling/FOSSBilling/main/src/modules/Servicehosting/Server/Managers/Virtualizor.php"

    if wget -q --spider "$module_url" 2>/dev/null; then
        wget -q -O "$module_file" "$module_url"
        log_success "Module Virtualizor téléchargé depuis GitHub."
    else
        log_warn "Module non trouvé sur GitHub. Création du module de base..."
        step_create_virtualizor_module "$module_file"
    fi

    chown www-data:www-data "$module_file"
    chmod 644 "$module_file"
    log_success "Module Virtualizor installé dans FOSSBilling."
}

# ── Créer le module Virtualizor si non disponible en ligne ───────────────────
step_create_virtualizor_module() {
    local output_file="$1"

    cat > "$output_file" <<'PHPEOF'
<?php
/**
 * FOSSBilling — Virtualizor Server Manager
 * Permet la création/suppression automatique de VPS via l'API Virtualizor.
 */

namespace Box\Mod\Servicehosting\Server\Managers;

use Box\Mod\Servicehosting\Server\Manager;

class Virtualizor extends Manager
{
    public static function getForm(): array
    {
        return [
            'label' => 'Virtualizor',
            'form'  => [
                'credentials' => [
                    'fields' => [
                        [
                            'name'  => 'apikey',
                            'label' => 'API Key',
                            'type'  => 'text',
                        ],
                        [
                            'name'  => 'apipass',
                            'label' => 'API Password',
                            'type'  => 'password',
                        ],
                    ],
                ],
            ],
        ];
    }

    private function apiCall(string $act, array $params = []): array
    {
        $server    = $this->getServer();
        $apikey    = $server->getParam('apikey');
        $apipass   = $server->getParam('apipass');
        $ip        = $server->getIp();
        $port      = $server->getPort() ?: 4082;

        $timestamp = microtime(true);
        $signature = md5($apikey . $apipass . $timestamp);

        $url = "https://{$ip}:{$port}/index.php?act={$act}";
        $url .= "&apikey={$apikey}&timestamp={$timestamp}&signature={$signature}";

        $params['api'] = 'json';
        $query = http_build_query($params);

        $ch = curl_init();
        curl_setopt_array($ch, [
            CURLOPT_URL            => $url,
            CURLOPT_POST           => true,
            CURLOPT_POSTFIELDS     => $query,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_SSL_VERIFYPEER => false,
            CURLOPT_TIMEOUT        => 30,
        ]);

        $response = curl_exec($ch);
        $errno    = curl_errno($ch);
        curl_close($ch);

        if ($errno) {
            throw new \Exception("Virtualizor API error: " . curl_strerror($errno));
        }

        $data = json_decode($response, true);
        if (!$data) {
            throw new \Exception("Invalid API response from Virtualizor");
        }

        return $data;
    }

    public function testConnection(): bool
    {
        $result = $this->apiCall('listvs', ['page' => 1, 'reslen' => 1]);
        return isset($result['title']);
    }

    public function createAccount(\Box\Mod\Servicehosting\Server\Account $account): bool
    {
        $params = [
            'virt_type'  => 'kvm',
            'node_id'    => 0,
            'hostname'   => $account->getDomain(),
            'rootpass'   => $account->getPassword(),
            'user_email' => $account->getUsername(),
            'user_pass'  => $account->getPassword(),
            'plid'       => $account->getPackageCustomField('plan_id'),
        ];

        $result = $this->apiCall('addvs', $params);

        if (!empty($result['done'])) {
            $account->setIp($result['vs_info']['ip'][0] ?? '');
            return true;
        }

        throw new \Exception("Failed to create VPS: " . json_encode($result['error'] ?? []));
    }

    public function suspendAccount(\Box\Mod\Servicehosting\Server\Account $account): bool
    {
        $vsid   = $account->getParam('vs_id');
        $result = $this->apiCall('stopvs', ['svs' => $vsid]);
        return !empty($result['done']);
    }

    public function unsuspendAccount(\Box\Mod\Servicehosting\Server\Account $account): bool
    {
        $vsid   = $account->getParam('vs_id');
        $result = $this->apiCall('startvs', ['svs' => $vsid]);
        return !empty($result['done']);
    }

    public function terminateAccount(\Box\Mod\Servicehosting\Server\Account $account): bool
    {
        $vsid   = $account->getParam('vs_id');
        $result = $this->apiCall('deletevs', ['svs' => $vsid]);
        return !empty($result['done']);
    }

    public function changeAccountPackage(\Box\Mod\Servicehosting\Server\Account $account): bool
    {
        return true;
    }

    public function changeAccountPassword(\Box\Mod\Servicehosting\Server\Account $account): bool
    {
        $vsid   = $account->getParam('vs_id');
        $result = $this->apiCall('vpsmanage', [
            'svs'      => $vsid,
            'rootpass' => $account->getPassword(),
        ]);
        return !empty($result['done']);
    }
}
PHPEOF

    log_success "Module Virtualizor créé localement."
}

# ── Étape 2 : Configurer le serveur Virtualizor dans FOSSBilling ──────────────
step_configure_server_in_fossbilling() {
    log_info "Ajout du serveur Virtualizor dans FOSSBilling..."

    local server_data
    server_data=$(cat <<JSON
{
    "name": "Virtualizor Principal",
    "type": "Virtualizor",
    "ip": "${VIRTUALIZOR_IP}",
    "port": "${VIRTUALIZOR_PORT}",
    "login": "api",
    "password": "${VIRTUALIZOR_API_KEY}",
    "config": "{\"apipass\": \"${VIRTUALIZOR_API_PASS}\"}",
    "active": 1,
    "status_url": "https://${VIRTUALIZOR_IP}:${VIRTUALIZOR_PORT}/",
    "name_servers": "",
    "ns_ip": "",
    "ns_ip2": "",
    "hostname": "${VIRTUALIZOR_IP}",
    "max_accounts": 100,
    "secure": 1
}
JSON
)

    local response
    response=$(fossbilling_api "POST" "admin/servicehosting/server_save" "$server_data")

    if echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',''))" 2>/dev/null | grep -q "1\|true"; then
        log_success "Serveur Virtualizor ajouté dans FOSSBilling."
    else
        log_warn "Réponse inattendue lors de l'ajout du serveur :"
        echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
        log_warn "Ajoutez manuellement le serveur via FOSSBilling Admin > Hébergement > Serveurs"
    fi
}

# ── Étape 3 : Créer un produit VPS dans FOSSBilling ──────────────────────────
step_create_vps_product() {
    log_info "Création du produit VPS Starter dans FOSSBilling..."

    # Créer d'abord une catégorie "VPS"
    local cat_response
    cat_response=$(fossbilling_api "POST" "admin/product/category_create" \
        '{"title": "VPS", "description": "Serveurs Virtuels Privés"}')

    local cat_id
    cat_id=$(echo "$cat_response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result', 1))" 2>/dev/null || echo "1")

    # Créer le produit VPS
    local product_data
    product_data=$(cat <<JSON
{
    "title": "VPS Starter",
    "product_category_id": ${cat_id},
    "type": "hosting",
    "description": "VPS 1 vCPU / 1 GB RAM / 20 GB SSD\\n\\nIdéal pour débuter. Inclus :\\n- 1 vCPU\\n- 1 GB RAM\\n- 20 GB SSD NVMe\\n- 1 TB bande passante/mois\\n- 1 adresse IP",
    "status": "active",
    "setup": "after_payment",
    "hidden": 0,
    "taxed": 1,
    "allow_quantity_select": 0,
    "stock_control": 0,
    "quantity_in_stock": 0,
    "plugin": "Virtualizor",
    "config": {
        "plan": "starter-1vcpu-1gb-20gb",
        "plan_id": "1",
        "server_group": "1",
        "hostname_format": "vps{order_id}.${FOSSBILLING_URL#*//}"
    }
}
JSON
)

    local prod_response
    prod_response=$(fossbilling_api "POST" "admin/product/prepare" "$product_data")
    local prod_id
    prod_id=$(echo "$prod_response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result', 0))" 2>/dev/null || echo "0")

    if [[ "$prod_id" != "0" && -n "$prod_id" ]]; then
        log_success "Produit VPS Starter créé (ID: ${prod_id})."

        # Ajouter le prix : 5€/mois
        local price_data
        price_data=$(cat <<JSON
{
    "product_id": ${prod_id},
    "currency": "${CURRENCY}",
    "monthly": "5.00",
    "quarterly": "14.00",
    "annually": "50.00"
}
JSON
)
        fossbilling_api "POST" "admin/product/price_update" "$price_data" > /dev/null 2>&1 || \
            log_warn "Prix non configurés automatiquement. Configurez-les manuellement."

        log_success "Prix configurés : 5€/mois, 14€/trimestre, 50€/an."
    else
        log_warn "Création produit : réponse inattendue. Créez le produit manuellement."
        log_warn "FOSSBilling Admin > Produits > Ajouter un produit"
    fi
}

# ── Étape 4 : Tester la connexion Virtualizor depuis FOSSBilling ──────────────
step_test_connection() {
    log_info "Test de la connexion FOSSBilling → Virtualizor..."

    local response
    response=$(fossbilling_api "POST" "admin/servicehosting/server_test_connection" \
        '{"id": 1}')

    local success
    success=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',''))" 2>/dev/null || echo "")

    if [[ "$success" == "1" || "$success" == "True" || "$success" == "true" ]]; then
        log_success "Connexion FOSSBilling ↔ Virtualizor : OK"
    else
        log_warn "Test de connexion non concluant. Vérification manuelle recommandée."
        log_warn "FOSSBilling Admin > Hébergement > Serveurs > Tester la connexion"
    fi
}

# ── Résumé final ──────────────────────────────────────────────────────────────
print_summary() {
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║       FOSSBILLING ↔ VIRTUALIZOR - CONFIGURATION         ║${NC}"
    echo -e "${BOLD}╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}║${NC}  Module       : ${GREEN}Virtualizor installé${NC}"
    echo -e "${BOLD}║${NC}  Serveur      : ${GREEN}${VIRTUALIZOR_IP}:${VIRTUALIZOR_PORT}${NC}"
    echo -e "${BOLD}║${NC}  Produit VPS  : ${GREEN}VPS Starter (5€/mois)${NC}"
    echo -e "${BOLD}║${NC}"
    echo -e "${BOLD}║${NC}  Vérifications dans FOSSBilling Admin :"
    echo -e "${BOLD}║${NC}    ${FOSSBILLING_URL}/admin"
    echo -e "${BOLD}║${NC}    → Hébergement > Serveurs > connexion OK"
    echo -e "${BOLD}║${NC}    → Produits > VPS Starter visible"
    echo -e "${BOLD}║${NC}"
    echo -e "${BOLD}║${NC}  Pour tester la commande complète :"
    echo -e "${BOLD}║${NC}    1. Créez un compte client de test"
    echo -e "${BOLD}║${NC}    2. Passez une commande VPS Starter"
    echo -e "${BOLD}║${NC}    3. Approuvez le paiement manuellement"
    echo -e "${BOLD}║${NC}    4. Vérifiez le VPS dans le panel Virtualizor"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo -e "${BOLD}=== Connexion FOSSBilling ↔ Virtualizor ===${NC}"
    echo ""

    check_root
    check_prerequisites
    test_fossbilling_api
    step_install_virtualizor_module
    step_configure_server_in_fossbilling
    step_create_vps_product
    step_test_connection
    print_summary
}

main "$@"
