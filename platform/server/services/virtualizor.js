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
const LXD_GW = process.env.LXD_GATEWAY || '10.63.135.1';
const LXD_SUBNET = process.env.LXD_SUBNET || '10.63.135';

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

function pickContainerIp(name) {
  const hash = crypto.createHash('md5').update(name).digest('hex');
  const last = (parseInt(hash.slice(0, 2), 16) % 200) + 50; // range .50-.249
  return `${LXD_SUBNET}.${last}`;
}

function addPortForward(containerIp, sshPort) {
  try {
    execSync(`iptables -t nat -C PREROUTING -p tcp --dport ${sshPort} -j DNAT --to-destination ${containerIp}:22 2>/dev/null || iptables -t nat -A PREROUTING -p tcp --dport ${sshPort} -j DNAT --to-destination ${containerIp}:22`);
    execSync(`iptables -C FORWARD -p tcp -d ${containerIp} --dport 22 -j ACCEPT 2>/dev/null || iptables -A FORWARD -p tcp -d ${containerIp} --dport 22 -j ACCEPT`);
    execSync('iptables-save > /etc/iptables/rules.v4 2>/dev/null || iptables-save > /etc/iptables.rules 2>/dev/null || true');
  } catch (e) {
    console.warn('[LXD] iptables warning:', e.message);
  }
}

function removePortForward(containerIp, sshPort) {
  try {
    execSync(`iptables -t nat -D PREROUTING -p tcp --dport ${sshPort} -j DNAT --to-destination ${containerIp}:22 2>/dev/null || true`);
    execSync(`iptables -D FORWARD -p tcp -d ${containerIp} --dport 22 -j ACCEPT 2>/dev/null || true`);
  } catch (e) {
    console.warn('[LXD] iptables cleanup warning:', e.message);
  }
}

export async function createVps({ plan, hostname, rootpass, userEmail }) {
  const name = sanitizeName(hostname);
  const containerIp = pickContainerIp(name);
  const sshPort = pickSshPort(name);

  // Cloud-init user-data: configure static IP + SSH
  const userData = [
    '#cloud-config',
    'network:',
    '  version: 2',
    '  ethernets:',
    '    eth0:',
    '      dhcp4: false',
    `      addresses: [${containerIp}/24]`,
    `      gateway4: ${LXD_GW}`,
    '      nameservers:',
    '        addresses: [8.8.8.8, 1.1.1.1]',
    'package_update: false',
    'ssh_pwauth: true',
    'disable_root: false',
    'chpasswd:',
    '  expire: false',
    '  list: |',
    `    root:${rootpass}`,
    'runcmd:',
    '  - mkdir -p /etc/ssh/sshd_config.d',
    '  - echo -e "PermitRootLogin yes\\nPasswordAuthentication yes" > /etc/ssh/sshd_config.d/99-allow-root.conf',
    '  - systemctl restart ssh || systemctl restart sshd',
  ].join('\n');

  // Créer le container avec static IP via cloud-init
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
      'user.user-data': userData,
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

  // Attendre que cloud-init configure le réseau (static IP + SSH)
  console.log(`[LXD] Container ${name} démarré, attente cloud-init (IP: ${containerIp})...`);
  await new Promise(r => setTimeout(r, 20000));

  // Vérifier que l'IP est accessible
  let ipConfirmed = false;
  for (let i = 0; i < 6; i++) {
    try {
      const state = await lxd('GET', `/instances/${name}/state`);
      const ifaces = state.metadata?.network || {};
      for (const iface of Object.values(ifaces)) {
        const addr = iface.addresses?.find(a => a.family === 'inet' && !a.address.startsWith('127.'));
        if (addr) { ipConfirmed = true; break; }
      }
    } catch (e) {}
    if (ipConfirmed) break;
    await new Promise(r => setTimeout(r, 5000));
  }

  // Configurer le port forwarding SSH
  addPortForward(containerIp, sshPort);

  console.log(`[LXD] VPS créé: ${name} | IP: ${containerIp} | SSH port: ${sshPort}`);
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
