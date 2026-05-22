import axios from 'axios';
import db from '../db/index.js';

const CONTABO_AUTH_URL = 'https://auth.contabo.com/auth/realms/contabo/protocol/openid-connect/token';
const CONTABO_API = 'https://api.contabo.com/v1';

let _token = null;
let _tokenExpiry = 0;

async function getToken() {
  if (_token && Date.now() < _tokenExpiry) return _token;

  const params = new URLSearchParams({
    client_id: process.env.CONTABO_CLIENT_ID,
    client_secret: process.env.CONTABO_CLIENT_SECRET,
    username: process.env.CONTABO_API_USER,
    password: process.env.CONTABO_API_PASSWORD,
    grant_type: 'password',
  });

  const res = await axios.post(CONTABO_AUTH_URL, params.toString(), {
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
  });

  _token = res.data.access_token;
  _tokenExpiry = Date.now() + (res.data.expires_in - 60) * 1000;
  return _token;
}

async function contaboApi(method, path, data = null) {
  const token = await getToken();
  const res = await axios({
    method,
    url: `${CONTABO_API}${path}`,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      'x-request-id': crypto.randomUUID(),
    },
    data: data || undefined,
  });
  return res.data;
}

// Acheter une nouvelle IP additionnelle pour le VPS host
export async function purchaseAdditionalIp() {
  const instanceId = process.env.CONTABO_INSTANCE_ID;
  if (!instanceId) throw new Error('CONTABO_INSTANCE_ID non configuré.');

  // Commander une IP additionnelle
  const res = await contaboApi('POST', `/compute/instances/${instanceId}/ips`, {});
  const ip = res.data?.[0]?.ipConfig?.v4?.ip || res.data?.ipv4;

  if (!ip) throw new Error(`Réponse Contabo inattendue: ${JSON.stringify(res)}`);

  // Stocker dans le pool
  db.prepare('INSERT INTO ip_pool (ip_address, instance_id, status) VALUES (?, ?, \'available\')')
    .run(ip, instanceId);

  console.log(`[Contabo] Nouvelle IP achetée et ajoutée au pool: ${ip}`);
  return ip;
}

// Récupérer la prochaine IP libre du pool (ou en acheter une nouvelle)
export async function allocateIp() {
  // Essayer d'abord le pool local
  const available = db.prepare("SELECT * FROM ip_pool WHERE status = 'available' LIMIT 1").get();
  if (available) {
    db.prepare("UPDATE ip_pool SET status = 'allocated' WHERE id = ?").run(available.id);
    console.log(`[Contabo] IP allouée depuis le pool: ${available.ip_address}`);
    return { ip: available.ip_address, pool_id: available.id };
  }

  // Pool vide → acheter une nouvelle IP
  console.log('[Contabo] Pool vide, achat d\'une nouvelle IP...');
  const ip = await purchaseAdditionalIp();

  const newEntry = db.prepare("SELECT * FROM ip_pool WHERE ip_address = ?").get(ip);
  db.prepare("UPDATE ip_pool SET status = 'allocated' WHERE ip_address = ?").run(ip);

  // Alerte si le pool est maintenant à 0
  const remaining = db.prepare("SELECT COUNT(*) as n FROM ip_pool WHERE status = 'available'").get();
  if (remaining.n === 0) {
    console.warn('[Contabo] ALERTE: pool d\'IPs épuisé après allocation.');
  }

  return { ip, pool_id: newEntry?.id };
}

// Libérer une IP quand un VPS est supprimé
export async function releaseIp(ip) {
  db.prepare("UPDATE ip_pool SET status = 'available', allocated_to_vps = NULL WHERE ip_address = ?").run(ip);
  console.log(`[Contabo] IP libérée: ${ip}`);
}

// Vérifier le solde et envoyer une alerte si bas
export async function checkBalance() {
  try {
    const res = await contaboApi('GET', '/billing/balance');
    const balance = res.data?.balance;
    console.log(`[Contabo] Solde: ${balance}€`);
    if (balance < 5) {
      console.warn(`[Contabo] ALERTE SOLDE BAS: ${balance}€`);
    }
    return balance;
  } catch (e) {
    console.warn('[Contabo] Impossible de vérifier le solde:', e.message);
    return null;
  }
}

export function isConfigured() {
  return !!(process.env.CONTABO_CLIENT_ID && process.env.CONTABO_CLIENT_SECRET &&
    process.env.CONTABO_API_USER && process.env.CONTABO_API_PASSWORD &&
    process.env.CONTABO_INSTANCE_ID);
}
