<template>
  <div class="min-h-screen bg-gray-50 flex flex-col">
    <NavBar />
    <div class="flex-1 max-w-6xl mx-auto w-full px-4 py-10">

      <!-- En-tête -->
      <div class="flex items-center justify-between mb-8">
        <div>
          <h1 class="text-2xl font-bold text-gray-900">
            <fa-icon icon="tachometer-alt" class="text-brand-600 mr-2" />
            Mon espace
          </h1>
          <p class="text-gray-500 text-sm mt-1">Bonjour {{ auth.user?.first_name }}, voici vos serveurs.</p>
        </div>
        <router-link to="/" class="btn-primary">
          <fa-icon icon="plus" class="mr-2" />
          Commander un VPS
        </router-link>
      </div>

      <!-- Message de succès après paiement -->
      <div v-if="route.query.status === 'success'" class="bg-green-50 border border-green-200 text-green-700 rounded-xl px-5 py-4 mb-6 flex items-center gap-3">
        <fa-icon icon="check-circle" class="text-xl flex-shrink-0" />
        <div>
          <p class="font-semibold">Paiement confirmé !</p>
          <p class="text-sm">Votre VPS est en cours de création. Vous recevrez un email avec vos credentials dans quelques minutes.</p>
        </div>
      </div>

      <!-- Chargement -->
      <div v-if="loading" class="flex justify-center py-20">
        <fa-icon icon="spinner" class="text-4xl text-brand-500 animate-spin" />
      </div>

      <!-- Aucun VPS -->
      <div v-else-if="vpsList.length === 0" class="card text-center py-16">
        <fa-icon icon="server" class="text-5xl text-gray-200 mb-4" />
        <h2 class="text-lg font-semibold text-gray-600 mb-2">Aucun VPS actif</h2>
        <p class="text-gray-400 text-sm mb-6">Commandez votre premier serveur virtuel dès maintenant.</p>
        <router-link to="/" class="btn-primary inline-flex items-center gap-2">
          <fa-icon icon="plus" />
          Voir les offres
        </router-link>
      </div>

      <!-- Liste des VPS -->
      <div v-else class="grid grid-cols-1 md:grid-cols-2 gap-5">
        <div v-for="vps in vpsList" :key="vps.id" class="card">
          <div class="flex items-start justify-between mb-4">
            <div class="flex items-center gap-3">
              <div class="w-10 h-10 bg-brand-100 rounded-xl flex items-center justify-center">
                <fa-icon icon="server" class="text-brand-600" />
              </div>
              <div>
                <h3 class="font-bold text-gray-900 text-sm">{{ vps.hostname }}</h3>
                <p class="text-xs text-gray-400">{{ vps.plan_name }}</p>
              </div>
            </div>
            <VpsStatusBadge :status="vps.status" />
          </div>

          <!-- Specs -->
          <div class="grid grid-cols-2 gap-2 text-xs text-gray-500 mb-4">
            <span class="flex items-center gap-1"><fa-icon icon="bolt" class="text-brand-400" />{{ vps.vcpu }} vCPU</span>
            <span class="flex items-center gap-1"><fa-icon icon="memory" class="text-brand-400" />{{ formatRam(vps.ram_mb) }} RAM</span>
            <span class="flex items-center gap-1"><fa-icon icon="hdd" class="text-brand-400" />{{ vps.disk_gb }} GB SSD</span>
            <span class="flex items-center gap-1"><fa-icon icon="network-wired" class="text-brand-400" />{{ vps.bandwidth_gb }} GB BW</span>
          </div>

          <!-- IP + credentials -->
          <div v-if="vps.status === 'active'" class="bg-gray-50 rounded-lg p-3 mb-4 font-mono text-sm">
            <div class="flex items-center justify-between">
              <span class="text-gray-500 text-xs">Adresse IP</span>
              <button @click="copyText(vps.ip_address)" class="text-brand-500 hover:text-brand-700 text-xs flex items-center gap-1">
                <fa-icon :icon="copied[vps.id + '_ip'] ? 'check' : 'copy'" />
                {{ copied[vps.id + '_ip'] ? 'Copié' : 'Copier' }}
              </button>
            </div>
            <p class="text-gray-800 font-medium">{{ vps.ip_address }}</p>
          </div>

          <!-- Bouton afficher credentials -->
          <div v-if="vps.status === 'active'" class="mb-4">
            <button @click="toggleCredentials(vps.id)"
              class="text-sm text-brand-600 hover:text-brand-800 flex items-center gap-1.5">
              <fa-icon :icon="showCreds[vps.id] ? 'eye-slash' : 'eye'" />
              {{ showCreds[vps.id] ? 'Masquer' : 'Afficher' }} les credentials SSH
            </button>

            <div v-if="showCreds[vps.id] && credentials[vps.id]" class="mt-2 bg-gray-900 text-green-400 rounded-lg p-3 font-mono text-xs">
              <p>ssh {{ credentials[vps.id].username }}@{{ credentials[vps.id].ip }}</p>
              <div class="flex items-center justify-between mt-1">
                <p class="text-yellow-300">Mot de passe : {{ credentials[vps.id].password }}</p>
                <button @click="copyText(credentials[vps.id].password)" class="text-gray-400 hover:text-white ml-2">
                  <fa-icon :icon="copied[vps.id + '_pass'] ? 'check' : 'copy'" />
                </button>
              </div>
            </div>
          </div>

          <!-- Actions -->
          <div class="flex gap-2 border-t border-gray-100 pt-3">
            <button v-if="vps.status === 'active'" @click="stopVps(vps)"
              class="flex-1 text-xs py-2 bg-yellow-50 hover:bg-yellow-100 text-yellow-700 rounded-lg transition flex items-center justify-center gap-1">
              <fa-icon icon="pause" />
              Arrêter
            </button>
            <button v-if="vps.status === 'suspended'" @click="startVps(vps)"
              class="flex-1 text-xs py-2 bg-green-50 hover:bg-green-100 text-green-700 rounded-lg transition flex items-center justify-center gap-1">
              <fa-icon icon="play" />
              Démarrer
            </button>
            <span class="text-xs text-gray-400 flex items-center">
              Créé le {{ formatDate(vps.created_at) }}
            </span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, reactive } from 'vue';
