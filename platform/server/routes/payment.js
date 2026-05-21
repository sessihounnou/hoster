import { Router } from 'express';
import db from '../db/index.js';
import { authMiddleware } from '../middleware/auth.js';
import { createTransaction, verifyWebhookEvent, getTransaction } from '../services/fedapay.js';
import { createVps } from '../services/virtualizor.js';
import { sendCredentials } from '../services/mailer.js';
import crypto from 'crypto';
import config from '../config.js';

const router = Router();

function encryptPassword(plain) {
  const key = Buffer.from(config.encryptionKey.padEnd(64, '0').slice(0, 64), 'hex');
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv('aes-256-cbc', key, iv);
  const encrypted = Buffer.concat([cipher.update(plain, 'utf8'), cipher.final()]);
  return iv.toString('hex') + ':' + encrypted.toString('hex');
}

function decryptPassword(enc) {
  const [ivHex, dataHex] = enc.split(':');
  const key = Buffer.from(config.encryptionKey.padEnd(64, '0').slice(0, 64), 'hex');
  const iv = Buffer.from(ivHex, 'hex');
  const decipher = crypto.createDecipheriv('aes-256-cbc', key, iv);
  const decrypted = Buffer.concat([decipher.update(Buffer.from(dataHex, 'hex')), decipher.final()]);
  return decrypted.toString('utf8');
}

// POST /api/payment/initiate — créer une commande + transaction FedaPay
router.post('/initiate', authMiddleware, async (req, res) => {
  try {
    const { plan_id, billing_cycle = 'monthly' } = req.body;
    if (!plan_id) return res.status(400).json({ error: 'plan_id requis.' });

    const plan = db.prepare('SELECT * FROM plans WHERE id = ? AND active = 1').get(plan_id);
    if (!plan) return res.status(404).json({ error: 'Plan introuvable ou inactif.' });

    const amount = billing_cycle === 'annually' ? (plan.price_annually || plan.price_monthly * 12) : plan.price_monthly;

    // Créer la commande en DB
    const orderResult = db.prepare(`
      INSERT INTO orders (user_id, plan_id, status, amount, currency, billing_cycle)
      VALUES (?, ?, 'pending', ?, 'XOF', ?)
    `).run(req.user.id, plan.id, amount, billing_cycle);

    const order = db.prepare('SELECT * FROM orders WHERE id = ?').get(orderResult.lastInsertRowid);
    const user = db.prepare('SELECT * FROM users WHERE id = ?').get(req.user.id);

    // Créer la transaction FedaPay
    const { transaction_id, checkout_url } = await createTransaction({ order, user, plan });

    // Sauvegarder l'ID de transaction FedaPay
    db.prepare('UPDATE orders SET fedapay_transaction_id = ? WHERE id = ?').run(transaction_id.toString(), order.id);

    res.json({ order_id: order.id, checkout_url });
  } catch (err) {
    console.error('[Payment] Erreur initiate:', err);
    res.status(500).json({ error: 'Erreur lors de la création du paiement.' });
  }
});

// GET /api/payment/verify/:order_id — vérification manuelle après retour FedaPay
router.get('/verify/:order_id', authMiddleware, async (req, res) => {
  try {
    const order = db.prepare('SELECT * FROM orders WHERE id = ? AND user_id = ?')
      .get(req.params.order_id, req.user.id);
    if (!order) return res.status(404).json({ error: 'Commande introuvable.' });

    if (['provisioning', 'active', 'cancelled'].includes(order.status)) {
      return res.json({ status: order.status });
    }

    // Accepter l'id FedaPay depuis l'URL de retour (?fedapay_id=...)
    const fedapayId = req.query.fedapay_id || order.fedapay_transaction_id;
    if (order.status === 'pending' && fedapayId) {
      if (fedapayId && !order.fedapay_transaction_id) {
        db.prepare('UPDATE orders SET fedapay_transaction_id = ? WHERE id = ?').run(fedapayId.toString(), order.id);
      }
      const transaction = await getTransaction(fedapayId);
      if (transaction.status === 'approved') {
        db.prepare("UPDATE orders SET status = 'paid', paid_at = CURRENT_TIMESTAMP WHERE id = ?").run(order.id);
        const fresh = db.prepare('SELECT * FROM orders WHERE id = ?').get(order.id);
        provisionVps(fresh).catch(err => {
          console.error('[Verify] Provisioning error:', err);
          db.prepare("UPDATE orders SET status = 'cancelled' WHERE id = ?").run(order.id);
        });
        return res.json({ status: 'provisioning' });
      }
    }

    res.json({ status: order.status });
  } catch (err) {
    console.error('[Verify] Erreur:', err);
    res.status(500).json({ error: 'Erreur de vérification.' });
  }
});

