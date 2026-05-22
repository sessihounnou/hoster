import db from './index.js';
import bcrypt from 'bcryptjs';
import config from '../config.js';

export function runMigrations() {
  db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      email        TEXT    UNIQUE NOT NULL,
      password_hash TEXT   NOT NULL,
      first_name   TEXT    NOT NULL DEFAULT '',
      last_name    TEXT    NOT NULL DEFAULT '',
      role         TEXT    NOT NULL DEFAULT 'client',
      created_at   DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS plans (
      id                   INTEGER PRIMARY KEY AUTOINCREMENT,
      name                 TEXT    NOT NULL,
      slug                 TEXT    UNIQUE NOT NULL,
      description          TEXT    DEFAULT '',
      vcpu                 INTEGER NOT NULL,
      ram_mb               INTEGER NOT NULL,
      disk_gb              INTEGER NOT NULL,
      bandwidth_gb         INTEGER NOT NULL,
      price_monthly        REAL    NOT NULL,
      price_annually       REAL,
      virtualizor_plan_id  TEXT    DEFAULT '',
      active               INTEGER DEFAULT 1,
      created_at           DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS orders (
      id                     INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id                INTEGER NOT NULL REFERENCES users(id),
      plan_id                INTEGER NOT NULL REFERENCES plans(id),
      status                 TEXT    NOT NULL DEFAULT 'pending',
      fedapay_transaction_id TEXT,
      amount                 REAL    NOT NULL,
      currency               TEXT    NOT NULL DEFAULT 'XOF',
      billing_cycle          TEXT    NOT NULL DEFAULT 'monthly',
      created_at             DATETIME DEFAULT CURRENT_TIMESTAMP,
      paid_at                DATETIME
    );

    CREATE TABLE IF NOT EXISTS vps (
      id                INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id          INTEGER NOT NULL REFERENCES orders(id),
      user_id           INTEGER NOT NULL REFERENCES users(id),
      plan_id           INTEGER NOT NULL REFERENCES plans(id),
      virtualizor_vs_id TEXT,
      ip_address        TEXT,
      hostname          TEXT,
      root_password_enc TEXT,
      status            TEXT NOT NULL DEFAULT 'provisioning',
      created_at        DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  `);

  // Add ssh_port column if migrating from older schema
  try { db.prepare('ALTER TABLE vps ADD COLUMN ssh_port INTEGER').run(); } catch {}
  // Add container_ip column if migrating from older schema
  try { db.prepare('ALTER TABLE vps ADD COLUMN container_ip TEXT').run(); } catch {}

  db.exec(`
    CREATE TABLE IF NOT EXISTS ip_pool (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      ip_address      TEXT    UNIQUE NOT NULL,
      instance_id     TEXT    NOT NULL,
      status          TEXT    NOT NULL DEFAULT 'available',
      allocated_to_vps INTEGER REFERENCES vps(id),
      created_at      DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  `);

  seedAdminUser();
  seedDefaultPlans();
}

function seedAdminUser() {
  const existing = db.prepare('SELECT id FROM users WHERE email = ?').get(config.admin.email);
  if (existing) return;

  const hash = bcrypt.hashSync(config.admin.password, 10);
  db.prepare(`
    INSERT INTO users (email, password_hash, first_name, last_name, role)
    VALUES (?, ?, 'Admin', 'Principal', 'admin')
  `).run(config.admin.email, hash);

  console.log(`[DB] Admin créé : ${config.admin.email}`);
}

function seedDefaultPlans() {
  const plans = [
    {
      name: 'Freemium',
      slug: 'freemium',
      description: 'Plan d\'entrée idéal pour démarrer. Parfait pour tester vos projets.',
      vcpu: 1,
      ram_mb: 512,
      disk_gb: 5,
      bandwidth_gb: 100,
      price_monthly: 500,
      price_annually: 5000,
      virtualizor_plan_id: '0',
    },
    {
      name: 'VPS Starter',
      slug: 'starter',
      description: 'Idéal pour débuter. Parfait pour les petits sites et projets.',
      vcpu: 1,
      ram_mb: 1024,
      disk_gb: 20,
      bandwidth_gb: 1000,
      price_monthly: 3000,
      price_annually: 30000,
      virtualizor_plan_id: '1',
    },
    {
      name: 'VPS Pro',
      slug: 'pro',
      description: 'Pour les projets en croissance. Plus de puissance et de stockage.',
      vcpu: 2,
      ram_mb: 2048,
      disk_gb: 50,
      bandwidth_gb: 2000,
      price_monthly: 6000,
      price_annually: 60000,
      virtualizor_plan_id: '2',
    },
    {
      name: 'VPS Business',
      slug: 'business',
      description: 'Haute performance pour les applications critiques.',
      vcpu: 4,
      ram_mb: 4096,
      disk_gb: 100,
      bandwidth_gb: 5000,
      price_monthly: 12000,
      price_annually: 120000,
      virtualizor_plan_id: '3',
    },
  ];

  const insert = db.prepare(`
    INSERT OR IGNORE INTO plans (name, slug, description, vcpu, ram_mb, disk_gb, bandwidth_gb,
      price_monthly, price_annually, virtualizor_plan_id)
    VALUES (@name, @slug, @description, @vcpu, @ram_mb, @disk_gb, @bandwidth_gb,
      @price_monthly, @price_annually, @virtualizor_plan_id)
  `);

  let added = 0;
  plans.forEach(p => {
    const info = insert.run(p);
    if (info.changes > 0) added++;
  });

  if (added > 0) console.log(`[DB] ${added} plan(s) ajouté(s).`);
}
