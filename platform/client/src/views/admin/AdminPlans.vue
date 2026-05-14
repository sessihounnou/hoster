<template>
  <div>
    <div class="flex items-center justify-between mb-6">
      <h2 class="text-xl font-bold text-gray-900">
        <fa-icon icon="list-alt" class="text-brand-600 mr-2" />
        Plans VPS
      </h2>
      <button @click="openModal(null)" class="btn-primary">
        <fa-icon icon="plus" class="mr-2" />
        Nouveau plan
      </button>
    </div>

    <div v-if="loading" class="flex justify-center py-12">
      <fa-icon icon="spinner" class="text-3xl text-brand-500 animate-spin" />
    </div>

    <div v-else class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
      <div v-for="plan in plans" :key="plan.id"
        class="card relative"
        :class="!plan.active ? 'opacity-60' : ''">

        <div class="flex items-start justify-between mb-3">
          <div>
            <h3 class="font-bold text-gray-900">{{ plan.name }}</h3>
            <p class="text-xs text-gray-400 mt-0.5">slug: {{ plan.slug }}</p>
          </div>
          <span class="px-2 py-0.5 rounded-full text-xs font-semibold"
            :class="plan.active ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-500'">
            {{ plan.active ? 'Actif' : 'Inactif' }}
          </span>
        </div>

        <div class="grid grid-cols-2 gap-1.5 text-xs text-gray-600 mb-3">
          <span><fa-icon icon="bolt" class="text-brand-400 mr-1" />{{ plan.vcpu }} vCPU</span>
          <span><fa-icon icon="memory" class="text-brand-400 mr-1" />{{ formatRam(plan.ram_mb) }}</span>
          <span><fa-icon icon="hdd" class="text-brand-400 mr-1" />{{ plan.disk_gb }} GB</span>
          <span><fa-icon icon="network-wired" class="text-brand-400 mr-1" />{{ plan.bandwidth_gb }} GB BW</span>
        </div>

        <div class="flex items-center justify-between border-t border-gray-100 pt-3">
          <div>
            <p class="text-lg font-extrabold text-brand-800">{{ formatXof(plan.price_monthly) }}<span class="text-xs text-gray-400 font-normal">/mois</span></p>
          </div>
          <div class="flex gap-2">
            <button @click="openModal(plan)" class="p-2 text-gray-400 hover:text-brand-600 hover:bg-brand-50 rounded-lg transition">
              <fa-icon icon="edit" />
            </button>
            <button @click="toggleActive(plan)" class="p-2 rounded-lg transition"
              :class="plan.active ? 'text-red-400 hover:text-red-600 hover:bg-red-50' : 'text-green-400 hover:text-green-600 hover:bg-green-50'">
              <fa-icon :icon="plan.active ? 'times-circle' : 'check-circle'" />
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Modal création/édition -->
    <div v-if="showModal" class="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4">
      <div class="bg-white rounded-2xl w-full max-w-lg shadow-2xl max-h-screen overflow-y-auto">
        <div class="flex items-center justify-between p-6 border-b border-gray-100">
          <h3 class="font-bold text-gray-900">{{ editingPlan ? 'Modifier le plan' : 'Nouveau plan' }}</h3>
          <button @click="showModal = false" class="text-gray-400 hover:text-gray-600">
            <fa-icon icon="times" />
          </button>
        </div>

        <form @submit.prevent="savePlan" class="p-6 space-y-4">
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="block text-xs font-medium text-gray-600 mb-1">Nom du plan *</label>
              <input v-model="form.name" required class="input text-sm" placeholder="VPS Starter" />
            </div>
            <div>
              <label class="block text-xs font-medium text-gray-600 mb-1">Slug *</label>
              <input v-model="form.slug" required class="input text-sm" placeholder="starter" :disabled="!!editingPlan" />
            </div>
          </div>

          <div>
            <label class="block text-xs font-medium text-gray-600 mb-1">Description</label>
            <textarea v-model="form.description" class="input text-sm h-16 resize-none" placeholder="Description courte..."></textarea>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="block text-xs font-medium text-gray-600 mb-1">vCPU *</label>
              <input v-model.number="form.vcpu" type="number" min="1" required class="input text-sm" />
            </div>
            <div>
              <label class="block text-xs font-medium text-gray-600 mb-1">RAM (MB) *</label>
              <input v-model.number="form.ram_mb" type="number" min="256" required class="input text-sm" placeholder="1024" />
            </div>
            <div>
              <label class="block text-xs font-medium text-gray-600 mb-1">Disque (GB) *</label>
              <input v-model.number="form.disk_gb" type="number" min="1" required class="input text-sm" placeholder="20" />
            </div>
            <div>
              <label class="block text-xs font-medium text-gray-600 mb-1">Bande passante (GB) *</label>
              <input v-model.number="form.bandwidth_gb" type="number" min="1" required class="input text-sm" placeholder="1000" />
            </div>
            <div>
              <label class="block text-xs font-medium text-gray-600 mb-1">Prix mensuel (XOF) *</label>
              <input v-model.number="form.price_monthly" type="number" min="0" required class="input text-sm" placeholder="3000" />
            </div>
            <div>
              <label class="block text-xs font-medium text-gray-600 mb-1">Prix annuel (XOF)</label>
              <input v-model.number="form.price_annually" type="number" min="0" class="input text-sm" placeholder="30000" />
            </div>
          </div>

          <div>
            <label class="block text-xs font-medium text-gray-600 mb-1">ID Plan Virtualizor</label>
            <input v-model="form.virtualizor_plan_id" class="input text-sm" placeholder="1" />
          </div>

          <div v-if="modalError" class="bg-red-50 border border-red-200 text-red-600 text-sm rounded-lg px-4 py-2">
            {{ modalError }}
          </div>

          <div class="flex gap-3 pt-2">
            <button type="submit" :disabled="savingPlan" class="btn-primary flex-1 py-2.5">
              <fa-icon v-if="savingPlan" icon="spinner" class="animate-spin mr-2" />
              {{ editingPlan ? 'Enregistrer' : 'Créer le plan' }}
            </button>
            <button type="button" @click="showModal = false" class="btn-secondary flex-1 py-2.5">Annuler</button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue';
