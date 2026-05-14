<template>
  <div class="min-h-screen bg-gray-50">
    <NavBar />

    <!-- ── Hero ─────────────────────────────────────────────────────────── -->
    <section class="bg-gradient-to-br from-brand-900 via-brand-800 to-indigo-800 text-white py-28 px-4 relative overflow-hidden">
      <!-- Décoration fond -->
      <div class="absolute inset-0 opacity-10 pointer-events-none" aria-hidden="true">
        <div class="absolute -top-20 -right-20 w-96 h-96 bg-indigo-400 rounded-full blur-3xl"></div>
        <div class="absolute -bottom-10 -left-10 w-72 h-72 bg-brand-400 rounded-full blur-3xl"></div>
      </div>

      <div class="max-w-5xl mx-auto text-center relative">
        <div class="inline-flex items-center gap-2 bg-white/10 border border-white/20 rounded-full px-4 py-1.5 text-sm mb-8">
          <fa-icon icon="bolt" class="text-yellow-300" />
          <span>Datacenter Hub Europe · Ubuntu 24.04 · KVM Proxmox</span>
        </div>

        <h1 class="text-5xl md:text-7xl font-extrabold mb-6 leading-tight tracking-tight">
          Votre serveur,<br>
          <span class="text-transparent bg-clip-text bg-gradient-to-r from-indigo-300 to-cyan-300">
            vos règles.
          </span>
        </h1>

        <p class="text-xl text-white/75 mb-10 max-w-2xl mx-auto leading-relaxed">
          Des VPS KVM haute performance livrés en moins de 5 minutes,
          payez avec <strong class="text-white">FedaPay</strong> et obtenez un accès root complet immédiatement.
        </p>

        <div class="flex flex-col sm:flex-row gap-4 justify-center">
          <a href="#plans"
             class="bg-white text-brand-800 font-bold px-8 py-4 rounded-xl hover:bg-indigo-50 transition shadow-xl text-base">
            <fa-icon icon="server" class="mr-2" />
            Voir les offres
          </a>
          <router-link to="/register"
             class="bg-indigo-500/80 hover:bg-indigo-500 border border-white/20 text-white font-bold px-8 py-4 rounded-xl transition text-base">
            Essayer gratuitement
            <fa-icon icon="chevron-right" class="ml-2 text-sm" />
          </router-link>
        </div>

        <!-- Stats rapides -->
        <div class="mt-16 grid grid-cols-3 gap-6 max-w-lg mx-auto text-center">
          <div>
            <p class="text-3xl font-extrabold text-white">99.9%</p>
            <p class="text-xs text-white/50 mt-1">Disponibilité</p>
          </div>
          <div class="border-x border-white/10">
            <p class="text-3xl font-extrabold text-white">&lt; 5min</p>
            <p class="text-xs text-white/50 mt-1">Livraison VPS</p>
          </div>
          <div>
            <p class="text-3xl font-extrabold text-white">24/7</p>
            <p class="text-xs text-white/50 mt-1">Support</p>
          </div>
        </div>
      </div>
    </section>

    <!-- ── Ce que vous pouvez faire ──────────────────────────────────────── -->
    <section class="py-24 px-4 bg-white">
      <div class="max-w-6xl mx-auto">
        <div class="text-center mb-14">
          <h2 class="text-3xl md:text-4xl font-extrabold text-gray-900 mb-3">
            Un VPS, des possibilités infinies
          </h2>
          <p class="text-gray-500 text-lg max-w-xl mx-auto">
            Avec un accès root complet et une connexion à 1 Gbps, tout est possible.
          </p>
        </div>

        <div class="grid grid-cols-2 md:grid-cols-3 gap-5">
          <UseCaseCard
            v-for="use in useCases" :key="use.title"
            :icon="use.icon"
            :title="use.title"
            :desc="use.desc"
            :color="use.color"
          />
        </div>
      </div>
    </section>

    <!-- ── Comment ça marche ──────────────────────────────────────────────── -->
    <section class="py-20 px-4 bg-gray-50">
      <div class="max-w-4xl mx-auto">
        <div class="text-center mb-12">
          <h2 class="text-3xl font-extrabold text-gray-900 mb-3">En 3 étapes simples</h2>
          <p class="text-gray-500">De l'inscription à votre VPS actif en moins de 10 minutes.</p>
        </div>

        <div class="relative">
          <!-- Ligne de connexion (desktop) -->
          <div class="hidden md:block absolute top-10 left-1/6 right-1/6 h-0.5 bg-brand-100"></div>

          <div class="grid grid-cols-1 md:grid-cols-3 gap-8">
            <StepCard step="1" icon="user" title="Créez votre compte"
              desc="Inscription rapide avec votre email. Aucune carte bancaire requise pour commencer." />
            <StepCard step="2" icon="database" title="Choisissez votre plan"
              desc="Sélectionnez les ressources dont vous avez besoin et payez en toute sécurité via FedaPay." />
            <StepCard step="3" icon="server" title="Recevez vos accès"
              desc="Votre VPS est provisionné automatiquement. Les credentials SSH arrivent par email en moins de 5 min." />
          </div>
        </div>
      </div>
    </section>

    <!-- ── Plans ─────────────────────────────────────────────────────────── -->
    <section id="plans" class="py-24 px-4 bg-white">
      <div class="max-w-6xl mx-auto">
        <div class="text-center mb-14">
          <h2 class="text-3xl md:text-4xl font-extrabold text-gray-900 mb-3">Choisissez votre offre</h2>
          <p class="text-gray-500 text-lg">Tous les plans incluent accès SSH root, IP dédiée et protection DDoS.</p>
        </div>

        <div v-if="plansStore.loading" class="flex justify-center py-16">
          <fa-icon icon="spinner" class="text-4xl text-brand-500 animate-spin" />
        </div>

        <div v-else class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 items-start">
          <PlanCard
            v-for="plan in plansStore.plans"
            :key="plan.id"
            :plan="plan"
            :featured="plan.slug === 'pro'"
          />
        </div>

        <!-- Note freemium -->
        <div class="mt-8 bg-indigo-50 border border-indigo-100 rounded-xl px-6 py-4 flex items-start gap-3 max-w-2xl mx-auto">
          <fa-icon icon="shield-alt" class="text-indigo-500 mt-0.5 flex-shrink-0" />
          <p class="text-sm text-indigo-700">
            <strong>Plan Freemium :</strong> 30 jours gratuits, aucune carte requise.
            Limité à 1 VPS actif simultané. Après 30 jours, passez à un plan payant pour continuer.
          </p>
        </div>
      </div>
    </section>

    <!-- ── Garanties / Infra ──────────────────────────────────────────────── -->
    <section class="py-20 px-4 bg-gradient-to-br from-brand-900 to-brand-800 text-white">
      <div class="max-w-5xl mx-auto">
        <div class="text-center mb-12">
          <h2 class="text-3xl font-extrabold mb-3">Une infrastructure de confiance</h2>
          <p class="text-white/60">Nos serveurs tournent sur une infrastructure Proxmox KVM dans un datacenter européen.</p>
        </div>
        <div class="grid grid-cols-2 md:grid-cols-4 gap-6 text-center">
          <div v-for="g in guarantees" :key="g.label" class="bg-white/5 border border-white/10 rounded-xl p-5">
            <fa-icon :icon="g.icon" class="text-2xl mb-3" :class="g.color" />
            <p class="font-bold text-sm">{{ g.label }}</p>
            <p class="text-white/50 text-xs mt-1">{{ g.sub }}</p>
          </div>
        </div>
      </div>
    </section>

    <!-- ── FAQ ───────────────────────────────────────────────────────────── -->
    <section class="py-20 px-4 bg-gray-50">
      <div class="max-w-2xl mx-auto">
        <h2 class="text-3xl font-extrabold text-gray-900 text-center mb-10">Questions fréquentes</h2>
        <div class="space-y-3">
          <FaqItem
            v-for="faq in faqs" :key="faq.q"
            :question="faq.q" :answer="faq.a"
          />
        </div>
      </div>
    </section>

    <!-- ── CTA final ─────────────────────────────────────────────────────── -->
    <section class="py-20 px-4 bg-white text-center">
      <div class="max-w-xl mx-auto">
        <fa-icon icon="server" class="text-5xl text-brand-200 mb-5" />
        <h2 class="text-3xl font-extrabold text-gray-900 mb-4">Prêt à démarrer ?</h2>
        <p class="text-gray-500 mb-8">Créez votre compte en 30 secondes et obtenez votre VPS gratuit immédiatement.</p>
        <router-link to="/register" class="btn-primary text-base px-10 py-4 inline-flex items-center gap-2">
          <fa-icon icon="bolt" />
          Commencer gratuitement
        </router-link>
      </div>
    </section>

    <!-- ── Footer ─────────────────────────────────────────────────────────── -->
    <footer class="bg-brand-900 text-white/50 py-10 px-4">
      <div class="max-w-5xl mx-auto flex flex-col md:flex-row items-center justify-between gap-4 text-sm">
        <div class="flex items-center gap-2 text-white font-bold text-base">
          <fa-icon icon="server" class="text-indigo-300" />
          MonVPS
        </div>
        <p>&copy; {{ new Date().getFullYear() }} MonVPS · Datacenter Hub Europe · Paiement FedaPay</p>
        <div class="flex gap-4">
          <a href="#plans" class="hover:text-white transition">Offres</a>
          <router-link to="/login" class="hover:text-white transition">Connexion</router-link>
          <router-link to="/register" class="hover:text-white transition">Inscription</router-link>
        </div>
      </div>
    </footer>
  </div>
