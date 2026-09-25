<script setup>
import { ref, computed } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  client: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['close']);
const store = useStore();

const name = ref(props.client.name || '');
const username = ref(props.client.username || '');
const newPassword = ref('');
const showPassword = ref(false);
const selectedInboxIds = ref([...(props.client.inbox_ids || [])]);
const errorMessage = ref('');

const inboxes = useMapGetter('inboxes/getInboxes');
const uiFlags = useMapGetter('clients/getUIFlags');

const whatsappInboxes = computed(() => {
  const all = inboxes.value || [];
  const wa = all.filter(inbox => inbox.channel_type === 'Channel::Whatsapp');
  return wa.length > 0 ? wa : all;
});

const toggleInbox = inboxId => {
  if (selectedInboxIds.value.includes(inboxId)) {
    selectedInboxIds.value = selectedInboxIds.value.filter(id => id !== inboxId);
  } else {
    selectedInboxIds.value.push(inboxId);
  }
};

const updateClient = async () => {
  if (!name.value.trim()) return;
  if (newPassword.value && newPassword.value.length < 6) {
    errorMessage.value = 'Password must be at least 6 characters.';
    return;
  }
  errorMessage.value = '';

  try {
    const payload = {
      id: props.client.id,
      name: name.value.trim(),
      inbox_ids: selectedInboxIds.value,
    };
    if (newPassword.value) {
      payload.password = newPassword.value;
    }

    await store.dispatch('clients/update', payload);
    useAlert('Client updated successfully');
    emit('close');
  } catch (error) {
    const errorMsg =
      error?.response?.data?.error ||
      error?.response?.data?.message ||
      error?.message ||
      'Could not update client. Please try again.';
    errorMessage.value = errorMsg;
    useAlert(errorMsg);
  }
};
</script>

<template>
  <div class="flex flex-col h-auto overflow-auto">
    <woot-modal-header :header-title="`Edit Client - ${props.client.name}`" />
    <form class="w-full p-6 space-y-4" @submit.prevent="updateClient">
      <div>
        <label class="block text-sm font-medium text-n-slate-12 mb-1">
          Full Name
        </label>
        <input
          v-model="name"
          type="text"
          class="w-full px-3 py-2 border rounded-md border-n-slate-6 bg-n-alpha-1 text-n-slate-12 text-sm focus:outline-none focus:ring-1 focus:ring-n-brand"
          required
        />
      </div>

      <div>
        <label class="block text-sm font-medium text-n-slate-12 mb-1">
          Username
        </label>
        <input
          :value="username"
          type="text"
          disabled
          class="w-full px-3 py-2 border rounded-md border-n-slate-6 bg-n-alpha-2 text-n-slate-10 text-sm cursor-not-allowed"
        />
        <p class="text-xs text-n-slate-10 mt-1">
          Username cannot be changed.
        </p>
      </div>

      <div>
        <label class="block text-sm font-medium text-n-slate-12 mb-1">
          Reset Password (Admin Only)
        </label>
        <div class="relative flex items-center">
          <input
            v-model="newPassword"
            :type="showPassword ? 'text' : 'password'"
            placeholder="Leave blank to keep existing password"
            minlength="6"
            class="w-full px-3 py-2 pr-10 border rounded-md border-n-slate-6 bg-n-alpha-1 text-n-slate-12 text-sm focus:outline-none focus:ring-1 focus:ring-n-brand"
          />
          <button
            type="button"
            class="absolute right-2.5 p-1 text-n-slate-10 hover:text-n-slate-12 transition-colors focus:outline-none"
            :aria-label="showPassword ? 'Hide password' : 'Show password'"
            @click="showPassword = !showPassword"
          >
            <span :class="showPassword ? 'i-lucide-eye-off' : 'i-lucide-eye'" class="text-base block" />
          </button>
        </div>
        <p class="text-xs text-n-slate-10 mt-1">
          Enter a new password (min 6 chars, uppercase, lowercase, number, symbol) to reset this client's password.
        </p>
      </div>

      <div>
        <label class="block text-sm font-medium text-n-slate-12 mb-1">
          Assigned WhatsApp Inboxes
        </label>
        <div v-if="whatsappInboxes.length === 0" class="text-sm text-n-slate-10 italic">
          No WhatsApp inboxes found.
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
          :is-loading="uiFlags.isUpdating"
          :disabled="!name.trim() || uiFlags.isUpdating"
          label="Save Changes"
        />
      </div>
    </form>
  </div>
</template>