import api from '../../api.js';

const plans = ref([]);
const loading = ref(true);
const showModal = ref(false);
const editingPlan = ref(null);
const savingPlan = ref(false);
const modalError = ref('');

const form = ref({
  name: '', slug: '', description: '', vcpu: 1, ram_mb: 1024, disk_gb: 20,
  bandwidth_gb: 1000, price_monthly: 0, price_annually: null, virtualizor_plan_id: '',
});

function formatRam(mb) { return mb >= 1024 ? `${mb / 1024} GB` : `${mb} MB`; }
function formatXof(v) {
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'XOF', maximumFractionDigits: 0 }).format(v);
}

function openModal(plan) {
  editingPlan.value = plan;
  modalError.value = '';
  if (plan) {
    form.value = { ...plan };
  } else {
    form.value = { name: '', slug: '', description: '', vcpu: 1, ram_mb: 1024, disk_gb: 20,
      bandwidth_gb: 1000, price_monthly: 0, price_annually: null, virtualizor_plan_id: '' };
  }
  showModal.value = true;
}

async function savePlan() {
  savingPlan.value = true;
  modalError.value = '';
  try {
    if (editingPlan.value) {
      await api.put(`/api/plans/${editingPlan.value.id}`, form.value);
    } else {
      await api.post('/api/plans', form.value);
    }
    await fetchPlans();
    showModal.value = false;
  } catch (err) {
    modalError.value = err.response?.data?.error || 'Erreur lors de la sauvegarde.';
  } finally {
    savingPlan.value = false;
  }
}

async function toggleActive(plan) {
  await api.put(`/api/plans/${plan.id}`, { ...plan, active: plan.active ? 0 : 1 });
  plan.active = plan.active ? 0 : 1;
}

async function fetchPlans() {
  loading.value = true;
  try {
    const { data } = await api.get('/api/plans/all');
    plans.value = data.plans;
  } finally {
    loading.value = false;
  }
}

onMounted(() => fetchPlans());
</script>
