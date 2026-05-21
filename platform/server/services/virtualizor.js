import axios from 'axios';
import crypto from 'crypto';
import config from '../config.js';

const BASE_URL = `http://${config.virtualizor.ip}:4082/index.php`;

function buildApiUrl(act, extraParams = {}) {
  const timestamp = Math.floor(Date.now() / 1000);
  const signature = crypto
    .createHash('md5')
    .update(config.virtualizor.apiKey + config.virtualizor.apiPass + timestamp)
    .digest('hex');

  const params = new URLSearchParams({
    act,
    apikey: config.virtualizor.apiKey,
    timestamp,
    signature,
    api: 'json',
    ...extraParams,
  });

  return `${BASE_URL}?${params.toString()}`;
}

async function apiCall(act, data = {}) {
  const url = buildApiUrl(act);
  const response = await axios.post(url, new URLSearchParams({ ...data, api: 'json' }).toString(), {
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    timeout: 30000,
  });
  return response.data;
}

export async function createVps({ plan, hostname, rootpass, userEmail }) {
  const data = {
    virt_type: 'lxc',
    node_id: 0,
    hostname,
    rootpass,
    user_email: userEmail,
    user_pass: rootpass,
    plid: plan.virtualizor_plan_id || '1',
    os_id: 1248, // Ubuntu 22.04 — à ajuster selon les OS installés dans Virtualizor
    bandwidth: plan.bandwidth_gb * 1024, // en MB
    disk_space: plan.disk_gb * 1024,     // en MB
    ram: plan.ram_mb,
    cores: plan.vcpu,
    network_speed: 100,
  };

  const result = await apiCall('addvs', data);

  if (!result.done) {
    throw new Error(`Échec création VPS: ${JSON.stringify(result.error || result)}`);
  }

  return {
    vs_id: result.done?.toString() || result.vpsid?.toString(),
    ip: result.vs_info?.ip?.[0] || '',
  };
}

export async function getVpsInfo(vsId) {
  const result = await apiCall('vpsdetails', { svs: vsId });
  return result.info || result.vs_info || {};
}

export async function stopVps(vsId) {
  const result = await apiCall('stopvs', { svs: vsId });
  return !!result.done;
}

export async function startVps(vsId) {
  const result = await apiCall('startvs', { svs: vsId });
  return !!result.done;
}

export async function deleteVps(vsId) {
  const result = await apiCall('deletevs', { svs: vsId });
  return !!result.done;
}

export async function listVps(userId = null) {
  const params = userId ? { uid: userId } : {};
  const result = await apiCall('listvs', params);
  return result.vs || {};
}
