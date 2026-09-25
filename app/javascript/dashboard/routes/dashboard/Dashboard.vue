<script>
import { defineAsyncComponent, ref, computed } from 'vue';
import { useStore } from 'vuex';
import Auth from 'dashboard/api/auth';

import NextSidebar from 'next/sidebar/Sidebar.vue';
import WootKeyShortcutModal from 'dashboard/components/widgets/modal/WootKeyShortcutModal.vue';
import AddAccountModal from 'dashboard/components/app/AddAccountModal.vue';
import UpgradePage from 'dashboard/routes/dashboard/upgrade/UpgradePage.vue';

import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAccount } from 'dashboard/composables/useAccount';
import { useWindowSize } from '@vueuse/core';

import wootConstants from 'dashboard/constants/globals';
import { isUpgradePageBypassRoute } from 'dashboard/helper/routeHelpers';

const CommandBar = defineAsyncComponent(
  () => import('./commands/commandbar.vue')
);

const FloatingCallWidget = defineAsyncComponent(
  () => import('dashboard/components-next/call/FloatingCallWidget.vue')
);

import MobileSidebarLauncher from 'dashboard/components-next/sidebar/MobileSidebarLauncher.vue';
import { useCallsStore } from 'dashboard/stores/calls';

export default {
  components: {
    NextSidebar,
    CommandBar,
    WootKeyShortcutModal,
    AddAccountModal,
    UpgradePage,
    FloatingCallWidget,
    MobileSidebarLauncher,
  },
  setup() {
    const upgradePageRef = ref(null);
    const { uiSettings, updateUISettings } = useUISettings();
    const { accountId } = useAccount();
    const { width: windowWidth } = useWindowSize();
    const callsStore = useCallsStore();
    const store = useStore();
    const isClient = computed(() => store.getters.getCurrentRole === 'client');
    const currentUser = computed(() => store.getters.getCurrentUser || {});
    const currentAccount = computed(() => store.getters.getCurrentAccount || {});
    const currentAccountName = computed(() => currentAccount.value?.name || 'Account');
    const clientDisplayName = computed(() => currentUser.value?.name || currentUser.value?.username || 'Client');
    const clientInitials = computed(() => {
      const name = clientDisplayName.value;
      return name ? name.substring(0, 2).toUpperCase() : 'C';
    });

    const handleLogout = async () => {
      await Auth.logout();
      window.location = '/client/login';
    };

    return {
      uiSettings,
      updateUISettings,
      accountId,
      upgradePageRef,
      windowWidth,
      isClient,
      currentAccountName,
      clientDisplayName,
      clientInitials,
      handleLogout,
      hasActiveCall: computed(() => callsStore.hasActiveCall),
      hasIncomingCall: computed(() => callsStore.hasIncomingCall),
    };
  },
  data() {
    return {
      showAccountModal: false,
      showCreateAccountModal: false,
      showShortcutModal: false,
      isMobileSidebarOpen: false,
    };
  },
  computed: {
    isSmallScreen() {
      return this.windowWidth < wootConstants.SMALL_SCREEN_BREAKPOINT;
    },
    showUpgradePage() {
      return this.upgradePageRef?.shouldShowUpgradePage;
    },
    isAccountPaywalled() {
      return this.upgradePageRef?.isAccountPaywalled;
    },
    bypassUpgradePage() {
      return isUpgradePageBypassRoute(this.$route.name);
    },
    previouslyUsedDisplayType() {
      const {
        previously_used_conversation_display_type: conversationDisplayType,
      } = this.uiSettings;
      return conversationDisplayType;
    },
  },
  watch: {
    isSmallScreen: {
      handler() {
        const { LAYOUT_TYPES } = wootConstants;
        if (window.innerWidth <= wootConstants.SMALL_SCREEN_BREAKPOINT) {
          this.updateUISettings({
            conversation_display_type: LAYOUT_TYPES.EXPANDED,
          });
        } else {
          this.updateUISettings({
            conversation_display_type: this.previouslyUsedDisplayType,
          });
        }
      },
      immediate: true,
    },
  },
  methods: {
    toggleMobileSidebar() {
      this.isMobileSidebarOpen = !this.isMobileSidebarOpen;
    },
    closeMobileSidebar() {
      this.isMobileSidebarOpen = false;
    },
    openCreateAccountModal() {
      this.showAccountModal = false;
      this.showCreateAccountModal = true;
    },
    closeCreateAccountModal() {
      this.showCreateAccountModal = false;
    },
    toggleAccountModal() {
      this.showAccountModal = !this.showAccountModal;
    },
    toggleKeyShortcutModal() {
      this.showShortcutModal = true;
    },
    closeKeyShortcutModal() {
      this.showShortcutModal = false;
    },
  },
};
</script>

