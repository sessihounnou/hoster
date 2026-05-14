<template>
  <div>
    <h2 class="text-xl font-bold text-gray-900 mb-6">Tableau de bord</h2>

    <!-- Statistiques -->
    <div v-if="loading" class="flex justify-center py-12">
      <fa-icon icon="spinner" class="text-3xl text-brand-500 animate-spin" />
    </div>

    <div v-else class="grid grid-cols-2 lg:grid-cols-3 gap-4 mb-8">
      <div v-for="stat in statCards" :key="stat.label" class="card">
        <div class="flex items-center justify-between mb-2">
          <span class="text-sm text-gray-500">{{ stat.label }}</span>
          <div class="w-8 h-8 rounded-lg flex items-center justify-center" :class="stat.bg">
            <fa-icon :icon="stat.icon" class="text-sm" :class="stat.color" />
          </div>
        </div>
        <p class="text-2xl font-extrabold text-gray-900">{{ stat.value }}</p>
      </div>
    </div>

    <!-- VPS récents -->
    <div class="card">
      <div class="flex items-center justify-between mb-4">
        <h3 class="font-bold text-gray-900">VPS récents</h3>
        <router-link to="/admin/orders" class="text-sm text-brand-600 hover:underline">Voir tout</router-link>
      </div>
      <div v-if="recentVps.length === 0" class="text-center py-8 text-gray-400 text-sm">
        Aucun VPS créé pour le moment.
      </div>
      <div v-else class="overflow-x-auto">
        <table class="w-full text-sm">
          <thead>
            <tr class="text-left text-xs text-gray-400 border-b border-gray-100">
              <th class="pb-3 font-medium">Client</th>
              <th class="pb-3 font-medium">Hostname</th>
              <th class="pb-3 font-medium">IP</th>
              <th class="pb-3 font-medium">Plan</th>
              <th class="pb-3 font-medium">Statut</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="vps in recentVps" :key="vps.id" class="border-b border-gray-50 hover:bg-gray-50">
              <td class="py-3 text-gray-700">{{ vps.user_email }}</td>
              <td class="py-3 font-mono text-xs text-gray-600">{{ vps.hostname }}</td>
              <td class="py-3 font-mono text-xs text-brand-600">{{ vps.ip_address }}</td>
              <td class="py-3 text-gray-600">{{ vps.plan_name }}</td>
              <td class="py-3"><VpsStatusBadge :status="vps.status" /></td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue';
import VpsStatusBadge from '../../components/VpsStatusBadge.vue';
import api from '../../api.js';

const loading = ref(true);
const stats = ref({});
const recentVps = ref([]);

const statCards = computed(() => [
  { label: 'Clients total',     value: stats.value.total_clients  || 0, icon: 'users',        bg: 'bg-blue-100',   color: 'text-blue-600' },
  { label: 'VPS actifs',        value: stats.value.total_vps      || 0, icon: 'server',       bg: 'bg-green-100',  color: 'text-green-600' },
  { label: 'Commandes actives', value: stats.value.active_orders  || 0, icon: 'check-circle', bg: 'bg-indigo-100', color: 'text-indigo-600' },
  { label: 'En attente',        value: stats.value.pending_orders || 0, icon: 'spinner',      bg: 'bg-yellow-100', color: 'text-yellow-600' },
  { label: 'Revenus totaux',    value: formatXof(stats.value.total_revenue || 0), icon: 'database', bg: 'bg-purple-100', color: 'text-purple-600' },
  { label: 'Commandes totales', value: stats.value.total_orders   || 0, icon: 'list-alt',    bg: 'bg-gray-100',   color: 'text-gray-600' },
]);

function formatXof(v) {
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'XOF', maximumFractionDigits: 0 }).format(v);
}

onMounted(async () => {
  try {
    const [statsRes, vpsRes] = await Promise.all([
      api.get('/api/orders/stats'),
      api.get('/api/vps/all'),
    ]);
    stats.value = statsRes.data.stats;
    recentVps.value = vpsRes.data.vps.slice(0, 8);
  } finally {
    loading.value = false;
  }
});
</script>
