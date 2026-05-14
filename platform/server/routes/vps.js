import { Router } from 'express';
import db from '../db/index.js';
import { authMiddleware } from '../middleware/auth.js';
import { adminMiddleware } from '../middleware/admin.js';
import { stopVps, startVps } from '../services/virtualizor.js';
import { decryptPassword } from './payment.js';

const router = Router();

// GET /api/vps — VPS du client connecté
router.get('/', authMiddleware, (req, res) => {
  const vpsList = db.prepare(`
    SELECT v.id, v.ip_address, v.hostname, v.status, v.created_at,
           v.virtualizor_vs_id,
           p.name as plan_name, p.vcpu, p.ram_mb, p.disk_gb, p.bandwidth_gb
    FROM vps v
    JOIN plans p ON p.id = v.plan_id
    WHERE v.user_id = ?
    ORDER BY v.created_at DESC
  `).all(req.user.id);

  res.json({ vps: vpsList });
});

// GET /api/vps/:id/credentials — mot de passe root déchiffré
router.get('/:id/credentials', authMiddleware, (req, res) => {
  const vps = db.prepare('SELECT * FROM vps WHERE id = ? AND user_id = ?').get(req.params.id, req.user.id);
  if (!vps) return res.status(404).json({ error: 'VPS introuvable.' });

  try {
    const password = decryptPassword(vps.root_password_enc);
    res.json({ ip: vps.ip_address, hostname: vps.hostname, username: 'root', password });
  } catch {
    res.status(500).json({ error: 'Impossible de déchiffrer les credentials.' });
  }
});

// POST /api/vps/:id/stop — arrêter un VPS
router.post('/:id/stop', authMiddleware, async (req, res) => {
  const vps = db.prepare('SELECT * FROM vps WHERE id = ? AND user_id = ?').get(req.params.id, req.user.id);
  if (!vps) return res.status(404).json({ error: 'VPS introuvable.' });

  try {
    await stopVps(vps.virtualizor_vs_id);
    db.prepare('UPDATE vps SET status = ? WHERE id = ?').run('suspended', vps.id);
    res.json({ message: 'VPS arrêté.' });
  } catch (err) {
    res.status(500).json({ error: 'Impossible d\'arrêter le VPS.' });
  }
});

// POST /api/vps/:id/start — démarrer un VPS
router.post('/:id/start', authMiddleware, async (req, res) => {
  const vps = db.prepare('SELECT * FROM vps WHERE id = ? AND user_id = ?').get(req.params.id, req.user.id);
  if (!vps) return res.status(404).json({ error: 'VPS introuvable.' });

  try {
    await startVps(vps.virtualizor_vs_id);
    db.prepare('UPDATE vps SET status = ? WHERE id = ?').run('active', vps.id);
    res.json({ message: 'VPS démarré.' });
  } catch (err) {
    res.status(500).json({ error: 'Impossible de démarrer le VPS.' });
  }
});

// GET /api/vps/all — tous les VPS (admin)
router.get('/all', authMiddleware, adminMiddleware, (req, res) => {
  const vpsList = db.prepare(`
    SELECT v.id, v.ip_address, v.hostname, v.status, v.created_at,
           v.virtualizor_vs_id,
           p.name as plan_name,
           u.email as user_email, u.first_name, u.last_name
    FROM vps v
    JOIN plans p ON p.id = v.plan_id
    JOIN users u ON u.id = v.user_id
    ORDER BY v.created_at DESC
  `).all();

  res.json({ vps: vpsList });
});

// GET /api/vps/clients — tous les clients (admin)
router.get('/clients', authMiddleware, adminMiddleware, (req, res) => {
  const clients = db.prepare(`
    SELECT u.id, u.email, u.first_name, u.last_name, u.created_at,
           COUNT(v.id) as vps_count,
           COUNT(o.id) as order_count
    FROM users u
    LEFT JOIN vps v ON v.user_id = u.id
    LEFT JOIN orders o ON o.user_id = u.id
    WHERE u.role = 'client'
    GROUP BY u.id
    ORDER BY u.created_at DESC
  `).all();

  res.json({ clients });
});

export default router;
