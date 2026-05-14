import nodemailer from 'nodemailer';
import config from '../config.js';

const transporter = nodemailer.createTransport({
  host: config.smtp.host,
  port: config.smtp.port,
  secure: config.smtp.secure,
  auth: {
    user: config.smtp.user,
    pass: config.smtp.pass,
  },
});

function credentialsTemplate({ user, vps, plan }) {
  return `
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <style>
    body { font-family: Arial, sans-serif; background: #f4f6f9; margin: 0; padding: 20px; }
    .container { max-width: 600px; margin: 0 auto; background: #ffffff; border-radius: 8px; overflow: hidden; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
    .header { background: #1e3a5f; color: white; padding: 30px; text-align: center; }
    .header h1 { margin: 0; font-size: 24px; }
    .header p { margin: 8px 0 0; opacity: 0.85; }
    .body { padding: 30px; }
    .greeting { font-size: 16px; color: #333; margin-bottom: 20px; }
    .info-box { background: #f0f4f8; border-left: 4px solid #1e3a5f; border-radius: 4px; padding: 20px; margin: 20px 0; }
    .info-row { display: flex; margin: 8px 0; }
    .info-label { font-weight: bold; color: #555; min-width: 160px; }
    .info-value { color: #111; font-family: monospace; background: #e8ecf0; padding: 2px 8px; border-radius: 3px; }
    .cta { text-align: center; margin: 30px 0; }
    .cta a { background: #1e3a5f; color: white; text-decoration: none; padding: 12px 28px; border-radius: 6px; font-size: 15px; }
    .notice { background: #fff3cd; border: 1px solid #ffc107; border-radius: 4px; padding: 12px 16px; font-size: 13px; color: #856404; margin-top: 20px; }
    .footer { text-align: center; padding: 20px; color: #999; font-size: 12px; border-top: 1px solid #eee; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>Votre VPS est prêt !</h1>
      <p>Plan ${plan.name} — Provisioning terminé</p>
    </div>
    <div class="body">
      <p class="greeting">Bonjour <strong>${user.first_name} ${user.last_name}</strong>,</p>
      <p>Votre serveur virtuel a été créé avec succès. Voici vos informations de connexion :</p>

      <div class="info-box">
        <div class="info-row">
          <span class="info-label">Adresse IP :</span>
          <span class="info-value">${vps.ip_address}</span>
        </div>
        <div class="info-row">
          <span class="info-label">Hostname :</span>
          <span class="info-value">${vps.hostname}</span>
        </div>
        <div class="info-row">
          <span class="info-label">Utilisateur SSH :</span>
          <span class="info-value">root</span>
        </div>
        <div class="info-row">
          <span class="info-label">Mot de passe SSH :</span>
          <span class="info-value">${vps.root_password}</span>
        </div>
        <div class="info-row">
          <span class="info-label">Plan :</span>
          <span class="info-value">${plan.vcpu} vCPU / ${plan.ram_mb >= 1024 ? plan.ram_mb / 1024 + ' GB' : plan.ram_mb + ' MB'} RAM / ${plan.disk_gb} GB SSD</span>
        </div>
      </div>

      <p>Pour vous connecter en SSH :</p>
      <div class="info-box">
        <span class="info-value">ssh root@${vps.ip_address}</span>
      </div>

      <div class="cta">
        <a href="${config.frontendUrl}/dashboard">Accéder à mon espace client</a>
      </div>

      <div class="notice">
        <strong>Important :</strong> Changez votre mot de passe root dès la première connexion avec la commande <code>passwd</code>. Conservez ces informations en lieu sûr.
      </div>
    </div>
    <div class="footer">
      Cet email a été envoyé automatiquement. Ne pas répondre directement.<br>
      &copy; ${new Date().getFullYear()} Mon Hébergeur VPS. Tous droits réservés.
    </div>
  </div>
</body>
</html>
  `.trim();
}

export async function sendCredentials({ user, vps, plan }) {
  const html = credentialsTemplate({ user, vps, plan });

  await transporter.sendMail({
    from: config.smtp.from,
    to: user.email,
    subject: `[VPS Prêt] Vos accès pour ${vps.hostname} — ${plan.name}`,
    html,
    text: `
Votre VPS est prêt !

Plan : ${plan.name}
IP : ${vps.ip_address}
Hostname : ${vps.hostname}
Utilisateur : root
Mot de passe : ${vps.root_password}

Connexion SSH : ssh root@${vps.ip_address}

Espace client : ${config.frontendUrl}/dashboard

Changez votre mot de passe dès la première connexion.
    `.trim(),
  });
}

export async function sendWelcome({ user }) {
  await transporter.sendMail({
    from: config.smtp.from,
    to: user.email,
    subject: 'Bienvenue sur votre espace client VPS',
    html: `
      <p>Bonjour <strong>${user.first_name}</strong>,</p>
      <p>Votre compte a été créé avec succès.</p>
      <p><a href="${config.frontendUrl}/dashboard">Accéder à mon espace client</a></p>
    `,
  });
}
