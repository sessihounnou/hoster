import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import config from './config.js';
import { runMigrations } from './db/migrations.js';

import authRoutes from './routes/auth.js';
import plansRoutes from './routes/plans.js';
import ordersRoutes from './routes/orders.js';
import paymentRoutes from './routes/payment.js';
import vpsRoutes from './routes/vps.js';

const app = express();

// Middlewares globaux
app.use(cors({
  origin: [config.frontendUrl, 'http://localhost:5173'],
  credentials: true,
}));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Rate limiting
app.use('/api/auth/', rateLimit({ windowMs: 15 * 60 * 1000, max: 20, message: { error: 'Trop de requêtes. Réessayez dans 15 minutes.' } }));
app.use('/api/', rateLimit({ windowMs: 60 * 1000, max: 200 }));

// Routes
app.use('/api/auth', authRoutes);
app.use('/api/plans', plansRoutes);
app.use('/api/orders', ordersRoutes);
app.use('/api/payment', paymentRoutes);
app.use('/api/vps', vpsRoutes);

// Health check
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', version: '1.0.0', env: config.nodeEnv });
});

// 404
app.use((req, res) => {
  res.status(404).json({ error: 'Route non trouvée.' });
});

// Gestion erreurs globale
app.use((err, req, res, next) => {
  console.error('[Server]', err);
  res.status(500).json({ error: 'Erreur interne du serveur.' });
});

// Démarrage
runMigrations();
app.listen(config.port, () => {
  console.log(`[Server] API démarrée sur http://localhost:${config.port}`);
  console.log(`[Server] Environnement : ${config.nodeEnv}`);
});
