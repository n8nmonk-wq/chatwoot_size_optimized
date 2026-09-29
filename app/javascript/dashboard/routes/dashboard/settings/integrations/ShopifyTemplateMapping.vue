<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Select from 'dashboard/components-next/select/Select.vue';
import Input from 'dashboard/components-next/input/Input.vue';

const props = defineProps({
  inboxId: {
    type: [Number, String],
    default: null,
  },
  kind: {
    type: String,
    required: true,
  },
  modelValue: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();

const getFilteredWhatsAppTemplates = useMapGetter(
  'inboxes/getFilteredWhatsAppTemplates'
);

const templates = computed(() => {
  if (
    !props.inboxId ||
    typeof getFilteredWhatsAppTemplates.value !== 'function'
  ) {
    return [];
  }
  return getFilteredWhatsAppTemplates.value(props.inboxId) || [];
});

const isMediaHeader = template => {
  const header = template?.components?.find(c => c.type === 'HEADER');
  return ['IMAGE', 'VIDEO', 'DOCUMENT'].includes(header?.format);
};

const templateOptions = computed(() => {
  return templates.value.map(tmpl => {
    const hasMedia = isMediaHeader(tmpl);
    const friendlyName = (tmpl.name || '').replace(/_/g, ' ');
    const lang = tmpl.language || 'en';
    const label = hasMedia
      ? `${friendlyName} (${lang}) - ${t('INTEGRATION_SETTINGS.SHOPIFY.TEMPLATE_MAPPING.MEDIA_NOT_SUPPORTED')}`
      : `${friendlyName} (${lang})`;

    return {
      value: `${tmpl.name}|${lang}`,
      label,
      disabled: hasMedia,
    };
  });
});

const extractSlots = template => {
  if (!template?.components) return [];
  const slots = [];
  template.components.forEach(component => {
    const type = component.type?.toUpperCase();
    if (
      type === 'HEADER' &&
      component.format?.toUpperCase() === 'TEXT' &&
      component.text
    ) {
      const matches = component.text.match(/{{([^}]+)}}/g) || [];
      matches.forEach(m => {
        const varName = m.replace(/[{}]/g, '').trim();
        slots.push({
          slot: `header.${varName}`,
          label: `Header {{${varName}}}`,
          type: 'header',
        });
      });
    } else if (type === 'BODY' && component.text) {
      const matches = component.text.match(/{{([^}]+)}}/g) || [];
      matches.forEach(m => {
        const varName = m.replace(/[{}]/g, '').trim();
        slots.push({
          slot: `body.${varName}`,
          label: `Body {{${varName}}}`,
          type: 'body',
        });
      });
    } else if (type === 'BUTTONS' && Array.isArray(component.buttons)) {
      component.buttons.forEach((btn, idx) => {
        if (btn.type?.toUpperCase() === 'URL' && btn.url?.includes('{{')) {
          slots.push({
            slot: `button.${idx}`,
            label: `Button ${idx + 1} URL suffix`,
            type: 'button',
          });
        }
      });
    }
  });
  return slots;
};

const selectedTemplateKey = computed({
  get() {
    if (!props.modelValue?.template_name) return '';
    return `${props.modelValue.template_name}|${props.modelValue.language || 'en'}`;
  },
  set(val) {
    if (!val) {
      emit('update:modelValue', {
        template_name: '',
        language: 'en',
        variables: {},
      });
      return;
    }
    const [name, lang] = val.split('|');
    const tmpl = templates.value.find(
      tmplItem => tmplItem.name === name && (tmplItem.language || 'en') === lang
    );
    const required = extractSlots(tmpl);
    const newVars = {};
    required.forEach(s => {
      newVars[s.slot] = props.modelValue?.variables?.[s.slot] || '';
    });
    emit('update:modelValue', {
      template_name: name,
      language: lang,
      variables: newVars,
    });
  },
});

const activeTemplate = computed(() => {
  if (!props.modelValue?.template_name) return null;
  return templates.value.find(
    tmplItem =>
      tmplItem.name === props.modelValue.template_name &&
      (tmplItem.language || 'en') === (props.modelValue.language || 'en')
  );
});

const requiredSlots = computed(() => extractSlots(activeTemplate.value));

