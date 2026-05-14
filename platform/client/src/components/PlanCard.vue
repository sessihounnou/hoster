<template>
  <div class="bg-white rounded-2xl border-2 transition-all duration-300 hover:shadow-xl hover:-translate-y-1"
       :class="isFree ? 'border-green-300 shadow-green-100 shadow-sm'
              : featured ? 'border-brand-600 shadow-lg shadow-brand-100'
              : 'border-gray-100 shadow-sm'">

    <!-- Badge -->
    <div v-if="isFree" class="bg-green-500 text-white text-xs font-bold text-center py-1.5 rounded-t-xl tracking-wider uppercase">
      <fa-icon icon="bolt" class="mr-1" /> Gratuit 30 jours — Sans carte
    </div>
    <div v-else-if="featured" class="bg-brand-600 text-white text-xs font-bold text-center py-1.5 rounded-t-xl tracking-wider uppercase">
      <fa-icon icon="bolt" class="mr-1" /> Le plus populaire
    </div>

    <div class="p-6">
      <!-- Nom + prix -->
      <div class="mb-5">
        <h3 class="text-xl font-bold text-gray-900">{{ plan.name }}</h3>
        <p class="text-gray-500 text-sm mt-1">{{ plan.description }}</p>
        <div class="mt-4 flex items-baseline gap-1">
          <span v-if="isFree" class="text-3xl font-extrabold text-green-600">Gratuit</span>
          <template v-else>
            <span class="text-3xl font-extrabold text-brand-800">{{ formatPrice(plan.price_monthly) }}</span>
            <span class="text-gray-400 text-sm">/ mois</span>
          </template>
        </div>
        <p v-if="isFree" class="text-xs text-green-600 mt-1">
          <fa-icon icon="check-circle" /> 30 jours offerts · aucune carte requise
        </p>
        <p v-else-if="plan.price_annually" class="text-xs text-green-600 mt-1">
          <fa-icon icon="check-circle" /> {{ formatPrice(plan.price_annually) }} / an (économisez {{ savings }}%)
        </p>
      </div>

      <!-- Specs -->
      <ul class="space-y-2.5 mb-6">
        <li class="flex items-center gap-2.5 text-sm text-gray-600">
          <fa-icon icon="bolt" class="text-brand-500 w-4" />
          <span><strong class="text-gray-800">{{ plan.vcpu }}</strong> vCPU</span>
        </li>
        <li class="flex items-center gap-2.5 text-sm text-gray-600">
          <fa-icon icon="memory" class="text-brand-500 w-4" />
          <span><strong class="text-gray-800">{{ formatRam(plan.ram_mb) }}</strong> RAM</span>
        </li>
        <li class="flex items-center gap-2.5 text-sm text-gray-600">
          <fa-icon icon="hdd" class="text-brand-500 w-4" />
          <span><strong class="text-gray-800">{{ plan.disk_gb }} GB</strong> SSD NVMe</span>
        </li>
        <li class="flex items-center gap-2.5 text-sm text-gray-600">
          <fa-icon icon="network-wired" class="text-brand-500 w-4" />
          <span><strong class="text-gray-800">{{ formatBw(plan.bandwidth_gb) }}</strong> bande passante</span>
        </li>
        <li class="flex items-center gap-2.5 text-sm text-gray-600">
          <fa-icon icon="shield-alt" class="text-brand-500 w-4" />
          <span>Protection DDoS incluse</span>
        </li>
      </ul>

      <!-- CTA -->
      <router-link :to="auth.isLoggedIn ? `/checkout/${plan.id}` : '/register'" class="block">
        <button class="w-full py-3 rounded-xl font-semibold text-sm transition-all duration-200"
                :class="isFree
                  ? 'bg-green-500 hover:bg-green-600 text-white shadow-md shadow-green-200'
                  : featured
                    ? 'bg-brand-600 hover:bg-brand-700 text-white shadow-md shadow-brand-200'
                    : 'bg-gray-50 hover:bg-brand-50 border border-gray-200 hover:border-brand-300 text-brand-700'">
          <fa-icon :icon="isFree ? 'bolt' : 'chevron-right'" class="mr-1 text-xs" />
          {{ isFree ? 'Démarrer gratuitement' : 'Commander maintenant' }}
        </button>
      </router-link>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue';
import { useAuthStore } from '../stores/auth.js';

const props = defineProps({
  plan: { type: Object, required: true },
  featured: { type: Boolean, default: false },
});

const isFree = computed(() => props.plan.price_monthly === 0);

const auth = useAuthStore();

function formatPrice(xof) {
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'XOF', maximumFractionDigits: 0 }).format(xof);
}
function formatRam(mb) {
  return mb >= 1024 ? `${mb / 1024} GB` : `${mb} MB`;
}
function formatBw(gb) {
  return gb >= 1000 ? `${gb / 1000} TB` : `${gb} GB`;
}
const savings = computed(() => {
  if (!props.plan.price_annually) return 0;
  const yearly = props.plan.price_monthly * 12;
  return Math.round((1 - props.plan.price_annually / yearly) * 100);
});
</script>