</template>

<script setup>
import { onMounted, defineComponent, h, ref } from 'vue';
import NavBar from '../components/NavBar.vue';
import PlanCard from '../components/PlanCard.vue';
import { usePlansStore } from '../stores/plans.js';

const plansStore = usePlansStore();
onMounted(() => plansStore.fetchPlans());

// ── Composants inline légers ───────────────────────────────────────────────
const UseCaseCard = defineComponent({
  props: { icon: String, title: String, desc: String, color: String },
  setup(props) {
    return () => h('div', { class: 'bg-gray-50 hover:bg-white border border-gray-100 hover:border-gray-200 hover:shadow-md rounded-2xl p-5 transition-all duration-200 group' }, [
      h('div', { class: `w-11 h-11 rounded-xl flex items-center justify-center mb-3 ${props.color}` }, [
        h('fa-icon', { icon: props.icon, class: 'text-lg' }),
      ]),
      h('h3', { class: 'font-bold text-gray-900 text-sm mb-1' }, props.title),
      h('p', { class: 'text-gray-500 text-xs leading-relaxed' }, props.desc),
    ]);
  },
});

const StepCard = defineComponent({
  props: { step: String, icon: String, title: String, desc: String },
  setup(props) {
    return () => h('div', { class: 'text-center relative' }, [
      h('div', { class: 'w-20 h-20 bg-brand-600 rounded-2xl flex flex-col items-center justify-center mx-auto mb-4 shadow-lg shadow-brand-200' }, [
        h('fa-icon', { icon: props.icon, class: 'text-white text-2xl' }),
      ]),
      h('div', { class: 'absolute -top-2 left-1/2 -translate-x-1/2 w-6 h-6 bg-indigo-100 text-brand-700 rounded-full text-xs font-bold flex items-center justify-center' }, props.step),
      h('h3', { class: 'font-bold text-gray-900 mb-2' }, props.title),
      h('p', { class: 'text-gray-500 text-sm leading-relaxed' }, props.desc),
    ]);
  },
});