const getSourcesForSlot = slot => {
  const isButton = slot.type === 'button';
  const isOrderMilestone = [
    'confirmed',
    'shipped',
    'out_for_delivery',
    'delivered',
  ].includes(props.kind);
  const isTrackingMilestone = [
    'shipped',
    'out_for_delivery',
    'delivered',
  ].includes(props.kind);

  if (isButton) {
    if (props.kind === 'abandoned_cart') {
      return [
        {
          value: 'checkout_url_suffix',
          label: t('INTEGRATION_SETTINGS.SHOPIFY.SOURCES.CHECKOUT_URL_SUFFIX'),
        },
      ];
    }
    return [
      {
        value: 'order_status_url_suffix',
        label: t(
          'INTEGRATION_SETTINGS.SHOPIFY.SOURCES.ORDER_STATUS_URL_SUFFIX'
        ),
      },
    ];
  }

  const sources = [
    {
      value: 'first_name',
      label: t('INTEGRATION_SETTINGS.SHOPIFY.SOURCES.FIRST_NAME'),
    },
    {
      value: 'full_name',
      label: t('INTEGRATION_SETTINGS.SHOPIFY.SOURCES.FULL_NAME'),
    },
    {
      value: 'store_name',
      label: t('INTEGRATION_SETTINGS.SHOPIFY.SOURCES.STORE_NAME'),
    },
    {
      value: 'item_summary',
      label: t('INTEGRATION_SETTINGS.SHOPIFY.SOURCES.ITEM_SUMMARY'),
    },
    { value: 'total', label: t('INTEGRATION_SETTINGS.SHOPIFY.SOURCES.TOTAL') },
  ];

  if (isOrderMilestone) {
    sources.push({
      value: 'order_name',
      label: t('INTEGRATION_SETTINGS.SHOPIFY.SOURCES.ORDER_NAME'),
    });
  }

  if (isTrackingMilestone) {
    sources.push(
      {
        value: 'tracking_number',
        label: t('INTEGRATION_SETTINGS.SHOPIFY.SOURCES.TRACKING_NUMBER'),
      },
      {
        value: 'courier',
        label: t('INTEGRATION_SETTINGS.SHOPIFY.SOURCES.COURIER'),
      }
    );
  }

  sources.push({
    value: 'static',
    label: t('INTEGRATION_SETTINGS.SHOPIFY.SOURCES.STATIC'),
  });
  return sources;
};

const getVariableSourceType = slotKey => {
  const current = props.modelValue?.variables?.[slotKey];
  if (current && typeof current === 'object' && 'static' in current) {
    return 'static';
  }
  return current || '';
};

const getStaticValue = slotKey => {
  const current = props.modelValue?.variables?.[slotKey];
  if (current && typeof current === 'object' && 'static' in current) {
    return current.static;
  }
  return '';
};

const updateSlotSource = (slotKey, newSourceType) => {
  const vars = { ...(props.modelValue?.variables || {}) };
  if (newSourceType === 'static') {
    vars[slotKey] = { static: '' };
  } else {
    vars[slotKey] = newSourceType;
  }
  emit('update:modelValue', {
    ...props.modelValue,
    variables: vars,
  });
};

const updateStaticText = (slotKey, text) => {
  const vars = { ...(props.modelValue?.variables || {}) };
  vars[slotKey] = { static: text };
  emit('update:modelValue', {
    ...props.modelValue,
    variables: vars,
  });
};
</script>

<template>
  <div
    class="flex flex-col gap-3 p-4 rounded-lg bg-n-alpha-black2 border border-n-weak"
  >
    <div class="flex flex-col gap-1.5">
      <label class="text-xs font-medium text-n-slate-12">
        {{ t('INTEGRATION_SETTINGS.SHOPIFY.TEMPLATE_MAPPING.TEMPLATE_LABEL') }}
      </label>
      <Select
        v-model="selectedTemplateKey"
        :options="templateOptions"
        :placeholder="
          t(
            'INTEGRATION_SETTINGS.SHOPIFY.TEMPLATE_MAPPING.TEMPLATE_PLACEHOLDER'
          )
        "
        class="w-full"
      />
    </div>

    <!-- Variables Mapping Section -->
    <div
      v-if="requiredSlots.length > 0"
      class="flex flex-col gap-3 pt-2 border-t border-n-weak"
    >
      <span
        class="text-xs font-semibold text-n-slate-11 uppercase tracking-wider"
      >
        {{ t('INTEGRATION_SETTINGS.SHOPIFY.TEMPLATE_MAPPING.VARIABLES_TITLE') }}
      </span>

      <div
        v-for="slot in requiredSlots"
        :key="slot.slot"
        class="flex flex-col gap-2 p-2.5 rounded-md bg-n-surface-1 border border-n-weak"
      >
        <div class="flex items-center justify-between">
          <span class="text-xs font-medium text-n-slate-12">
            {{ slot.label }}
          </span>
          <span class="text-[11px] text-n-slate-10 font-mono">
            {{ slot.slot }}
          </span>
        </div>

        <div class="flex flex-col gap-2 sm:flex-row sm:items-center">
          <Select
            :model-value="getVariableSourceType(slot.slot)"
            :options="getSourcesForSlot(slot)"
            :placeholder="
              t('INTEGRATION_SETTINGS.SHOPIFY.TEMPLATE_MAPPING.SELECT_SOURCE')
            "
            class="w-full sm:w-1/2"
            @update:model-value="val => updateSlotSource(slot.slot, val)"
          />

          <Input
            v-if="getVariableSourceType(slot.slot) === 'static'"
            :model-value="getStaticValue(slot.slot)"
            :placeholder="
              t(
                'INTEGRATION_SETTINGS.SHOPIFY.TEMPLATE_MAPPING.STATIC_PLACEHOLDER'
              )
            "
            class="w-full sm:w-1/2 !mb-0"
            @input="e => updateStaticText(slot.slot, e.target.value)"
          />
        </div>
      </div>
    </div>
  </div>
</template>
