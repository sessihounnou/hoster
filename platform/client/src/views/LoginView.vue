<template>
  <div class="min-h-screen bg-gray-50 flex flex-col">
    <NavBar />
    <div class="flex-1 flex items-center justify-center px-4 py-12">
      <div class="w-full max-w-md">
        <div class="card">
          <div class="text-center mb-8">
            <div class="w-14 h-14 bg-brand-100 rounded-2xl flex items-center justify-center mx-auto mb-4">
              <fa-icon icon="lock" class="text-2xl text-brand-600" />
            </div>
            <h1 class="text-2xl font-bold text-gray-900">Connexion</h1>
            <p class="text-gray-500 text-sm mt-1">Accédez à votre espace client</p>
          </div>

          <form @submit.prevent="handleLogin" class="space-y-4">
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1.5">Adresse email</label>
              <div class="relative">
                <fa-icon icon="envelope" class="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 text-sm" />
                <input v-model="form.email" type="email" required placeholder="vous@exemple.com"
                  class="input pl-9" autocomplete="email" />
              </div>
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1.5">Mot de passe</label>
              <div class="relative">
                <fa-icon icon="lock" class="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 text-sm" />
                <input v-model="form.password" :type="showPass ? 'text' : 'password'" required
                  placeholder="••••••••" class="input pl-9 pr-10" autocomplete="current-password" />
                <button type="button" @click="showPass = !showPass"
                  class="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600">
                  <fa-icon :icon="showPass ? 'eye-slash' : 'eye'" />
                </button>
              </div>
            </div>

            <div v-if="error" class="bg-red-50 border border-red-200 text-red-700 text-sm rounded-lg px-4 py-3 flex items-center gap-2">
              <fa-icon icon="exclamation-triangle" />
              {{ error }}
            </div>

            <button type="submit" :disabled="loading" class="btn-primary w-full py-3">
              <fa-icon v-if="loading" icon="spinner" class="animate-spin mr-2" />
              <fa-icon v-else icon="sign-in-alt" class="mr-2" />
              Se connecter
            </button>
          </form>

          <p class="text-center text-sm text-gray-500 mt-6">
            Pas encore de compte ?
            <router-link to="/register" class="text-brand-600 font-semibold hover:underline">S'inscrire</router-link>
          </p>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue';
import { useRouter, useRoute } from 'vue-router';
import NavBar from '../components/NavBar.vue';
import { useAuthStore } from '../stores/auth.js';
import api from '../api.js';

const auth = useAuthStore();
const router = useRouter();
const route = useRoute();

const form = ref({ email: '', password: '' });
const loading = ref(false);
const error = ref('');
const showPass = ref(false);

async function handleLogin() {
  loading.value = true;
  error.value = '';
  try {
    const { data } = await api.post('/api/auth/login', form.value);
    auth.setAuth(data.token, data.user);
    const redirect = route.query.redirect || (data.user.role === 'admin' ? '/admin' : '/dashboard');
    router.push(redirect);
  } catch (err) {
    error.value = err.response?.data?.error || 'Erreur de connexion. Réessayez.';
  } finally {
    loading.value = false;
  }
}
</script>
