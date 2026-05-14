import { Router } from 'express';
import db from '../db/index.js';
import { authMiddleware } from '../middleware/auth.js';
import { adminMiddleware } from '../middleware/admin.js';

const router = Router();

// GET /api/plans — public
router.get('/', (req, res) => {
  const plans = db.prepare('SELECT * FROM plans WHERE active = 1 ORDER BY price_monthly ASC').all();
  res.json({ plans });
});

// GET /api/plans/all — admin (inclut les plans inactifs)
router.get('/all', authMiddleware, adminMiddleware, (req, res) => {
  const plans = db.prepare('SELECT * FROM plans ORDER BY created_at DESC').all();
  res.json({ plans });
});

// POST /api/plans — admin
router.post('/', authMiddleware, adminMiddleware, (req, res) => {
  try {
    const { name, slug, description, vcpu, ram_mb, disk_gb, bandwidth_gb, price_monthly, price_annually, virtualizor_plan_id } = req.body;

    if (!name || !slug || !vcpu || !ram_mb || !disk_gb || !bandwidth_gb || !price_monthly) {
      return res.status(400).json({ error: 'Champs obligatoires manquants.' });
    }

    const existing = db.prepare('SELECT id FROM plans WHERE slug = ?').get(slug);
    if (existing) return res.status(409).json({ error: 'Ce slug est déjà utilisé.' });

    const result = db.prepare(`
      INSERT INTO plans (name, slug, description, vcpu, ram_mb, disk_gb, bandwidth_gb,
        price_monthly, price_annually, virtualizor_plan_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(name, slug, description || '', vcpu, ram_mb, disk_gb, bandwidth_gb,
      price_monthly, price_annually || null, virtualizor_plan_id || '');

    const plan = db.prepare('SELECT * FROM plans WHERE id = ?').get(result.lastInsertRowid);
    res.status(201).json({ plan });
  } catch (err) {
    console.error('[Plans] Erreur create:', err);
    res.status(500).json({ error: 'Erreur serveur.' });
  }
});

// PUT /api/plans/:id — admin
router.put('/:id', authMiddleware, adminMiddleware, (req, res) => {
  try {
    const { name, description, vcpu, ram_mb, disk_gb, bandwidth_gb, price_monthly, price_annually, virtualizor_plan_id, active } = req.body;

    const plan = db.prepare('SELECT id FROM plans WHERE id = ?').get(req.params.id);
    if (!plan) return res.status(404).json({ error: 'Plan introuvable.' });

    db.prepare(`
      UPDATE plans SET name = ?, description = ?, vcpu = ?, ram_mb = ?, disk_gb = ?,
        bandwidth_gb = ?, price_monthly = ?, price_annually = ?, virtualizor_plan_id = ?, active = ?
      WHERE id = ?
    `).run(name, description, vcpu, ram_mb, disk_gb, bandwidth_gb,
      price_monthly, price_annually || null, virtualizor_plan_id || '', active ?? 1, req.params.id);

    const updated = db.prepare('SELECT * FROM plans WHERE id = ?').get(req.params.id);
    res.json({ plan: updated });
  } catch (err) {
    console.error('[Plans] Erreur update:', err);
    res.status(500).json({ error: 'Erreur serveur.' });
  }
});

// DELETE /api/plans/:id — admin (désactivation)
router.delete('/:id', authMiddleware, adminMiddleware, (req, res) => {
  const plan = db.prepare('SELECT id FROM plans WHERE id = ?').get(req.params.id);
  if (!plan) return res.status(404).json({ error: 'Plan introuvable.' });

  db.prepare('UPDATE plans SET active = 0 WHERE id = ?').run(req.params.id);
  res.json({ message: 'Plan désactivé.' });
});

export default router;
