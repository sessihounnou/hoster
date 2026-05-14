import 'dotenv/config';

export default {
  port: parseInt(process.env.PORT) || 3000,
  nodeEnv: process.env.NODE_ENV || 'development',
  jwtSecret: process.env.JWT_SECRET || 'dev_secret_change_in_production',
  appUrl: process.env.APP_URL || 'http://localhost:3000',
  frontendUrl: process.env.FRONTEND_URL || 'http://localhost:5173',

  fedapay: {
    secretKey: process.env.FEDAPAY_SECRET_KEY || '',
    env: process.env.FEDAPAY_ENV || 'sandbox',
  },

  virtualizor: {
    ip: process.env.VIRTUALIZOR_IP || '127.0.0.1',
    apiKey: process.env.VIRTUALIZOR_API_KEY || '',
    apiPass: process.env.VIRTUALIZOR_API_PASS || '',
  },

  smtp: {
    host: process.env.SMTP_HOST || 'smtp.gmail.com',
    port: parseInt(process.env.SMTP_PORT) || 587,
    secure: process.env.SMTP_SECURE === 'true',
    user: process.env.SMTP_USER || '',
    pass: process.env.SMTP_PASS || '',
    from: process.env.SMTP_FROM || 'contact@monsite.com',
  },

  admin: {
    email: process.env.ADMIN_EMAIL || 'admin@monsite.com',
    password: process.env.ADMIN_PASSWORD || 'admin123',
  },

  encryptionKey: process.env.ENCRYPTION_KEY || '0000000000000000000000000000000000000000000000000000000000000000',
};
