import axios from 'axios';
import crypto from 'crypto';
import { execSync } from 'child_process';

const LXD_SOCKET = '/var/snap/lxd/common/lxd/unix.socket';
const LXD_IMAGE_SOURCE = {
  type: 'image',
  server: 'https://cloud-images.ubuntu.com/releases/',
  protocol: 'simplestreams',
  alias: '22.04',
};
const PUBLIC_IP = process.env.SERVER_PUBLIC_IP || '212.47.78.8';

async function lxd(method, path, data = null) {
  const opts = {
    method,
    url: `http://localhost/1.0${path}`,
    socketPath: LXD_SOCKET,
    timeout: 300000,
  };
  if (data) {
    opts.data = data;
    opts.headers = { 'Content-Type': 'application/json' };
  }
  const res = await axios(opts);
  return res.data;
}

async function waitOperation(opPath) {
  await lxd('GET', `${opPath}/wait?timeout=300`);
}

function sanitizeName(hostname) {
  return hostname.replace(/[^a-zA-Z0-9-]/g, '-').slice(0, 63).toLowerCase();
}

function pickSshPort(name) {
  const hash = crypto.createHash('md5').update(name).digest('hex');
  return 20000 + (parseInt(hash.slice(0, 4), 16) % 9000);
}

function addPortForward(containerIp, sshPort) {
  try {
    execSync(`iptables -t nat -C PREROUTING -p tcp --dport ${sshPort} -j DNAT --to-destination ${containerIp}:22 2>/dev/null || iptables -t nat -A PREROUTING -p tcp --dport ${sshPort} -j DNAT --to-destination ${containerIp}:22`);
    execSync(`iptables -C FORWARD -p tcp -d ${containerIp} --dport 22 -j ACCEPT 2>/dev/null || iptables -A FORWARD -p tcp -d ${containerIp} --dport 22 -j ACCEPT`);
    execSync('iptables-save > /etc/iptables/rules.v4 2>/dev/null || true');
  } catch (e) {
    console.warn('[LXD] iptables warning:', e.message);
  }
}

function removePortForward(containerIp, sshPort) {
  try {
    execSync(`iptables -t nat -D PREROUTING -p tcp --dport ${sshPort} -j DNAT --to-destination ${containerIp}:22 2>/dev/null || true`);
    execSync(`iptables -D FORWARD -p tcp -d ${containerIp} --dport 22 -j ACCEPT 2>/dev/null || true`);
    execSync('iptables-save > /etc/iptables/rules.v4 2>/dev/null || true');
  } catch (e) {
    console.warn('[LXD] iptables cleanup warning:', e.message);
  }
}

export async function createVps({ plan, hostname, rootpass, userEmail }) {
  const name = sanitizeName(hostname);
  const sshPort = pickSshPort(name);

  // Créer le container
  const create = await lxd('POST', '/instances', {
    name,
    architecture: 'x86_64',
    profiles: ['default'],
    source: LXD_IMAGE_SOURCE,
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

  if (create.error_code && create.error_code >= 400) {
    throw new Error(`Création container échouée: ${create.error}`);
  }
  if (create.metadata?.id) await waitOperation(`/operations/${create.metadata.id}`);

  // Démarrer le container
  const start = await lxd('PUT', `/instances/${name}/state`, {
    action: 'start', timeout: 60, force: false,
  });
  if (start.metadata?.id) await waitOperation(`/operations/${start.metadata.id}`);

  // Attendre que le container soit prêt et réseau disponible
  await new Promise(r => setTimeout(r, 8000));

  // Récupérer l'IP du container
  let containerIp = '';
  for (let i = 0; i < 10; i++) {
    try {
      const state = await lxd('GET', `/instances/${name}/state`);
      const ifaces = state.metadata?.network || {};
      for (const iface of Object.values(ifaces)) {
        const addr = iface.addresses?.find(a => a.family === 'inet' && !a.address.startsWith('127.'));
        if (addr) { containerIp = addr.address; break; }
      }
    } catch (e) {}
    if (containerIp) break;
    await new Promise(r => setTimeout(r, 2000));
  }

  if (!containerIp) throw new Error('Impossible d\'obtenir l\'IP du container LXD');

  // Configurer SSH et mot de passe root
  try {
    const execRes = await lxd('POST', `/instances/${name}/exec`, {
      command: ['sh', '-c', [
        `echo "root:${rootpass}" | chpasswd`,
        'mkdir -p /etc/ssh/sshd_config.d',
        'echo -e "PermitRootLogin yes\\nPasswordAuthentication yes" > /etc/ssh/sshd_config.d/99-allow-root.conf',
        'systemctl enable ssh 2>/dev/null; systemctl restart ssh 2>/dev/null',
        'systemctl enable openssh-server 2>/dev/null; systemctl restart openssh-server 2>/dev/null',
      ].join(' && ')],
      environment: { DEBIAN_FRONTEND: 'noninteractive' },
      'wait-for-websocket': false,
      interactive: false,
    });
    if (execRes.metadata?.id) await waitOperation(`/operations/${execRes.metadata.id}`);
  } catch (e) {
    console.warn('[LXD] SSH config warning:', e.message);
  }

  // Configurer le port forwarding SSH
  addPortForward(containerIp, sshPort);

  return {
    vs_id: name,
    ip: PUBLIC_IP,
    ssh_port: sshPort,
    container_ip: containerIp,
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

export async function deleteVps(vsId, containerIp, sshPort) {
  try {
    if (containerIp && sshPort) removePortForward(containerIp, sshPort);
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
