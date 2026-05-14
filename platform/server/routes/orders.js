import { Router } from 'express';
import db from '../db/index.js';
import { authMiddleware } from '../middleware/auth.js';
import { adminMiddleware } from '../middleware/admin.js';

const router = Router();

// GET /api/orders — commandes de l'utilisateur connecté
router.get('/', authMiddleware, (req, res) => {
  const orders = db.prepare(`
    SELECT o.*, p.name as plan_name, p.vcpu, p.ram_mb, p.disk_gb
    FROM orders o
    JOIN plans p ON p.id = o.plan_id
    WHERE o.user_id = ?
    ORDER BY o.created_at DESC
  `).all(req.user.id);

  res.json({ orders });
});

// GET /api/orders/all — toutes les commandes (admin)
router.get('/all', authMiddleware, adminMiddleware, (req, res) => {
  const orders = db.prepare(`
    SELECT o.*, p.name as plan_name, u.email as user_email,
           u.first_name, u.last_name
    FROM orders o
    JOIN plans p ON p.id = o.plan_id
    JOIN users u ON u.id = o.user_id
    ORDER BY o.created_at DESC
  `).all();

  res.json({ orders });
});

// GET /api/orders/stats — statistiques (admin)
router.get('/stats', authMiddleware, adminMiddleware, (req, res) => {
  const stats = {
    total_orders: db.prepare('SELECT COUNT(*) as c FROM orders').get().c,
    active_orders: db.prepare("SELECT COUNT(*) as c FROM orders WHERE status = 'active'").get().c,
    pending_orders: db.prepare("SELECT COUNT(*) as c FROM orders WHERE status = 'pending'").get().c,
    total_revenue: db.prepare("SELECT COALESCE(SUM(amount), 0) as s FROM orders WHERE status IN ('paid','active')").get().s,
    total_clients: db.prepare("SELECT COUNT(*) as c FROM users WHERE role = 'client'").get().c,
    total_vps: db.prepare("SELECT COUNT(*) as c FROM vps WHERE status = 'active'").get().c,
  };

  res.json({ stats });
});

export default router;
