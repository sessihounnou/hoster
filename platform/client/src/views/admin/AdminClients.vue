<template>
  <div>
    <h2 class="text-xl font-bold text-gray-900 mb-6">
      <fa-icon icon="users" class="text-brand-600 mr-2" />
      Clients
    </h2>

    <div v-if="loading" class="flex justify-center py-12">
      <fa-icon icon="spinner" class="text-3xl text-brand-500 animate-spin" />
    </div>

    <div v-else class="card overflow-x-auto">
      <div class="flex items-center justify-between mb-4">
        <input v-model="search" type="text" placeholder="Rechercher par email..."
          class="input max-w-xs text-sm" />
        <span class="text-sm text-gray-400">{{ filteredClients.length }} client(s)</span>
      </div>

      <table class="w-full text-sm">
        <thead>
          <tr class="text-left text-xs text-gray-400 border-b border-gray-100">
            <th class="pb-3 font-medium">Client</th>
            <th class="pb-3 font-medium">Email</th>
            <th class="pb-3 font-medium text-center">VPS</th>
            <th class="pb-3 font-medium text-center">Commandes</th>
            <th class="pb-3 font-medium">Inscrit le</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="client in filteredClients" :key="client.id" class="border-b border-gray-50 hover:bg-gray-50">
            <td class="py-3 font-medium text-gray-800">{{ client.first_name }} {{ client.last_name }}</td>
            <td class="py-3 text-gray-500">{{ client.email }}</td>
            <td class="py-3 text-center">
              <span class="bg-brand-100 text-brand-700 px-2 py-0.5 rounded-full text-xs font-semibold">{{ client.vps_count }}</span>
            </td>
            <td class="py-3 text-center">
              <span class="bg-gray-100 text-gray-600 px-2 py-0.5 rounded-full text-xs font-semibold">{{ client.order_count }}</span>
            </td>
            <td class="py-3 text-gray-400 text-xs">{{ formatDate(client.created_at) }}</td>
          </tr>
        </tbody>
      </table>
      <p v-if="filteredClients.length === 0" class="text-center py-8 text-gray-400">Aucun client trouvé.</p>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue';
import api from '../../api.js';

const clients = ref([]);
const loading = ref(true);
const search = ref('');

const filteredClients = computed(() =>
  clients.value.filter(c =>
    !search.value || c.email.toLowerCase().includes(search.value.toLowerCase())
  )
);
function formatDate(d) { return new Date(d).toLocaleDateString('fr-FR'); }

onMounted(async () => {
  try {
    const { data } = await api.get('/api/vps/clients');
    clients.value = data.clients;
  } finally {
    loading.value = false;
  }
});
</script>
