<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import ShopifyAPI from 'dashboard/api/integrations/shopify';
import integrationAPI from 'dashboard/api/integrations';

import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import ShopifyTemplateMapping from './ShopifyTemplateMapping.vue';

defineProps({
  error: {
    type: String,
    default: '',
  },
});

const { t } = useI18n();
const store = useStore();

const isLoading = ref(true);
const isSaving = ref(false);
const isSavingOrderUpdates = ref(false);
const isRegisteringWebhooks = ref(false);
const webhookRegistrationResult = ref(null);
const isSubmittingStoreUrl = ref(false);
const isDisconnecting = ref(false);

const hookData = ref({ connected: false });

const connectDialogRef = ref(null);
const disconnectDialogRef = ref(null);

const storeUrl = ref('');
const storeUrlError = ref('');

// Reminder settings form fields
const enabled = ref(false);
const inboxId = ref('');
const templateName = ref('');
const language = ref('en');
const cartTemplate = ref({
  template_name: '',
  language: 'en',
  variables: {},
});
const storeDomain = ref('');
const requireMarketingConsent = ref(false);
const testPhones = ref('');
const delayHours = ref(24);

// Order updates form fields
const orderUpdatesEnabled = ref(false);
const orderUpdatesInboxId = ref('');
const MILESTONE_KINDS = [
  'confirmed',
  'shipped',
  'out_for_delivery',
  'delivered',
];
const milestoneConfigs = computed(() => [
  {
    key: 'confirmed',
    title: t(
      'INTEGRATION_SETTINGS.SHOPIFY.ORDER_UPDATES.MILESTONES.CONFIRMED.TITLE'
    ),
    description: t(
      'INTEGRATION_SETTINGS.SHOPIFY.ORDER_UPDATES.MILESTONES.CONFIRMED.DESCRIPTION'
    ),
  },
  {
    key: 'shipped',
    title: t(
      'INTEGRATION_SETTINGS.SHOPIFY.ORDER_UPDATES.MILESTONES.SHIPPED.TITLE'
    ),
    description: t(
      'INTEGRATION_SETTINGS.SHOPIFY.ORDER_UPDATES.MILESTONES.SHIPPED.DESCRIPTION'
    ),
  },
  {
    key: 'out_for_delivery',
    title: t(
      'INTEGRATION_SETTINGS.SHOPIFY.ORDER_UPDATES.MILESTONES.OUT_FOR_DELIVERY.TITLE'
    ),
    description: t(
      'INTEGRATION_SETTINGS.SHOPIFY.ORDER_UPDATES.MILESTONES.OUT_FOR_DELIVERY.DESCRIPTION'
    ),
  },
  {
    key: 'delivered',
    title: t(
      'INTEGRATION_SETTINGS.SHOPIFY.ORDER_UPDATES.MILESTONES.DELIVERED.TITLE'
    ),
    description: t(
      'INTEGRATION_SETTINGS.SHOPIFY.ORDER_UPDATES.MILESTONES.DELIVERED.DESCRIPTION'
    ),
  },
]);
const milestones = ref({
  confirmed: { enabled: false, template: null },
  shipped: { enabled: false, template: null },
  out_for_delivery: { enabled: false, template: null },
  delivered: { enabled: false, template: null },
});

const inboxesList = useMapGetter('inboxes/getInboxes');

const whatsappInboxes = computed(() => {
  return inboxesList.value.filter(
    inbox => inbox.channel_type === 'Channel::Whatsapp'
  );
});

const whatsappInboxOptions = computed(() => {
  return whatsappInboxes.value.map(inbox => ({
    value: inbox.id,
    label: inbox.name,
  }));
});

const hasTestPhones = computed(() => {
  return testPhones.value.trim().length > 0;
});

const validateStoreUrl = url => {
  const pattern = /^[a-zA-Z0-9][a-zA-Z0-9-]*\.myshopify\.com$/;
  return pattern.test(url);
};

const openConnectDialog = () => {
  storeUrl.value = '';
  storeUrlError.value = '';
  connectDialogRef.value?.open();
};

const closeConnectDialog = () => {
  connectDialogRef.value?.close();
  storeUrl.value = '';
  storeUrlError.value = '';
};

const openDisconnectDialog = () => {
  disconnectDialogRef.value?.open();
};

const closeDisconnectDialog = () => {
  disconnectDialogRef.value?.close();
};

