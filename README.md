# Infrastructure VPS Revendable — Proxmox + Virtualizor + FOSSBilling

Infrastructure complète de revente VPS sur serveur dédié Contabo Ubuntu 22.04.

## Architecture

```
Internet
   │
   ▼
[Serveur Contabo — 1 IP publique]
   │
   ├─ Proxmox VE 8.x (hyperviseur)
   │     └─ vmbr0 : bridge public (IP serveur)
   │     └─ vmbr1 : bridge NAT 10.10.10.0/24 (VMs clients)
   │
   ├─ Virtualizor (panel VPS :4082)
   │     └─ Backend Proxmox via API :8006
   │     └─ Gestion VMs, plans, clients
   │
   └─ FOSSBilling (facturation HTTPS)
         └─ Nginx + PHP 8.2 + MariaDB + SSL
         └─ Module Virtualizor → création VPS automatique
```

## Ordre d'exécution

> ⚠️ **IMPORTANT** : Les scripts doivent être exécutés dans cet ordre précis.
> Un reboot est obligatoire après le script 01.

### Étape 0 — Préparer les variables

Éditez chaque script pour renseigner vos valeurs avant exécution :

| Script | Variables à modifier |
|--------|---------------------|
| `01_install_proxmox.sh` | `PVE_HOSTNAME` (ex: `pve.monserveur.com`) |
| `02_install_virtualizor.sh` | `ADMIN_EMAIL`, `PROXMOX_ROOT_PASS` |
| `03_install_fossbilling.sh` | `DOMAIN`, `ADMIN_EMAIL`, `COMPANY_NAME` |
| `04_connect_fossbilling_virt.sh` | `FOSSBILLING_URL`, `FOSSBILLING_ADMIN_TOKEN` |
| `05_network_config.sh` | `VM_SUBNET`, `VM_GATEWAY` (optionnel, valeurs par défaut OK) |

Vous pouvez aussi passer les variables en ligne de commande :

```bash
DOMAIN=billing.monsite.com ADMIN_EMAIL=admin@monsite.com bash 03_install_fossbilling.sh
```

### Étape 1 — Installer Proxmox VE

```bash
chmod +x 01_install_proxmox.sh
bash 01_install_proxmox.sh
# ⚠ REBOOT OBLIGATOIRE à la fin
reboot
```

**Vérification** : `https://VOTRE_IP:8006` doit afficher le panel Proxmox.

---

### Étape 2 — Configurer le réseau

```bash
bash 05_network_config.sh
```

**Vérification** :
```bash
ip a                              # vmbr0 et vmbr1 visibles
sysctl net.ipv4.ip_forward        # doit afficher 1
iptables -t nat -L -n -v          # règle MASQUERADE visible
```

---

### Étape 3 — Installer Virtualizor

```bash
bash 02_install_virtualizor.sh
```

**Vérification** : `https://VOTRE_IP:4082` doit afficher le panel Virtualizor.

**Étapes manuelles dans Virtualizor** :
1. Connectez-vous au panel admin
2. **Configuration > Serveurs > Ajouter un serveur**
   - Type : `Proxmox`
   - IP : `127.0.0.1`, Port : `8006`
   - Username : `root@pam`, Password : votre mot de passe root
3. **Gestion VPS > Plans > Ajouter un plan** (voir `/tmp/virt-test-plan.conf`)

---

### Étape 4 — Installer FOSSBilling

```bash
DOMAIN=billing.votredomaine.com bash 03_install_fossbilling.sh
```

**Vérification** : `https://billing.votredomaine.com` doit afficher l'assistant d'installation.

**Étape manuelle obligatoire** : Ouvrez le domaine dans votre navigateur et complétez l'assistant web FOSSBilling (création du compte admin, configuration SMTP, etc.).

---

### Étape 5 — Connecter FOSSBilling à Virtualizor

```bash
# Récupérez d'abord votre token API FOSSBilling dans Admin > Profil > Clés API
FOSSBILLING_ADMIN_TOKEN=votre_token bash 04_connect_fossbilling_virt.sh
```

**Vérification** dans FOSSBilling Admin :
- Hébergement > Serveurs → connexion Virtualizor = OK
- Produits → VPS Starter visible avec son prix

---

## Credentials

Tous les mots de passe générés sont sauvegardés dans :

```bash
cat /root/.vps-infra-credentials
```

## Ports ouverts

| Port | Service |
|------|---------|
| 22 | SSH |
| 80 | HTTP (redirect HTTPS) |
| 443 | HTTPS FOSSBilling |
| 4082 | Virtualizor Admin |
| 4083 | Virtualizor Client |
| 8006 | Proxmox Web UI (HTTPS) |

## Dépannage

### Proxmox ne démarre pas après reboot
```bash
# Vérifier que le kernel PVE est chargé
uname -r   # doit contenir "pve"

# Voir les logs de démarrage
journalctl -b -u pve-manager
```

### Les VMs n'ont pas accès à Internet
```bash
# Vérifier le NAT
iptables -t nat -L -n -v | grep MASQUERADE

# Vérifier le forwarding
cat /proc/sys/net/ipv4/ip_forward   # doit afficher 1

# Relancer les règles
bash 05_network_config.sh
```

### Certbot échoue (SSL)
```bash
# Vérifier que le port 80 est accessible
curl -I http://billing.votredomaine.com

# Vérifier le DNS
dig +short billing.votredomaine.com

# Renouveler manuellement
certbot renew --dry-run
```

### FOSSBilling affiche une erreur 500
```bash
# Consulter les logs Nginx
tail -50 /var/log/nginx/fossbilling-error.log

# Vérifier PHP
systemctl status php8.2-fpm

# Permissions
chown -R www-data:www-data /var/www/fossbilling
```
