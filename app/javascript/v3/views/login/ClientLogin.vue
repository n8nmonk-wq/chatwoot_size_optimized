<script setup>
import { ref, computed } from 'vue';
import { login } from '../../api/auth';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';

const username = ref('');
const password = ref('');
const isLoading = ref(false);
const errorMessage = ref('');

const isFormValid = computed(() => {
  return username.value.trim().length > 0 && password.value.length > 0;
});

const handleLogin = async () => {
  if (!isFormValid.value || isLoading.value) return;

  isLoading.value = true;
  errorMessage.value = '';

  try {
    const credentials = {
      username: username.value.trim().toLowerCase(),
      password: password.value,
    };

    const result = await login(credentials);
    if (result?.sessionsLimitReached) {
      errorMessage.value = 'Maximum session limit reached. Please contact your administrator.';
      useAlert(errorMessage.value);
    }
  } catch (error) {
    const msg =
      error?.response?.data?.error ||
      error?.message ||
      'Invalid username or password. Please try again.';
    errorMessage.value = msg;
    useAlert(msg);
  } finally {
    isLoading.value = false;
  }
};
</script>

<template>
  <div class="flex min-h-screen w-full items-center justify-center bg-n-surface-1 p-4 sm:p-6 lg:p-8">
    <div class="w-full max-w-md space-y-8 rounded-2xl bg-n-surface-2 p-8 shadow-xl border border-n-slate-4">
      <!-- Header with Logo -->
      <div class="flex flex-col items-center text-center">
        <img
          :src="'/brand-assets/logo_thumbnail.png'"
          alt="MMOChat"
          class="h-16 w-16 rounded-xl object-contain shadow-sm mb-4"
        />
        <h2 class="text-2xl font-bold tracking-tight text-n-slate-12">
          Client Portal Login
        </h2>
        <p class="mt-2 text-sm text-n-slate-10">
          Enter your assigned username and password to view and reply to your WhatsApp chats.
        </p>
      </div>

      <!-- Form -->
      <form class="mt-8 space-y-5" @submit.prevent="handleLogin">
        <div>
          <label class="block text-sm font-medium text-n-slate-12 mb-1.5" for="client-username">
            Username
          </label>
          <input
            id="client-username"
            v-model="username"
            type="text"
            autocomplete="username"
            placeholder="e.g. client1"
            class="w-full rounded-lg border border-n-slate-6 bg-n-alpha-1 px-3.5 py-2.5 text-sm text-n-slate-12 placeholder-n-slate-9 transition focus:border-n-brand focus:outline-none focus:ring-2 focus:ring-n-brand/20"
            required
          />
        </div>

        <div>
          <label class="block text-sm font-medium text-n-slate-12 mb-1.5" for="client-password">
            Password
          </label>
          <input
            id="client-password"
            v-model="password"
            type="password"
            autocomplete="current-password"
            placeholder="&bull;&bull;&bull;&bull;&bull;&bull;&bull;&bull;"
            class="w-full rounded-lg border border-n-slate-6 bg-n-alpha-1 px-3.5 py-2.5 text-sm text-n-slate-12 placeholder-n-slate-9 transition focus:border-n-brand focus:outline-none focus:ring-2 focus:ring-n-brand/20"
            required
          />
        </div>

        <div v-if="errorMessage" class="rounded-lg bg-red-500/10 p-3 text-xs font-medium text-red-500 border border-red-500/20">
          {{ errorMessage }}
        </div>

        <div>
          <Button
            type="submit"
            :is-loading="isLoading"
            :disabled="!isFormValid || isLoading"
            label="Sign In"
            class="w-full justify-center py-2.5 font-medium"
          />
        </div>
      </form>

      <!-- Footer notice -->
      <div class="pt-4 text-center border-t border-n-slate-4">
        <p class="text-xs text-n-slate-9">
          Need access or forgot your password? Please contact your MMOChat administrator.
        </p>
      </div>
    </div>
  </div>
</template>