const populateFormSettings = data => {
  hookData.value = data;
  if (!data?.connected) {
    return;
  }

  const cart = data.settings?.abandoned_cart || data.abandoned_cart || {};
  enabled.value = Boolean(cart.enabled);
  inboxId.value = cart.inbox_id ?? '';
  templateName.value = cart.template_name || '';
  language.value = cart.language || 'en';
  cartTemplate.value = cart.template || {
    template_name: cart.template_name || '',
    language: cart.language || 'en',
    variables: {},
  };
  storeDomain.value = cart.store_domain || '';
  requireMarketingConsent.value = Boolean(cart.require_marketing_consent);
  testPhones.value = Array.isArray(cart.test_phones)
    ? cart.test_phones.join(', ')
    : '';
  delayHours.value = cart.delay_hours || 24;

  const orders = data.settings?.order_updates || {};
  orderUpdatesEnabled.value = Boolean(orders.enabled);
  orderUpdatesInboxId.value = orders.inbox_id ?? '';
  MILESTONE_KINDS.forEach(kind => {
    const m = orders.milestones?.[kind] || {};
    milestones.value[kind] = {
      enabled: Boolean(m.enabled),
      template: m.template || null,
    };
  });
};

const fetchSettings = async () => {
  try {
    isLoading.value = true;
    const { data } = await ShopifyAPI.get();
    populateFormSettings(data);
  } catch (error) {
    hookData.value = { connected: false };
  } finally {
    isLoading.value = false;
  }
};

const handleConnectSubmit = async () => {
  try {
    storeUrlError.value = '';
    const cleanUrl = storeUrl.value.trim();
    if (!validateStoreUrl(cleanUrl)) {
      storeUrlError.value = t('INTEGRATION_SETTINGS.SHOPIFY.STORE_URL.HELP');
      return;
    }

    isSubmittingStoreUrl.value = true;
    const { data } = await integrationAPI.connectShopify({
      shopDomain: cleanUrl,
    });

    if (data.redirect_url) {
      window.location.href = data.redirect_url;
    }
  } catch (error) {
    storeUrlError.value =
      error?.response?.data?.error ||
      error?.response?.data?.message ||
      t('INTEGRATION_SETTINGS.SHOPIFY.ERROR');
  } finally {
    isSubmittingStoreUrl.value = false;
  }
};

const handleDisconnect = async () => {
  try {
    isDisconnecting.value = true;
    await ShopifyAPI.disconnect();
    hookData.value = { connected: false };
    closeDisconnectDialog();
    useAlert(t('INTEGRATION_SETTINGS.SHOPIFY.DISCONNECT.SUCCESS'));
  } catch (error) {
    useAlert(t('INTEGRATION_SETTINGS.SHOPIFY.DISCONNECT.ERROR'));
  } finally {
    isDisconnecting.value = false;
  }
};

const handleSaveSettings = async () => {
  try {
    isSaving.value = true;

    const parsedTestPhones = testPhones.value
      .split(',')
      .map(p => p.trim())
      .filter(p => p.length > 0);

    const payload = {
      abandoned_cart: {
        enabled: enabled.value,
        inbox_id: inboxId.value ? Number(inboxId.value) : null,
        template_name:
          cartTemplate.value?.template_name || templateName.value.trim(),
        language: cartTemplate.value?.language || language.value.trim(),
        store_domain: storeDomain.value.trim(),
        require_marketing_consent: requireMarketingConsent.value,
        test_phones: parsedTestPhones,
        delay_hours: Number(delayHours.value) || 24,
      },
    };

    if (cartTemplate.value?.template_name) {
      payload.abandoned_cart.template = cartTemplate.value;
    }

    const { data } = await ShopifyAPI.update(payload);
    populateFormSettings(data);
    useAlert(t('INTEGRATION_SETTINGS.SHOPIFY.REMINDERS.SAVE_SUCCESS'));
  } catch (error) {
    const errorMsg =
      error?.response?.data?.error ||
      error?.response?.data?.message ||
      t('INTEGRATION_SETTINGS.SHOPIFY.REMINDERS.SAVE_ERROR');
    useAlert(errorMsg);
  } finally {
    isSaving.value = false;
  }
};