// POST /api/payment/webhook — reçoit les notifications FedaPay
router.post('/webhook', async (req, res) => {
  try {
    const payload = req.body;
    const event = verifyWebhookEvent(payload);

    // FedaPay envoie 'transaction.approved' quand le paiement est confirmé
    if (event.name !== 'transaction.approved') {
      return res.json({ received: true });
    }

    const transaction = event.data?.object;
    if (!transaction) return res.status(400).json({ error: 'Données de transaction manquantes.' });

    const transactionId = transaction.id?.toString();
    const order = db.prepare('SELECT * FROM orders WHERE fedapay_transaction_id = ?').get(transactionId);

    if (!order) {
      console.warn('[Webhook] Commande non trouvée pour transaction:', transactionId);
      return res.json({ received: true });
    }

    if (order.status !== 'pending') {
      return res.json({ received: true, message: 'Commande déjà traitée.' });
    }

    // Marquer comme payée
    db.prepare('UPDATE orders SET status = \'paid\', paid_at = CURRENT_TIMESTAMP WHERE id = ?').run(order.id);

    // Lancer le provisioning en arrière-plan
    provisionVps(order).catch(err => {
      console.error('[Webhook] Erreur provisioning:', err);
      db.prepare('UPDATE orders SET status = \'cancelled\' WHERE id = ?').run(order.id);
    });

    res.json({ received: true });
  } catch (err) {
    console.error('[Webhook] Erreur:', err);
    res.status(400).json({ error: 'Erreur traitement webhook.' });
  }
});

async function provisionVps(order) {
  const plan = db.prepare('SELECT * FROM plans WHERE id = ?').get(order.plan_id);
  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(order.user_id);

  db.prepare('UPDATE orders SET status = \'provisioning\' WHERE id = ?').run(order.id);

  const hostname = `vps-${order.id}-${user.id}.client.local`;
  const rootpass = crypto.randomBytes(12).toString('base64').replace(/[^A-Za-z0-9]/g, '').slice(0, 16);

  // Créer le VPS dans Virtualizor
  const { vs_id, ip } = await createVps({
    plan,
    hostname,
    rootpass,
    userEmail: user.email,
  });

  // Sauvegarder le VPS en DB
  const vpsResult = db.prepare(`
    INSERT INTO vps (order_id, user_id, plan_id, virtualizor_vs_id, ip_address, hostname, root_password_enc, status)
    VALUES (?, ?, ?, ?, ?, ?, ?, 'active')
  `).run(order.id, order.user_id, order.plan_id, vs_id, ip, hostname, encryptPassword(rootpass));

  const vps = db.prepare('SELECT * FROM vps WHERE id = ?').get(vpsResult.lastInsertRowid);

  db.prepare('UPDATE orders SET status = \'active\' WHERE id = ?').run(order.id);

  // Envoyer l'email avec les credentials (mot de passe en clair, une seule fois)
  await sendCredentials({ user, vps: { ...vps, root_password: rootpass }, plan });

  console.log(`[Provisioning] VPS créé : ${hostname} (${ip}) pour ${user.email}`);
}

export { decryptPassword };
export default router;
