<template>
  <span class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold" :class="statusClass">
    <fa-icon :icon="statusIcon" :class="statusIcon === 'spinner' ? 'animate-spin' : ''" />
    {{ statusLabel }}
  </span>
</template>

<script setup>
import { computed } from 'vue';

const props = defineProps({ status: { type: String, required: true } });

const config = {
  active:       { label: 'Actif',          icon: 'check-circle',        cls: 'bg-green-100 text-green-700' },
  provisioning: { label: 'En création',    icon: 'spinner',             cls: 'bg-yellow-100 text-yellow-700' },
  suspended:    { label: 'Suspendu',       icon: 'pause',               cls: 'bg-red-100 text-red-700' },
  terminated:   { label: 'Terminé',        icon: 'times-circle',        cls: 'bg-gray-100 text-gray-500' },
};

const statusLabel = computed(() => config[props.status]?.label || props.status);
const statusIcon  = computed(() => config[props.status]?.icon  || 'circle');
const statusClass = computed(() => config[props.status]?.cls   || 'bg-gray-100 text-gray-600');
</script>
