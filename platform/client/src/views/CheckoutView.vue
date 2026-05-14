<template>
  <div class="min-h-screen bg-gray-50 flex flex-col">
    <NavBar />
    <div class="flex-1 flex items-center justify-center px-4 py-12">
      <div class="w-full max-w-lg">

        <!-- Chargement du plan -->
        <div v-if="loadingPlan" class="text-center py-16">
          <fa-icon icon="spinner" class="text-4xl text-brand-500 animate-spin" />
        </div>

        <!-- Plan non trouvé -->
        <div v-else-if="!plan" class="card text-center py-12">
          <fa-icon icon="exclamation-triangle" class="text-4xl text-yellow-400 mb-3" />
          <p class="text-gray-600">Plan introuvable.</p>
          <router-link to="/" class="btn-primary mt-4 inline-block">Retour aux offres</router-link>
        </div>

        <!-- Récapitulatif + paiement -->
        <div v-else class="card">
          <h1 class="text-xl font-bold text-gray-900 mb-6">Récapitulatif de commande</h1>

          <!-- Résumé plan -->
          <div class="bg-brand-50 border border-brand-100 rounded-xl p-4 mb-6">
            <div class="flex justify-between items-start mb-3">
              <div>
                <h2 class="font-bold text-brand-800">{{ plan.name }}</h2>
                <p class="text-sm text-gray-500 mt-0.5">{{ plan.description }}</p>
              </div>
              <div class="text-right">
                <span class="text-2xl font-extrabold text-brand-800">{{ formatPrice(currentPrice) }}</span>
                <span class="text-gray-400 text-xs block">{{ billingCycle === 'monthly' ? '/ mois' : '/ an' }}</span>
              </div>
            </div>
            <div class="grid grid-cols-2 gap-2 text-sm text-gray-600 border-t border-brand-100 pt-3">
              <span><fa-icon icon="bolt" class="text-brand-400 mr-1" />{{ plan.vcpu }} vCPU</span>
              <span><fa-icon icon="memory" class="text-brand-400 mr-1" />{{ formatRam(plan.ram_mb) }} RAM</span>
              <span><fa-icon icon="hdd" class="text-brand-400 mr-1" />{{ plan.disk_gb }} GB SSD</span>
              <span><fa-icon icon="network-wired" class="text-brand-400 mr-1" />{{ plan.bandwidth_gb }} GB BW</span>
            </div>
          </div>

          <!-- Choix cycle de facturation -->
          <div class="mb-6">
            <p class="text-sm font-medium text-gray-700 mb-2">Cycle de facturation</p>
            <div class="flex gap-3">
              <button @click="billingCycle = 'monthly'"
                class="flex-1 py-2.5 rounded-lg border-2 text-sm font-semibold transition"
                :class="billingCycle === 'monthly' ? 'border-brand-600 bg-brand-50 text-brand-700' : 'border-gray-200 text-gray-500 hover:border-gray-300'">
                Mensuel<br>
                <span class="font-normal text-xs">{{ formatPrice(plan.price_monthly) }}/mois</span>
              </button>
              <button v-if="plan.price_annually" @click="billingCycle = 'annually'"
                class="flex-1 py-2.5 rounded-lg border-2 text-sm font-semibold transition relative"
                :class="billingCycle === 'annually' ? 'border-brand-600 bg-brand-50 text-brand-700' : 'border-gray-200 text-gray-500 hover:border-gray-300'">
                <span class="absolute -top-2 left-1/2 -translate-x-1/2 bg-green-500 text-white text-xs px-2 rounded-full">
                  -{{ savings }}%
                </span>
                Annuel<br>
                <span class="font-normal text-xs">{{ formatPrice(plan.price_annually) }}/an</span>
              </button>
            </div>
          </div>

          <!-- Erreur -->
          <div v-if="error" class="bg-red-50 border border-red-200 text-red-700 text-sm rounded-lg px-4 py-3 flex items-center gap-2 mb-4">
            <fa-icon icon="exclamation-triangle" />
            {{ error }}
          </div>

          <!-- Bouton paiement -->
          <button @click="handlePayment" :disabled="loading" class="btn-primary w-full py-3.5 text-base">
            <fa-icon v-if="loading" icon="spinner" class="animate-spin mr-2" />
            <fa-icon v-else icon="lock" class="mr-2" />
            Payer {{ formatPrice(currentPrice) }} via FedaPay
          </button>

          <p class="text-center text-xs text-gray-400 mt-3 flex items-center justify-center gap-1">
            <fa-icon icon="shield-alt" />
            Paiement sécurisé par FedaPay
          </p>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import NavBar from '../components/NavBar.vue';
import api from '../api.js';

const route = useRoute();
const plan = ref(null);
const loadingPlan = ref(true);
const loading = ref(false);
const error = ref('');
const billingCycle = ref('monthly');

const currentPrice = computed(() =>
  billingCycle.value === 'annually' ? plan.value?.price_annually : plan.value?.price_monthly
);
const savings = computed(() => {
  if (!plan.value?.price_annually) return 0;
  return Math.round((1 - plan.value.price_annually / (plan.value.price_monthly * 12)) * 100);
});

function formatPrice(xof) {
  if (!xof) return '-';
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'XOF', maximumFractionDigits: 0 }).format(xof);
}
function formatRam(mb) { return mb >= 1024 ? `${mb / 1024} GB` : `${mb} MB`; }

onMounted(async () => {
  try {
    const { data } = await api.get('/api/plans');
    plan.value = data.plans.find(p => p.id == route.params.planId) || null;
  } catch {
    plan.value = null;
  } finally {
    loadingPlan.value = false;
  }
});

async function handlePayment() {
  loading.value = true;
  error.value = '';
  try {
    const { data } = await api.post('/api/payment/initiate', {
      plan_id: plan.value.id,
      billing_cycle: billingCycle.value,
    });
    window.location.href = data.checkout_url;
  } catch (err) {
    error.value = err.response?.data?.error || 'Erreur lors de la création du paiement.';
    loading.value = false;
  }
}
</script>
