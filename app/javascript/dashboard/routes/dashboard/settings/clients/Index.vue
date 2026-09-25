<script setup>
import { computed, onMounted, ref } from 'vue';
import { useStore, useStoreGetters, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { picoSearch } from '@chatwoot/pico-search';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import Avatar from 'next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import AddClient from './AddClient.vue';
import EditClient from './EditClient.vue';

const store = useStore();
const getters = useStoreGetters();

const showAddPopup = ref(false);
const showEditPopup = ref(false);
const showDeletePopup = ref(false);
const currentClient = ref({});
const searchQuery = ref('');
const loading = ref({});
const visiblePasswords = ref({});

const toggleClientPassword = clientId => {
  visiblePasswords.value[clientId] = !visiblePasswords.value[clientId];
};

const copyPassword = async pwd => {
  try {
    await copyTextToClipboard(pwd);
    useAlert('Password copied to clipboard');
  } catch (err) {
    useAlert('Failed to copy password');
  }
};

const clientsList = computed(() => getters['clients/getClients'].value || []);
const uiFlags = computed(() => getters['clients/getUIFlags'].value || {});
const inboxes = useMapGetter('inboxes/getInboxes');

const filteredClients = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return clientsList.value;
  return picoSearch(clientsList.value, query, ['name', 'username']);
});

const getAssignedInboxNames = client => {
  const ids = client.inbox_ids || [];
  if (ids.length === 0) return 'No inboxes assigned';
  const names = (inboxes.value || [])
    .filter(inbox => ids.includes(inbox.id))
    .map(inbox => inbox.name);
  return names.length > 0 ? names.join(', ') : `${ids.length} inbox(es)`;
};

onMounted(() => {
  store.dispatch('clients/get');
  store.dispatch('inboxes/get');
});

const openAddPopup = () => {
  showAddPopup.value = true;
};

const hideAddPopup = () => {
  showAddPopup.value = false;
};

const openEditPopup = client => {
  currentClient.value = client;
  showEditPopup.value = true;
};

const hideEditPopup = () => {
  showEditPopup.value = false;
};

const openDeletePopup = client => {
  currentClient.value = client;
  showDeletePopup.value = true;
};

const closeDeletePopup = () => {
  showDeletePopup.value = false;
};

const confirmDeletion = async () => {
  try {
    loading.value[currentClient.value.id] = true;
    await store.dispatch('clients/delete', currentClient.value.id);
    useAlert('Client deleted successfully');
    closeDeletePopup();
  } catch (error) {
    useAlert('Could not delete client');
  } finally {
    loading.value[currentClient.value.id] = false;
  }
};
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.isFetching"
    :loading-message="'Loading clients...'"
  >
    <template #header>
      <BaseSettingsHeader
        title="Clients"
        description="Manage client accounts. Clients can log in with username and password to reply only to WhatsApp conversations from assigned inboxes."
      >
        <template #actions>
          <Button
            label="Add Client"
            icon="i-lucide-user-plus"
            @click="openAddPopup"
          />
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <div class="flex flex-col gap-4">
        <!-- Search bar -->
        <div v-if="clientsList.length > 0" class="max-w-md">
          <input
            v-model="searchQuery"
            type="search"
            placeholder="Search clients by name or username..."
            class="w-full px-3 py-2 border rounded-md border-n-slate-6 bg-n-alpha-1 text-n-slate-12 text-sm focus:outline-none focus:ring-1 focus:ring-n-brand"
          />
        </div>

        <!-- Empty state -->
        <div
          v-if="!uiFlags.isFetching && clientsList.length === 0"
          class="flex flex-col items-center justify-center p-12 text-center border border-dashed rounded-xl border-n-slate-6"
        >
          <div class="w-12 h-12 rounded-full bg-n-alpha-2 flex items-center justify-center mb-4 text-n-slate-11">
            <span class="i-lucide-users text-2xl" />
          </div>
          <h3 class="text-base font-semibold text-n-slate-12 mb-1">
            No clients added yet
          </h3>
          <p class="text-sm text-n-slate-10 max-w-sm mb-4">
            Add a client to give them restricted access to reply to conversations in assigned WhatsApp inboxes.
          </p>
          <Button
            label="Add Client"
            icon="i-lucide-user-plus"
            @click="openAddPopup"
          />
        </div>

        <!-- Client list -->
        <div v-else class="flex flex-col divide-y divide-n-slate-4">
          <div
            v-for="client in filteredClients"
            :key="client.id"
            class="flex items-center justify-between py-4"
          >
            <div class="flex items-center gap-4">
              <Avatar
                :name="client.name"
                :src="client.thumbnail"
                size="40px"
              />
              <div class="flex flex-col">
                <span class="text-sm font-semibold text-n-slate-12">
                  {{ client.name }}
                </span>
                <div class="flex items-center flex-wrap gap-2 text-xs text-n-slate-10 mt-0.5">
                  <span class="font-mono bg-n-alpha-2 px-1.5 py-0.5 rounded text-n-brand font-medium">
                    @{{ client.username || 'client' }}
                  </span>
                  <span
                    v-if="client.client_password"
                    class="inline-flex items-center gap-1.5 bg-n-alpha-2 px-2 py-0.5 rounded font-mono text-n-slate-11 border border-n-slate-4"
                  >
                    <span class="text-n-slate-10 select-none">pass:</span>
                    <span class="tracking-wider">{{ visiblePasswords[client.id] ? client.client_password : '••••••••' }}</span>
                    <button
                      type="button"
                      class="hover:text-n-slate-12 p-0.5 transition-colors focus:outline-none cursor-pointer"
                      :title="visiblePasswords[client.id] ? 'Hide password' : 'View password'"
                      @click="toggleClientPassword(client.id)"
                    >
                      <span :class="visiblePasswords[client.id] ? 'i-lucide-eye-off' : 'i-lucide-eye'" class="text-xs block" />
                    </button>
                    <button
                      type="button"
                      class="hover:text-n-slate-12 p-0.5 transition-colors focus:outline-none cursor-pointer"
                      title="Copy password"
                      @click="copyPassword(client.client_password)"
                    >
                      <span class="i-lucide-copy text-xs block" />
                    </button>
                  </span>
                  <span>&bull;</span>
                  <span>{{ getAssignedInboxNames(client) }}</span>
                </div>
              </div>
            </div>

            <div class="flex items-center gap-2">
              <Button
                icon="i-woot-edit-pen"
                variant="faded"
                color="slate"
                size="sm"
                title="Edit Client & Reset Password"
                @click="openEditPopup(client)"
              />
              <Button
                icon="i-woot-bin"
                variant="faded"
                color="ruby"
                size="sm"
                title="Delete Client"
                :is-loading="loading[client.id]"
                @click="openDeletePopup(client)"
              />
            </div>
          </div>
        </div>
      </div>
    </template>

    <woot-modal v-model:show="showAddPopup" :on-close="hideAddPopup">
      <AddClient @close="hideAddPopup" />
    </woot-modal>

    <woot-modal v-model:show="showEditPopup" :on-close="hideEditPopup">
      <EditClient
        v-if="showEditPopup"
        :client="currentClient"
        @close="hideEditPopup"
      />
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDeletePopup"
      :on-close="closeDeletePopup"
      :on-confirm="confirmDeletion"
      title="Delete Client"
      :message="`Are you sure you want to delete ${currentClient.name}? This will remove their access.`"
      confirm-text="Yes, Delete Client"
      reject-text="No, Keep Client"
    />
  </SettingsLayout>
</template>