const handleSaveOrderUpdates = async () => {
  try {
    isSavingOrderUpdates.value = true;
    const milestonePayload = {};
    MILESTONE_KINDS.forEach(kind => {
      const m = milestones.value[kind];
      milestonePayload[kind] = {
        enabled: m.enabled,
        template: m.template,
      };
    });

    const payload = {
      order_updates: {
        enabled: orderUpdatesEnabled.value,
        inbox_id: orderUpdatesInboxId.value
          ? Number(orderUpdatesInboxId.value)
          : null,
        milestones: milestonePayload,
      },
    };

    const { data } = await ShopifyAPI.update(payload);
    populateFormSettings(data);
    useAlert(t('INTEGRATION_SETTINGS.SHOPIFY.ORDER_UPDATES.SAVE_SUCCESS'));
  } catch (error) {
    const errorMsg =
      error?.response?.data?.error ||
      error?.response?.data?.message ||
      t('INTEGRATION_SETTINGS.SHOPIFY.ORDER_UPDATES.SAVE_ERROR');
    useAlert(errorMsg);
  } finally {
    isSavingOrderUpdates.value = false;
  }
};

const handleRegisterWebhooks = async () => {
  try {
    isRegisteringWebhooks.value = true;
    webhookRegistrationResult.value = null;
    const { data } = await ShopifyAPI.registerWebhooks();
    webhookRegistrationResult.value = {
      success: true,
      message: t(
        'INTEGRATION_SETTINGS.SHOPIFY.ORDER_UPDATES.REGISTER_WEBHOOKS.SUCCESS'
      ),
      results: data.results,
    };
    useAlert(
      t('INTEGRATION_SETTINGS.SHOPIFY.ORDER_UPDATES.REGISTER_WEBHOOKS.SUCCESS')
    );
  } catch (error) {
    const errorMsg =
      error?.response?.data?.error ||
      error?.response?.data?.message ||
      'Failed to register webhooks';
    webhookRegistrationResult.value = {
      success: false,
      error: errorMsg,
    };
    useAlert(errorMsg);
  } finally {
    isRegisteringWebhooks.value = false;
  }
};

onMounted(async () => {
  await store.dispatch('inboxes/get');
  await fetchSettings();
});
</script>

