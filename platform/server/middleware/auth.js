import jwt from 'jsonwebtoken';
import config from '../config.js';
import db from '../db/index.js';

export function authMiddleware(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Token d\'authentification manquant.' });
  }

  const token = authHeader.slice(7);
  try {
    const payload = jwt.verify(token, config.jwtSecret);
    const user = db.prepare('SELECT id, email, first_name, last_name, role FROM users WHERE id = ?').get(payload.id);
    if (!user) return res.status(401).json({ error: 'Utilisateur introuvable.' });

    req.user = user;
    next();
  } catch {
    return res.status(401).json({ error: 'Token invalide ou expiré.' });
  }
}
