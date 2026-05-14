<template>
  <nav class="bg-brand-800 text-white shadow-lg sticky top-0 z-50">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
      <div class="flex items-center justify-between h-16">
        <!-- Logo -->
        <router-link to="/" class="flex items-center gap-2 font-bold text-xl tracking-tight hover:opacity-90 transition">
          <fa-icon icon="server" class="text-indigo-300" />
          <span>MonVPS</span>
        </router-link>

        <!-- Desktop nav -->
        <div class="hidden md:flex items-center gap-6">
          <router-link to="/" class="hover:text-indigo-200 transition text-sm font-medium">Offres</router-link>
          <template v-if="auth.isLoggedIn">
            <router-link to="/dashboard" class="hover:text-indigo-200 transition text-sm font-medium">
              <fa-icon icon="tachometer-alt" class="mr-1" /> Mon espace
            </router-link>
            <router-link v-if="auth.isAdmin" to="/admin" class="hover:text-indigo-200 transition text-sm font-medium">
              <fa-icon icon="cog" class="mr-1" /> Admin
            </router-link>
            <button @click="handleLogout" class="bg-white/10 hover:bg-white/20 transition px-4 py-1.5 rounded-lg text-sm font-medium flex items-center gap-1.5">
              <fa-icon icon="sign-out-alt" />
              Déconnexion
            </button>
          </template>
          <template v-else>
            <router-link to="/login" class="hover:text-indigo-200 transition text-sm font-medium">Connexion</router-link>
            <router-link to="/register" class="bg-indigo-500 hover:bg-indigo-400 transition px-4 py-1.5 rounded-lg text-sm font-semibold">
              Créer un compte
            </router-link>
          </template>
        </div>

        <!-- Mobile menu button -->
        <button @click="menuOpen = !menuOpen" class="md:hidden p-2 rounded-lg hover:bg-white/10 transition">
          <fa-icon :icon="menuOpen ? 'times' : 'bars'" />
        </button>
      </div>
    </div>

    <!-- Mobile menu -->
    <transition name="slide">
      <div v-if="menuOpen" class="md:hidden bg-brand-900 border-t border-white/10 px-4 py-4 space-y-3">
        <router-link to="/" @click="menuOpen = false" class="block text-sm py-2 hover:text-indigo-200">Offres</router-link>
        <template v-if="auth.isLoggedIn">
          <router-link to="/dashboard" @click="menuOpen = false" class="block text-sm py-2 hover:text-indigo-200">Mon espace</router-link>
          <router-link v-if="auth.isAdmin" to="/admin" @click="menuOpen = false" class="block text-sm py-2 hover:text-indigo-200">Admin</router-link>
          <button @click="handleLogout" class="block text-sm py-2 text-red-300 hover:text-red-200">Déconnexion</button>
        </template>
        <template v-else>
          <router-link to="/login" @click="menuOpen = false" class="block text-sm py-2 hover:text-indigo-200">Connexion</router-link>
          <router-link to="/register" @click="menuOpen = false" class="block text-sm py-2 text-indigo-300 font-semibold">Créer un compte</router-link>
        </template>
      </div>
    </transition>
  </nav>
</template>

<script setup>
import { ref } from 'vue';
import { useRouter } from 'vue-router';
import { useAuthStore } from '../stores/auth.js';

const auth = useAuthStore();
const router = useRouter();
const menuOpen = ref(false);

function handleLogout() {
  auth.logout();
  router.push('/');
  menuOpen.value = false;
}
</script>

<style scoped>
.slide-enter-active, .slide-leave-active { transition: all 0.2s ease; }
.slide-enter-from, .slide-leave-to { opacity: 0; transform: translateY(-8px); }
</style>