const FaqItem = defineComponent({
  props: { question: String, answer: String },
  setup(props) {
    const open = ref(false);
    return () => h('div', {
      class: 'border border-gray-200 rounded-xl overflow-hidden',
    }, [
      h('button', {
        class: 'w-full text-left px-5 py-4 flex items-center justify-between font-medium text-gray-900 hover:bg-gray-50 transition',
        onClick: () => { open.value = !open.value; },
      }, [
        props.question,
        h('fa-icon', { icon: 'chevron-right', class: `text-gray-400 text-sm transition-transform duration-200 ${open.value ? 'rotate-90' : ''}` }),
      ]),
      open.value ? h('div', { class: 'px-5 pb-4 text-sm text-gray-500 leading-relaxed border-t border-gray-100 pt-3' }, props.answer) : null,
    ]);
  },
});

// ── Données ────────────────────────────────────────────────────────────────
const useCases = [
  { icon: 'server',        title: 'Héberger un site web',      color: 'bg-blue-100 text-blue-600',    desc: 'WordPress, Next.js, Laravel, Nuxt… déployez n\'importe quel stack web avec Nginx ou Apache.' },
  { icon: 'shield-alt',    title: 'VPN personnel',             color: 'bg-green-100 text-green-600',  desc: 'Installez WireGuard ou OpenVPN pour naviguer de façon privée et sécurisée depuis n\'importe où.' },
  { icon: 'database',      title: 'Base de données',           color: 'bg-purple-100 text-purple-600', desc: 'MySQL, PostgreSQL, MongoDB, Redis… hébergez votre DB avec des sauvegardes automatiques.' },
  { icon: 'bolt',          title: 'API & Backend',             color: 'bg-yellow-100 text-yellow-600', desc: 'Node.js, Python, Go, PHP — déployez votre API avec PM2, Supervisor ou Docker.' },
  { icon: 'cog',           title: 'Serveur de jeu',            color: 'bg-red-100 text-red-600',      desc: 'Minecraft, CS:GO, Valheim… créez votre propre serveur de jeu avec vos règles.' },
  { icon: 'network-wired', title: 'Docker & Conteneurs',       color: 'bg-indigo-100 text-indigo-600', desc: 'Déployez des conteneurs Docker, orchestrez avec Portainer et automatisez vos déploiements CI/CD.' },
  { icon: 'hdd',           title: 'Stockage & Backup',         color: 'bg-orange-100 text-orange-600', desc: 'Nextcloud, Seafile, MinIO — votre propre cloud personnel ou professionnel sécurisé.' },
  { icon: 'bolt',          title: 'Bot & Automatisation',      color: 'bg-pink-100 text-pink-600',    desc: 'Bots Discord, Telegram, scraping, cron jobs — faites tourner vos scripts 24h/24, 7j/7.' },
  { icon: 'lock',          title: 'Proxy & Reverse Proxy',     color: 'bg-teal-100 text-teal-600',    desc: 'Nginx reverse proxy, HAProxy, Traefik — redirigez et protégez vos services en ligne.' },
];

