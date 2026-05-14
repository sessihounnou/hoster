import { defineStore } from 'pinia';
import { ref } from 'vue';
import api from '../api.js';

export const usePlansStore = defineStore('plans', () => {
  const plans = ref([]);
  const loading = ref(false);

  async function fetchPlans() {
    loading.value = true;
    try {
      const { data } = await api.get('/api/plans');
      plans.value = data.plans;
    } finally {
      loading.value = false;
    }
  }

  return { plans, loading, fetchPlans };
});
