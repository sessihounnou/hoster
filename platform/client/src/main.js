import { createApp } from 'vue';
import { createPinia } from 'pinia';
import { library } from '@fortawesome/fontawesome-svg-core';
import { FontAwesomeIcon } from '@fortawesome/vue-fontawesome';
import {
  faServer, faShieldAlt, faBolt, faUser, faSignInAlt, faSignOutAlt,
  faPlus, faEdit, faTrash, faCopy, faCheck, faSpinner, faCircle,
  faTachometerAlt, faListAlt, faUsers, faCog, faEye, faEyeSlash,
  faChevronRight, faExclamationTriangle, faCheckCircle, faTimesCircle,
  faPause, faPlay, faNetworkWired, faMemory, faHdd, faDatabase,
  faEnvelope, faLock, faPhone, faHome, faBars, faTimes,
} from '@fortawesome/free-solid-svg-icons';
import { faGithub, faLinkedin } from '@fortawesome/free-brands-svg-icons';

import App from './App.vue';
import router from './router/index.js';
import './style.css';

library.add(
  faServer, faShieldAlt, faBolt, faUser, faSignInAlt, faSignOutAlt,
  faPlus, faEdit, faTrash, faCopy, faCheck, faSpinner, faCircle,
  faTachometerAlt, faListAlt, faUsers, faCog, faEye, faEyeSlash,
  faChevronRight, faExclamationTriangle, faCheckCircle, faTimesCircle,
  faPause, faPlay, faNetworkWired, faMemory, faHdd, faDatabase,
  faEnvelope, faLock, faPhone, faHome, faBars, faTimes,
  faGithub, faLinkedin,
);

const app = createApp(App);
app.use(createPinia());
app.use(router);
app.component('fa-icon', FontAwesomeIcon);
app.mount('#app');