<template>
  <div class="flex flex-col flex-grow h-screen w-screen overflow-hidden text-n-slate-12">
    <!-- Client Topbar when logged in as client -->
    <header
      v-if="isClient"
      class="flex h-14 w-full items-center justify-between border-b border-n-slate-4 bg-n-surface-1 px-4 sm:px-6 shrink-0 z-20"
    >
      <div class="flex items-center gap-3">
        <img
          :src="'/brand-assets/logo_thumbnail.png'"
          alt="MMOChat"
          class="h-8 w-8 rounded-lg object-contain shadow-sm"
        />
        <div class="flex items-center gap-2">
          <span class="text-sm font-bold text-n-slate-12">MMOChat</span>
          <span class="rounded bg-n-alpha-2 px-1.5 py-0.5 text-xs font-medium text-n-brand">
            Client Portal
          </span>
          <span class="text-xs text-n-slate-9 hidden sm:inline">&bull;</span>
          <span class="text-xs text-n-slate-11 font-medium hidden sm:inline">
            {{ currentAccountName }}
          </span>
        </div>
      </div>

      <div class="flex items-center gap-3">
        <div class="flex items-center gap-2">
          <div class="w-7 h-7 rounded-full bg-n-alpha-3 flex items-center justify-center text-xs font-semibold text-n-slate-12">
            {{ clientInitials }}
          </div>
          <span class="text-xs font-medium text-n-slate-11 hidden sm:inline">
            {{ clientDisplayName }}
          </span>
        </div>
        <button
          type="button"
          class="flex items-center gap-1.5 px-3 py-1.5 rounded-md text-xs font-medium text-n-ruby-11 bg-n-ruby-2 hover:bg-n-ruby-3 transition"
          @click="handleLogout"
        >
          <span class="i-lucide-log-out text-sm" />
          <span>Logout</span>
        </button>
      </div>
    </header>

    <!-- Main App Layout -->
    <div class="flex flex-1 min-h-0 overflow-hidden">
      <NextSidebar
        v-if="!isClient"
        :is-mobile-sidebar-open="isMobileSidebarOpen"
        @toggle-account-modal="toggleAccountModal"
        @open-key-shortcut-modal="toggleKeyShortcutModal"
        @close-key-shortcut-modal="closeKeyShortcutModal"
        @show-create-account-modal="openCreateAccountModal"
        @close-mobile-sidebar="closeMobileSidebar"
      />

      <main
        class="flex flex-1 h-full w-full min-h-0 px-0 overflow-hidden bg-n-surface-1"
      >
        <UpgradePage
          v-if="!isClient"
          v-show="showUpgradePage"
          ref="upgradePageRef"
          :bypass-upgrade-page="bypassUpgradePage"
        >
          <MobileSidebarLauncher
            :is-mobile-sidebar-open="isMobileSidebarOpen"
            @toggle="toggleMobileSidebar"
          />
        </UpgradePage>
        <template v-if="isClient || !showUpgradePage">
          <router-view />
          <MobileSidebarLauncher
            v-if="!isClient"
            :is-mobile-sidebar-open="isMobileSidebarOpen"
            @toggle="toggleMobileSidebar"
          />
          <FloatingCallWidget v-if="!isClient && (hasActiveCall || hasIncomingCall)" />
        </template>
        <CommandBar v-if="!isClient" :is-paywalled="isAccountPaywalled" />
        <AddAccountModal
          v-if="!isClient"
          :show="showCreateAccountModal"
          @close-account-create-modal="closeCreateAccountModal"
        />
        <WootKeyShortcutModal
          v-if="!isClient"
          v-model:show="showShortcutModal"
          @close="closeKeyShortcutModal"
          @clickaway="closeKeyShortcutModal"
        />
      </main>
    </div>
  </div>
</template>
