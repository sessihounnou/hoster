import { Router } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import db from '../db/index.js';
import config from '../config.js';
import { authMiddleware } from '../middleware/auth.js';
import { sendWelcome } from '../services/mailer.js';

const router = Router();

router.post('/register', async (req, res) => {
  try {
    const { email, password, first_name, last_name } = req.body;

    if (!email || !password || !first_name || !last_name) {
      return res.status(400).json({ error: 'Tous les champs sont obligatoires.' });
    }
    if (password.length < 8) {
      return res.status(400).json({ error: 'Le mot de passe doit contenir au moins 8 caractères.' });
    }

    const existing = db.prepare('SELECT id FROM users WHERE email = ?').get(email.toLowerCase());
    if (existing) {
      return res.status(409).json({ error: 'Cette adresse email est déjà utilisée.' });
    }

    const hash = await bcrypt.hash(password, 10);
    const result = db.prepare(`
      INSERT INTO users (email, password_hash, first_name, last_name, role)
      VALUES (?, ?, ?, ?, 'client')
    `).run(email.toLowerCase(), hash, first_name.trim(), last_name.trim());

    const user = db.prepare('SELECT id, email, first_name, last_name, role FROM users WHERE id = ?').get(result.lastInsertRowid);
    const token = jwt.sign({ id: user.id }, config.jwtSecret, { expiresIn: '7d' });

    sendWelcome({ user }).catch(err => console.error('[Mail] Erreur email bienvenue:', err));

    res.status(201).json({ token, user });
  } catch (err) {
    console.error('[Auth] Erreur register:', err);
    res.status(500).json({ error: 'Erreur serveur lors de l\'inscription.' });
  }
});

router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body;
    if (!email || !password) {
      return res.status(400).json({ error: 'Email et mot de passe requis.' });
    }

    const user = db.prepare('SELECT * FROM users WHERE email = ?').get(email.toLowerCase());
    if (!user) {
      return res.status(401).json({ error: 'Email ou mot de passe incorrect.' });
    }

    const valid = await bcrypt.compare(password, user.password_hash);
    if (!valid) {
      return res.status(401).json({ error: 'Email ou mot de passe incorrect.' });
    }

    const token = jwt.sign({ id: user.id }, config.jwtSecret, { expiresIn: '7d' });
    const { password_hash, ...safeUser } = user;

    res.json({ token, user: safeUser });
  } catch (err) {
    console.error('[Auth] Erreur login:', err);
    res.status(500).json({ error: 'Erreur serveur lors de la connexion.' });
  }
});

router.get('/me', authMiddleware, (req, res) => {
  res.json({ user: req.user });
});

export default router;
