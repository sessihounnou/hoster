<template>
  <div>
    <h2 class="text-xl font-bold text-gray-900 mb-6">
      <fa-icon icon="database" class="text-brand-600 mr-2" />
      Commandes
    </h2>

    <div v-if="loading" class="flex justify-center py-12">
      <fa-icon icon="spinner" class="text-3xl text-brand-500 animate-spin" />
    </div>

    <div v-else class="card overflow-x-auto">
      <!-- Filtres -->
      <div class="flex flex-wrap gap-2 mb-5">
        <button v-for="s in statuses" :key="s.value"
          @click="filterStatus = s.value"
          class="px-3 py-1.5 rounded-lg text-xs font-semibold transition"
          :class="filterStatus === s.value ? 'bg-brand-600 text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'">
          {{ s.label }} ({{ countByStatus(s.value) }})
        </button>
      </div>

      <table class="w-full text-sm">
        <thead>
          <tr class="text-left text-xs text-gray-400 border-b border-gray-100">
            <th class="pb-3 font-medium">#</th>
            <th class="pb-3 font-medium">Client</th>
            <th class="pb-3 font-medium">Plan</th>
            <th class="pb-3 font-medium">Montant</th>
            <th class="pb-3 font-medium">Cycle</th>
            <th class="pb-3 font-medium">Statut</th>
            <th class="pb-3 font-medium">Date</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="order in filteredOrders" :key="order.id" class="border-b border-gray-50 hover:bg-gray-50">
            <td class="py-3 text-gray-400 font-mono text-xs">#{{ order.id }}</td>
            <td class="py-3">
              <div class="text-gray-800 font-medium text-xs">{{ order.first_name }} {{ order.last_name }}</div>
              <div class="text-gray-400 text-xs">{{ order.user_email }}</div>
            </td>
            <td class="py-3 text-gray-600">{{ order.plan_name }}</td>
            <td class="py-3 font-semibold text-gray-800">{{ formatXof(order.amount) }}</td>
            <td class="py-3">
              <span class="bg-gray-100 text-gray-600 px-2 py-0.5 rounded text-xs">{{ order.billing_cycle }}</span>
            </td>
            <td class="py-3">
              <span class="px-2 py-0.5 rounded-full text-xs font-semibold" :class="statusClass(order.status)">
                {{ order.status }}
              </span>
            </td>
            <td class="py-3 text-gray-400 text-xs">{{ formatDate(order.created_at) }}</td>
          </tr>
        </tbody>
      </table>
      <p v-if="filteredOrders.length === 0" class="text-center py-8 text-gray-400">Aucune commande trouvée.</p>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue';
import api from '../../api.js';

const orders = ref([]);
const loading = ref(true);
const filterStatus = ref('all');

const statuses = [
  { value: 'all',          label: 'Toutes' },
  { value: 'active',       label: 'Actives' },
  { value: 'pending',      label: 'En attente' },
  { value: 'provisioning', label: 'En création' },
  { value: 'cancelled',    label: 'Annulées' },
];

const filteredOrders = computed(() =>
  filterStatus.value === 'all' ? orders.value : orders.value.filter(o => o.status === filterStatus.value)
);

function countByStatus(s) {
  return s === 'all' ? orders.value.length : orders.value.filter(o => o.status === s).length;
}

function statusClass(s) {
  const m = { active: 'bg-green-100 text-green-700', pending: 'bg-yellow-100 text-yellow-700',
              provisioning: 'bg-blue-100 text-blue-700', cancelled: 'bg-red-100 text-red-600', paid: 'bg-indigo-100 text-indigo-700' };
  return m[s] || 'bg-gray-100 text-gray-600';
}

function formatXof(v) {
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'XOF', maximumFractionDigits: 0 }).format(v);
}
function formatDate(d) { return new Date(d).toLocaleDateString('fr-FR'); }

onMounted(async () => {
  try {
    const { data } = await api.get('/api/orders/all');
    orders.value = data.orders;
  } finally {
    loading.value = false;
  }
});
</script>
