import { defineStore } from 'pinia';
import { ref, computed } from 'vue';
import api from '../api.js';

export const useAuthStore = defineStore('auth', () => {
  const token = ref(localStorage.getItem('token') || null);
  const user = ref(JSON.parse(localStorage.getItem('user') || 'null'));

  const isLoggedIn = computed(() => !!token.value);
  const isAdmin = computed(() => user.value?.role === 'admin');

  function setAuth(newToken, newUser) {
    token.value = newToken;
    user.value = newUser;
    localStorage.setItem('token', newToken);
    localStorage.setItem('user', JSON.stringify(newUser));
    api.defaults.headers.common['Authorization'] = `Bearer ${newToken}`;
  }

  function logout() {
    token.value = null;
    user.value = null;
    localStorage.removeItem('token');
    localStorage.removeItem('user');
    delete api.defaults.headers.common['Authorization'];
  }

  // Initialiser l'en-tête axios si token existe
  if (token.value) {
    api.defaults.headers.common['Authorization'] = `Bearer ${token.value}`;
  }

  async function fetchMe() {
    try {
      const { data } = await api.get('/api/auth/me');
      user.value = data.user;
      localStorage.setItem('user', JSON.stringify(data.user));
    } catch {
      logout();
    }
  }

  return { token, user, isLoggedIn, isAdmin, setAuth, logout, fetchMe };
});
