<script setup>
import { ref, computed } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';

const emit = defineEmits(['close']);
const store = useStore();

const name = ref('');
const username = ref('');
const password = ref('');
const selectedInboxIds = ref([]);
const errorMessage = ref('');

const inboxes = useMapGetter('inboxes/getInboxes');
const uiFlags = useMapGetter('clients/getUIFlags');

const whatsappInboxes = computed(() => {
  const all = inboxes.value || [];
  const wa = all.filter(inbox => inbox.channel_type === 'Channel::Whatsapp');
  return wa.length > 0 ? wa : all;
});

const isFormValid = computed(() => {
  const cleanUsername = username.value.trim().toLowerCase();
  const validUsernameRegex = /^[a-zA-Z0-9_]{3,30}$/;
  return (
    name.value.trim().length > 0 &&
    validUsernameRegex.test(cleanUsername) &&
    password.value.length >= 6
  );
});

const toggleInbox = inboxId => {
  if (selectedInboxIds.value.includes(inboxId)) {
    selectedInboxIds.value = selectedInboxIds.value.filter(id => id !== inboxId);
  } else {
    selectedInboxIds.value.push(inboxId);
  }
};

const addClient = async () => {
  if (!isFormValid.value) return;
  errorMessage.value = '';

  try {
    await store.dispatch('clients/create', {
      name: name.value.trim(),
      username: username.value.trim().toLowerCase(),
      password: password.value,
      inbox_ids: selectedInboxIds.value,
    });
    useAlert('Client added successfully');
    emit('close');
  } catch (error) {
    const errorMsg =
      error?.response?.data?.message ||
      error?.message ||
      'Could not add client. Please try again.';
    errorMessage.value = errorMsg;
    useAlert(errorMsg);
  }
};
</script>

<template>
  <div class="flex flex-col h-auto overflow-auto">
    <woot-modal-header header-title="Add Client" />
    <form class="w-full p-6 space-y-4" @submit.prevent="addClient">
      <div>
        <label class="block text-sm font-medium text-n-slate-12 mb-1">
          Full Name
        </label>
        <input
          v-model="name"
          type="text"
          placeholder="Client Name (e.g. John Doe)"
          class="w-full px-3 py-2 border rounded-md border-n-slate-6 bg-n-alpha-1 text-n-slate-12 text-sm focus:outline-none focus:ring-1 focus:ring-n-brand"
          required
        />
      </div>

      <div>
        <label class="block text-sm font-medium text-n-slate-12 mb-1">
          Username
        </label>
        <input
          v-model="username"
          type="text"
          placeholder="username (letters, numbers, underscore only)"
          class="w-full px-3 py-2 border rounded-md border-n-slate-6 bg-n-alpha-1 text-n-slate-12 text-sm focus:outline-none focus:ring-1 focus:ring-n-brand"
          pattern="[a-zA-Z0-9_]{3,30}"
          required
        />
        <p class="text-xs text-n-slate-10 mt-1">
          Client will use this username to log in at /client/login.
        </p>
      </div>

      <div>
        <label class="block text-sm font-medium text-n-slate-12 mb-1">
          Password
        </label>
        <input
          v-model="password"
          type="password"
          placeholder="Initial password (min 6 characters)"
          class="w-full px-3 py-2 border rounded-md border-n-slate-6 bg-n-alpha-1 text-n-slate-12 text-sm focus:outline-none focus:ring-1 focus:ring-n-brand"
          minlength="6"
          required
        />
        <p class="text-xs text-n-slate-10 mt-1">
          Only administrators can view or reset client passwords.
        </p>
      </div>

      <div>
        <label class="block text-sm font-medium text-n-slate-12 mb-1">
          Assign WhatsApp Inboxes
        </label>
        <div v-if="whatsappInboxes.length === 0" class="text-sm text-n-slate-10 italic">
          No WhatsApp inboxes found. Please create a WhatsApp inbox in Settings &rarr; Inboxes first.
        </div>
        <div v-else class="space-y-2 border rounded-md p-3 border-n-slate-6 bg-n-alpha-1 max-h-40 overflow-y-auto">
          <label
            v-for="inbox in whatsappInboxes"
            :key="inbox.id"
            class="flex items-center space-x-2 cursor-pointer text-sm text-n-slate-12"
          >
            <input
              type="checkbox"
              :checked="selectedInboxIds.includes(inbox.id)"
              class="rounded border-n-slate-6 text-n-brand focus:ring-n-brand"
              @change="toggleInbox(inbox.id)"
            />
            <span>{{ inbox.name }}</span>
          </label>
        </div>
        <p class="text-xs text-n-slate-10 mt-1">
          Clients will only see and reply to conversations from assigned inboxes.
        </p>
      </div>

      <div v-if="errorMessage" class="text-xs text-red-500 font-medium">
        {{ errorMessage }}
      </div>

      <div class="flex justify-end gap-2 pt-4">
        <Button
          type="button"
          variant="faded"
          color="slate"
          label="Cancel"
          @click="emit('close')"
        />
        <Button
          type="submit"
          :is-loading="uiFlags.isCreating"
          :disabled="!isFormValid || uiFlags.isCreating"
          label="Add Client"
        />
      </div>
    </form>
  </div>
</template>
