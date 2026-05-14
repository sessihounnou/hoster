<template>
  <div class="min-h-screen bg-gray-100 flex">
    <!-- Sidebar -->
    <aside class="w-64 bg-brand-900 text-white flex flex-col fixed h-full z-40 transition-transform"
           :class="sidebarOpen ? 'translate-x-0' : '-translate-x-full md:translate-x-0'">
      <!-- Logo -->
      <div class="p-5 border-b border-white/10">
        <router-link to="/" class="flex items-center gap-2 font-bold text-lg hover:opacity-90">
          <fa-icon icon="server" class="text-indigo-300" />
          <span>MonVPS Admin</span>
        </router-link>
      </div>

      <!-- Nav -->
      <nav class="flex-1 p-4 space-y-1">
        <router-link v-for="item in navItems" :key="item.path"
          :to="item.path"
          @click="sidebarOpen = false"
          class="flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition"
          :class="route.path.startsWith(item.path) ? 'bg-white/15 text-white' : 'text-white/60 hover:bg-white/10 hover:text-white'">
          <fa-icon :icon="item.icon" class="w-4" />
          {{ item.label }}
        </router-link>
      </nav>

      <!-- Pied de sidebar -->
      <div class="p-4 border-t border-white/10">
        <router-link to="/dashboard" class="flex items-center gap-2 text-white/60 hover:text-white text-sm transition">
          <fa-icon icon="user" />
          Mon espace client
        </router-link>
      </div>
    </aside>

    <!-- Overlay mobile -->
    <div v-if="sidebarOpen" @click="sidebarOpen = false"
      class="fixed inset-0 bg-black/50 z-30 md:hidden" />

    <!-- Contenu principal -->
    <div class="flex-1 md:ml-64 flex flex-col min-h-screen">
      <!-- Top bar -->
      <header class="bg-white border-b border-gray-200 h-14 flex items-center justify-between px-4 md:px-6 sticky top-0 z-20">
        <button @click="sidebarOpen = !sidebarOpen" class="md:hidden p-2 text-gray-600 hover:text-gray-900">
          <fa-icon icon="bars" />
        </button>
        <div class="hidden md:block">
          <h1 class="text-sm font-semibold text-gray-700">Panel Administration</h1>
        </div>
        <div class="flex items-center gap-3">
          <span class="text-sm text-gray-500">{{ auth.user?.email }}</span>
          <button @click="handleLogout" class="text-sm text-red-500 hover:text-red-700 flex items-center gap-1">
            <fa-icon icon="sign-out-alt" />
          </button>
        </div>
      </header>

      <!-- Vue enfant -->
      <main class="flex-1 p-4 md:p-6">
        <router-view />
      </main>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useAuthStore } from '../../stores/auth.js';

const auth = useAuthStore();
const route = useRoute();
const router = useRouter();
const sidebarOpen = ref(false);

const navItems = [
  { path: '/admin/dashboard', label: 'Tableau de bord', icon: 'tachometer-alt' },
  { path: '/admin/plans',     label: 'Plans VPS',       icon: 'list-alt' },
  { path: '/admin/clients',   label: 'Clients',         icon: 'users' },
  { path: '/admin/orders',    label: 'Commandes',       icon: 'database' },
];

function handleLogout() {
  auth.logout();
  router.push('/');
}
</script>