import { useRoute } from 'vue-router';
import NavBar from '../components/NavBar.vue';
import VpsStatusBadge from '../components/VpsStatusBadge.vue';
import { useAuthStore } from '../stores/auth.js';
import api from '../api.js';

const auth = useAuthStore();
const route = useRoute();
const vpsList = ref([]);
const loading = ref(true);
const showCreds = reactive({});
const credentials = reactive({});
const copied = reactive({});

function formatRam(mb) { return mb >= 1024 ? `${mb / 1024} GB` : `${mb} MB`; }
function formatDate(d) { return new Date(d).toLocaleDateString('fr-FR'); }

async function fetchVps() {
  loading.value = true;
  try {
    const { data } = await api.get('/api/vps');
    vpsList.value = data.vps;
  } finally {
    loading.value = false;
  }
}

async function toggleCredentials(vpsId) {
  showCreds[vpsId] = !showCreds[vpsId];
  if (showCreds[vpsId] && !credentials[vpsId]) {
    try {
      const { data } = await api.get(`/api/vps/${vpsId}/credentials`);
      credentials[vpsId] = data;
    } catch {
      showCreds[vpsId] = false;
    }
  }
}

function copyText(text) {
  navigator.clipboard.writeText(text);
}

async function stopVps(vps) {
  if (!confirm(`Arrêter ${vps.hostname} ?`)) return;
  try {
    await api.post(`/api/vps/${vps.id}/stop`);
    vps.status = 'suspended';
  } catch {}
}

async function startVps(vps) {
  try {
    await api.post(`/api/vps/${vps.id}/start`);
    vps.status = 'active';
  } catch {}
}

onMounted(() => fetchVps());
</script>
