import axios from 'axios';
import crypto from 'crypto';
import { execSync } from 'child_process';

const LXD_SOCKET = '/var/snap/lxd/common/lxd/unix.socket';
const LXD_IMAGE = 'ubuntu:22.04';

async function lxd(method, path, data = null) {
  const opts = {
    method,
    url: `http://localhost/1.0${path}`,
    socketPath: LXD_SOCKET,
    timeout: 60000,
  };
  if (data) {
    opts.data = data;
    opts.headers = { 'Content-Type': 'application/json' };
  }
  const res = await axios(opts);
  return res.data;
}

async function waitOperation(opUrl) {
  await lxd('GET', opUrl.replace('/1.0', '') + '/wait?timeout=60');
}

function sanitizeName(hostname) {
  return hostname.replace(/[^a-zA-Z0-9-]/g, '-').slice(0, 63).toLowerCase();
}

function pickIp(name) {
  // Attribuer une IP depuis le sous-réseau LXD (10.50.x.x)
  const hash = crypto.createHash('md5').update(name).digest('hex');
  const b3 = (parseInt(hash.slice(0, 2), 16) % 254) + 1;
  const b4 = (parseInt(hash.slice(2, 4), 16) % 254) + 1;
  return `10.50.${b3}.${b4}`;
}

export async function createVps({ plan, hostname, rootpass, userEmail }) {
  const name = sanitizeName(hostname);
  const ip = pickIp(name);

  // Créer le container
  const create = await lxd('POST', '/instances', {
    name,
    architecture: 'x86_64',
    profiles: ['default'],
    source: { type: 'image', alias: LXD_IMAGE },
    config: {
      'limits.cpu': String(plan.vcpu),
      'limits.memory': `${plan.ram_mb}MB`,
      'user.hostname': hostname,
      'user.email': userEmail,
    },
    devices: {
      root: {
        type: 'disk',
        path: '/',
        pool: 'default',
        size: `${plan.disk_gb}GB`,
      },
    },
  });

  if (create.metadata?.status_code >= 400) {
    throw new Error(`Création container échouée: ${JSON.stringify(create)}`);
  }
  if (create.metadata?.id) await waitOperation(`/operations/${create.metadata.id}`);

  // Démarrer le container
  const start = await lxd('PUT', `/instances/${name}/state`, {
    action: 'start', timeout: 30, force: false,
  });
  if (start.metadata?.id) await waitOperation(`/operations/${start.metadata.id}`);

  // Attendre que le container soit prêt
  await new Promise(r => setTimeout(r, 5000));

  // Définir le mot de passe root via exec
  try {
    await lxd('POST', `/instances/${name}/exec`, {
      command: ['sh', '-c', `echo "root:${rootpass}" | chpasswd && echo "PermitRootLogin yes" >> /etc/ssh/sshd_config && service ssh restart 2>/dev/null || service sshd restart 2>/dev/null`],
      environment: {},
      'wait-for-websocket': false,
      interactive: false,
    });
  } catch (e) {
    console.warn('[LXD] Exec warning:', e.message);
  }

  // Récupérer l'IP du container
  await new Promise(r => setTimeout(r, 3000));
  let containerIp = '';
  try {
    const state = await lxd('GET', `/instances/${name}/state`);
    const ifaces = state.metadata?.network || {};
    for (const iface of Object.values(ifaces)) {
      const addr = iface.addresses?.find(a => a.family === 'inet' && a.address !== '127.0.0.1');
      if (addr) { containerIp = addr.address; break; }
    }
  } catch (e) {}

  return {
    vs_id: name,
    ip: containerIp || ip,
  };
}

export async function getVpsInfo(vsId) {
  try {
    const res = await lxd('GET', `/instances/${vsId}/state`);
    return res.metadata || {};
  } catch { return {}; }
}

export async function stopVps(vsId) {
  try {
    const res = await lxd('PUT', `/instances/${vsId}/state`, {
      action: 'stop', timeout: 30, force: true,
    });
    if (res.metadata?.id) await waitOperation(`/operations/${res.metadata.id}`);
    return true;
  } catch { return false; }
}

export async function startVps(vsId) {
  try {
    const res = await lxd('PUT', `/instances/${vsId}/state`, {
      action: 'start', timeout: 30,
    });
    if (res.metadata?.id) await waitOperation(`/operations/${res.metadata.id}`);
    return true;
  } catch { return false; }
}

export async function deleteVps(vsId) {
  try {
    await stopVps(vsId);
    await lxd('DELETE', `/instances/${vsId}`);
    return true;
  } catch { return false; }
}

export async function listVps() {
  try {
    const res = await lxd('GET', '/instances');
    return res.metadata || [];
  } catch { return []; }
}