<template>
  <SettingsLayout :is-loading="isLoading">
    <template #header>
      <BaseSettingsHeader
        :title="$t('INTEGRATION_SETTINGS.SHOPIFY.HEADER')"
        :description="$t('INTEGRATION_SETTINGS.SHOPIFY.DESCRIPTION')"
        feature-name="shopify_integration"
      />
    </template>
    <template #body>
      <div class="flex flex-col gap-6">
        <!-- Error State Notice from OAuth callback -->
        <div
          v-if="error"
          class="flex items-center gap-3 p-4 rounded-xl border border-n-ruby-6 bg-n-ruby-2 text-n-ruby-11 text-sm"
        >
          <Icon icon="i-lucide-alert-circle" class="size-5 shrink-0" />
          <p class="m-0">
            {{ t('INTEGRATION_SETTINGS.SHOPIFY.ERROR') }}
          </p>
        </div>

        <!-- Connection Card -->
        <div
          class="flex flex-col items-start justify-between lg:flex-row lg:items-center p-6 outline outline-n-container outline-1 bg-n-card rounded-xl gap-6"
        >
          <div
            class="flex items-start lg:items-center justify-start flex-1 m-0 gap-6 flex-col lg:flex-row"
          >
            <div
              class="flex h-16 w-16 items-center justify-center flex-shrink-0 rounded-xl bg-n-alpha-2 border border-n-weak text-n-brand"
            >
              <Icon icon="i-lucide-shopping-bag" class="size-8" />
            </div>
            <div class="flex flex-col gap-1">
              <div class="flex items-center gap-3">
                <h3 class="m-0 text-heading-1 text-n-slate-12">
                  {{ t('INTEGRATION_SETTINGS.SHOPIFY.HEADER') }}
                </h3>
                <span
                  v-if="hookData.connected"
                  class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-n-teal-3 text-n-teal-11"
                >
                  {{ t('INTEGRATION_SETTINGS.SHOPIFY.CONNECTED') }}
                </span>
                <span
                  v-else
                  class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-n-slate-3 text-n-slate-11"
                >
                  {{ t('INTEGRATION_SETTINGS.SHOPIFY.NOT_CONNECTED') }}
                </span>
              </div>
              <p class="m-0 text-n-slate-11 text-body-main">
                {{ t('INTEGRATION_SETTINGS.SHOPIFY.DESCRIPTION') }}
              </p>
              <p
                v-if="hookData.connected && hookData.reference_id"
                class="m-0 text-sm font-medium text-n-slate-12"
              >
                {{
                  t('INTEGRATION_SETTINGS.SHOPIFY.STORE_DOMAIN', {
                    shop: hookData.reference_id,
                  })
                }}
              </p>
            </div>
          </div>
          <div class="flex items-center">
            <Button
              v-if="hookData.connected"
              ruby
              faded
              :label="t('INTEGRATION_SETTINGS.SHOPIFY.DISCONNECT.BUTTON_TEXT')"
              @click="openDisconnectDialog"
            />
            <Button
              v-else
              teal
              :label="t('INTEGRATION_SETTINGS.SHOPIFY.STORE_URL.SUBMIT')"
              @click="openConnectDialog"
            />
          </div>
        </div>

        <!-- Reminders Section (when connected) -->
        <div
          v-if="hookData.connected"
          class="flex flex-col p-6 outline outline-n-container outline-1 bg-n-card rounded-xl gap-6"
        >
          <div class="flex flex-col gap-1">
            <h3 class="m-0 text-heading-2 text-n-slate-12">
              {{ t('INTEGRATION_SETTINGS.SHOPIFY.REMINDERS.TITLE') }}
            </h3>
            <p class="m-0 text-n-slate-11 text-body-main">
              {{ t('INTEGRATION_SETTINGS.SHOPIFY.REMINDERS.DESCRIPTION') }}
            </p>
          </div>

          <!-- Test Mode Banner -->
          <div
            v-if="hasTestPhones"
            class="flex items-center gap-3 p-4 rounded-xl border border-n-amber-6 bg-n-amber-2 text-n-amber-11 text-sm font-medium"
          >
            <Icon icon="i-lucide-info" class="size-5 shrink-0" />
            <span>{{
              t('INTEGRATION_SETTINGS.SHOPIFY.REMINDERS.TEST_MODE_NOTICE')
            }}</span>
          </div>

          <div
            class="flex items-center justify-between py-3 border-b border-n-weak"
          >
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('INTEGRATION_SETTINGS.SHOPIFY.REMINDERS.ENABLE') }}
            </span>
            <Switch v-model="enabled" />
          </div>

          <div v-if="enabled" class="flex flex-col gap-5">
            <div class="flex flex-col gap-1.5">
              <label class="text-sm font-medium text-n-slate-12">
                {{ t('INTEGRATION_SETTINGS.SHOPIFY.REMINDERS.INBOX.LABEL') }}
              </label>
              <Select
                v-model="inboxId"
                :options="whatsappInboxOptions"
                :placeholder="
                  t('INTEGRATION_SETTINGS.SHOPIFY.REMINDERS.INBOX.PLACEHOLDER')
                "
                class="w-full"
              />
              <span class="text-xs text-n-slate-11">
                {{ t('INTEGRATION_SETTINGS.SHOPIFY.REMINDERS.INBOX.HELP') }}
              </span>
            </div>

            <div class="flex flex-col gap-1.5">
              <label class="text-sm font-medium text-n-slate-12">
                {{
                  t(
                    'INTEGRATION_SETTINGS.SHOPIFY.TEMPLATE_MAPPING.TEMPLATE_LABEL'
                  )
                }}
              </label>
              <ShopifyTemplateMapping
                v-model="cartTemplate"
                :inbox-id="inboxId"
                kind="abandoned_cart"
              />
            </div>

            <Input
              v-model="storeDomain"
              :label="
                t('INTEGRATION_SETTINGS.SHOPIFY.REMINDERS.STORE_DOMAIN.LABEL')
              "
              :placeholder="
                t(
                  'INTEGRATION_SETTINGS.SHOPIFY.REMINDERS.STORE_DOMAIN.PLACEHOLDER'
                )
              "
              :message="
                t('INTEGRATION_SETTINGS.SHOPIFY.REMINDERS.STORE_DOMAIN.HELP')
              "
            />

            <div
              class="flex items-center justify-between py-3 border-b border-n-weak"
            >
              <div class="flex flex-col gap-0.5">
                <span class="text-sm font-medium text-n-slate-12">
                  {{
                    t(
                      'INTEGRATION_SETTINGS.SHOPIFY.REMINDERS.MARKETING_CONSENT.LABEL'
                    )
                  }}
                </span>
                <span class="text-xs text-n-slate-11">
                  {{
                    t(
                      'INTEGRATION_SETTINGS.SHOPIFY.REMINDERS.MARKETING_CONSENT.HELP'
                    )
                  }}
                </span>
              </div>
              <Switch v-model="requireMarketingConsent" />
            </div>

            <Input
              v-model="testPhones"
              :label="
                t('INTEGRATION_SETTINGS.SHOPIFY.REMINDERS.TEST_PHONES.LABEL')
              "
              :placeholder="
                t(
                  'INTEGRATION_SETTINGS.SHOPIFY.REMINDERS.TEST_PHONES.PLACEHOLDER'
                )
              "
              :message="
                t('INTEGRATION_SETTINGS.SHOPIFY.REMINDERS.TEST_PHONES.HELP')
              "
            />

            <Input
              v-model="delayHours"
              type="number"
              min="1"
              max="72"
              :label="
                t('INTEGRATION_SETTINGS.SHOPIFY.REMINDERS.DELAY_HOURS.LABEL')
              "
              :message="
                t('INTEGRATION_SETTINGS.SHOPIFY.REMINDERS.DELAY_HOURS.HELP')
              "
            />

            <div class="flex justify-end pt-4">
              <Button
                teal
                :is-loading="isSaving"
                :label="t('INTEGRATION_SETTINGS.SHOPIFY.REMINDERS.SAVE_BUTTON')"
                @click="handleSaveSettings"
              />
            </div>
          </div>
        </div>

        <!-- Order Updates Section (when connected) -->
        <div
          v-if="hookData.connected"
          class="flex flex-col p-6 outline outline-n-container outline-1 bg-n-card rounded-xl gap-6"
        >
          <div class="flex flex-col gap-1">
            <h3 class="m-0 text-heading-2 text-n-slate-12">
              {{ t('INTEGRATION_SETTINGS.SHOPIFY.ORDER_UPDATES.TITLE') }}
            </h3>
            <p class="m-0 text-n-slate-11 text-body-main">
              {{ t('INTEGRATION_SETTINGS.SHOPIFY.ORDER_UPDATES.DESCRIPTION') }}
            </p>
          </div>

          <!-- Meta switch-off notice -->
          <div
            class="flex items-center gap-3 p-4 rounded-xl border border-n-amber-6 bg-n-amber-2 text-n-amber-11 text-sm font-medium"
          >
            <Icon icon="i-lucide-alert-triangle" class="size-5 shrink-0" />
            <span>{{
              t('INTEGRATION_SETTINGS.SHOPIFY.ORDER_UPDATES.META_NOTICE')
            }}</span>
          </div>

          <!-- Shared settings notice -->
          <div
            class="flex items-center gap-3 p-4 rounded-xl border border-n-blue-6 bg-n-blue-2 text-n-blue-11 text-sm"
          >
            <Icon icon="i-lucide-info" class="size-5 shrink-0" />
            <span>{{
              t(
                'INTEGRATION_SETTINGS.SHOPIFY.ORDER_UPDATES.SHARED_SETTINGS_NOTICE'
              )
            }}</span>
          </div>

          <div
            class="flex items-center justify-between py-3 border-b border-n-weak"
          >
            <span class="text-sm font-medium text-n-slate-12">
              {{ t('INTEGRATION_SETTINGS.SHOPIFY.ORDER_UPDATES.ENABLE') }}
            </span>
            <Switch v-model="orderUpdatesEnabled" />
          </div>

          <div v-if="orderUpdatesEnabled" class="flex flex-col gap-5">
            <div class="flex flex-col gap-1.5">
              <label class="text-sm font-medium text-n-slate-12">
                {{
                  t('INTEGRATION_SETTINGS.SHOPIFY.ORDER_UPDATES.INBOX.LABEL')
                }}
              </label>
              <Select
                v-model="orderUpdatesInboxId"
                :options="whatsappInboxOptions"
                :placeholder="
                  t(
                    'INTEGRATION_SETTINGS.SHOPIFY.ORDER_UPDATES.INBOX.PLACEHOLDER'
                  )
                "
                class="w-full"
              />
              <span class="text-xs text-n-slate-11">
                {{ t('INTEGRATION_SETTINGS.SHOPIFY.ORDER_UPDATES.INBOX.HELP') }}
              </span>
            </div>

            <!-- Milestones List -->
            <div class="flex flex-col gap-4">
              <div
                v-for="milestone in milestoneConfigs"
                :key="milestone.key"
                class="flex flex-col gap-3 p-4 rounded-xl border border-n-weak bg-n-surface-1"
              >
                <div class="flex items-center justify-between">
                  <div class="flex flex-col gap-0.5">
                    <span class="text-sm font-medium text-n-slate-12">
                      {{ milestone.title }}
                    </span>
                    <span class="text-xs text-n-slate-11">
                      {{ milestone.description }}
                    </span>
                  </div>
                  <Switch v-model="milestones[milestone.key].enabled" />
                </div>

                <div v-if="milestones[milestone.key].enabled" class="pt-2">
                  <ShopifyTemplateMapping
                    v-model="milestones[milestone.key].template"
                    :inbox-id="orderUpdatesInboxId"
                    :kind="milestone.key"
                  />
                </div>
              </div>
            </div>

            <!-- Register Webhooks Action -->
            <div
              class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 pt-3 border-t border-n-weak"
            >
              <div class="flex flex-col gap-0.5">
                <span class="text-sm font-medium text-n-slate-12">
                  {{
                    t(
                      'INTEGRATION_SETTINGS.SHOPIFY.ORDER_UPDATES.REGISTER_WEBHOOKS.BUTTON'
                    )
                  }}
                </span>
                <span
                  v-if="webhookRegistrationResult?.success"
                  class="text-xs text-n-teal-11"
                >
                  {{ webhookRegistrationResult.message }}
                </span>
                <span
                  v-else-if="webhookRegistrationResult?.error"
                  class="text-xs text-n-ruby-11"
                >
                  {{ webhookRegistrationResult.error }}
                </span>
              </div>
              <Button
                faded
                slate
                :is-loading="isRegisteringWebhooks"
                :label="
                  t(
                    'INTEGRATION_SETTINGS.SHOPIFY.ORDER_UPDATES.REGISTER_WEBHOOKS.BUTTON'
                  )
                "
                @click="handleRegisterWebhooks"
              />
            </div>

            <div class="flex justify-end pt-4">
              <Button
                teal
                :is-loading="isSavingOrderUpdates"
                :label="
                  t('INTEGRATION_SETTINGS.SHOPIFY.ORDER_UPDATES.SAVE_BUTTON')
                "
                @click="handleSaveOrderUpdates"
              />
            </div>
          </div>
        </div>

        <!-- Connect Store Dialog -->
        <Dialog
          ref="connectDialogRef"
          :title="t('INTEGRATION_SETTINGS.SHOPIFY.STORE_URL.TITLE')"
          :is-loading="isSubmittingStoreUrl"
          :confirm-button-label="
            t('INTEGRATION_SETTINGS.SHOPIFY.STORE_URL.SUBMIT')
          "
          :cancel-button-label="
            t('INTEGRATION_SETTINGS.SHOPIFY.STORE_URL.CANCEL')
          "
          @confirm="handleConnectSubmit"
          @close="closeConnectDialog"
        >
          <Input
            v-model="storeUrl"
            :label="t('INTEGRATION_SETTINGS.SHOPIFY.STORE_URL.LABEL')"
            :placeholder="
              t('INTEGRATION_SETTINGS.SHOPIFY.STORE_URL.PLACEHOLDER')
            "
            :message="
              !storeUrlError
                ? t('INTEGRATION_SETTINGS.SHOPIFY.STORE_URL.HELP')
                : storeUrlError
            "
            :message-type="storeUrlError ? 'error' : 'info'"
          />
        </Dialog>

        <!-- Disconnect Confirmation Dialog -->
        <Dialog
          ref="disconnectDialogRef"
          type="alert"
          :title="t('INTEGRATION_SETTINGS.SHOPIFY.DISCONNECT.TITLE')"
          :description="t('INTEGRATION_SETTINGS.SHOPIFY.DISCONNECT.MESSAGE')"
          :is-loading="isDisconnecting"
          :confirm-button-label="
            t('INTEGRATION_SETTINGS.SHOPIFY.DISCONNECT.CONFIRM')
          "
          :cancel-button-label="
            t('INTEGRATION_SETTINGS.SHOPIFY.DISCONNECT.CANCEL')
          "
          @confirm="handleDisconnect"
          @close="closeDisconnectDialog"
        />
      </div>
    </template>
  </SettingsLayout>
</template>