const guarantees = [
  { icon: 'shield-alt',    label: 'Protection DDoS',  sub: 'Incluse sur tous les plans',    color: 'text-green-300' },
  { icon: 'server',        label: 'KVM Proxmox',      sub: 'Isolation complète garantie',   color: 'text-indigo-300' },
  { icon: 'hdd',           label: 'SSD NVMe',         sub: 'I/O ultra-rapide',              color: 'text-yellow-300' },
  { icon: 'network-wired', label: '1 Gbps réseau',    sub: 'Hub Europe, faible latence',    color: 'text-cyan-300' },
];

const faqs = [
  { q: 'Qu\'est-ce qu\'un VPS ?', a: 'Un VPS (Virtual Private Server) est un serveur dédié virtualisé. Vous avez un accès root complet, vos propres ressources (CPU, RAM, disque) et une IP dédiée, comme sur un serveur physique mais à moindre coût.' },
  { q: 'Comment fonctionne le plan Freemium ?', a: 'Le plan Freemium vous donne accès à un VPS (1 vCPU, 512 MB RAM, 5 GB SSD) pendant 30 jours gratuitement, sans carte bancaire. Après 30 jours, vous pouvez passer à un plan payant ou le VPS est suspendu.' },
  { q: 'Comment puis-je payer ?', a: 'Nous acceptons les paiements via FedaPay — mobile money (MTN, Moov), virement bancaire et carte. Aucune configuration complexe requise.' },
  { q: 'Mon VPS est-il disponible immédiatement ?', a: 'Oui. Après confirmation du paiement, votre VPS est provisionné automatiquement. Vous recevez les credentials SSH par email en moins de 5 minutes.' },
  { q: 'Puis-je installer n\'importe quel logiciel ?', a: 'Absolument. Vous avez un accès root complet. Vous pouvez installer n\'importe quel logiciel compatible Linux : serveurs web, bases de données, Docker, jeux, bots…' },
  { q: 'Quelle est la localisation des serveurs ?', a: 'Nos serveurs sont situés dans le Hub Europe, offrant une excellente connectivité pour l\'Afrique de l\'Ouest et l\'Europe.' },
];
</script>
