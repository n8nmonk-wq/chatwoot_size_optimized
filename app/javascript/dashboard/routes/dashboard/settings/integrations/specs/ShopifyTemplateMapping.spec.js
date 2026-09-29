import { flushPromises, mount } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import ShopifyTemplateMapping from '../ShopifyTemplateMapping.vue';

const sampleTemplates = [
  {
    name: 'order_confirmed_template',
    language: 'en',
    status: 'APPROVED',
    components: [
      { type: 'HEADER', format: 'TEXT', text: 'Order for {{1}}' },
      { type: 'BODY', text: 'Hi {{1}}, your order {{2}} total is {{3}}' },
      {
        type: 'BUTTONS',
        buttons: [{ type: 'URL', url: 'https://example.com/{{1}}' }],
      },
    ],
  },
  {
    name: 'tracking_template',
    language: 'en',
    status: 'APPROVED',
    components: [
      {
        type: 'BODY',
        text: 'Tracking {{tracking_code}} with {{courier_name}}',
      },
    ],
  },
  {
    name: 'media_template',
    language: 'en',
    status: 'APPROVED',
    components: [
      { type: 'HEADER', format: 'IMAGE' },
      { type: 'BODY', text: 'Hello' },
    ],
  },
];

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: getter => {
    if (getter === 'inboxes/getFilteredWhatsAppTemplates') {
      return {
        value: inboxId => (inboxId === 10 ? sampleTemplates : []),
      };
    }
    return { value: null };
  },
}));

describe('ShopifyTemplateMapping.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('renders template options and disables media header templates', () => {
    const wrapper = mount(ShopifyTemplateMapping, {
      props: {
        inboxId: 10,
        kind: 'confirmed',
        modelValue: {},
      },
      global: {
        stubs: {
          Select: {
            props: ['options', 'modelValue'],
            template: `
              <select :value="modelValue" @change="$emit('update:modelValue', $event.target.value)">
                <option v-for="opt in options" :key="opt.value" :value="opt.value" :disabled="opt.disabled">
                  {{ opt.label }}
                </option>
              </select>
            `,
          },
          Input: true,
        },
        mocks: {
          $t: key => key,
        },
      },
    });

    const options = wrapper.vm.templateOptions;
    expect(options).toHaveLength(3);
    expect(options[0].value).toBe('order_confirmed_template|en');
    expect(options[0].disabled).toBe(false);

    expect(options[2].value).toBe('media_template|en');
    expect(options[2].disabled).toBe(true);
  });

  it('extracts required slots and emits update:modelValue when template is selected', async () => {
    const wrapper = mount(ShopifyTemplateMapping, {
      props: {
        inboxId: 10,
        kind: 'confirmed',
        modelValue: {},
      },
      global: {
        stubs: {
          Select: {
            props: ['options', 'modelValue'],
            template: `
              <select :value="modelValue" @change="$emit('update:modelValue', $event.target.value)">
                <option v-for="opt in options" :key="opt.value" :value="opt.value" :disabled="opt.disabled">
                  {{ opt.label }}
                </option>
              </select>
            `,
          },
          Input: true,
        },
        mocks: {
          $t: key => key,
        },
      },
    });

    wrapper.vm.selectedTemplateKey = 'order_confirmed_template|en';
    await flushPromises();

    expect(wrapper.emitted('update:modelValue')).toBeTruthy();
    const emitted = wrapper.emitted('update:modelValue')[0][0];
    expect(emitted.template_name).toBe('order_confirmed_template');
    expect(emitted.language).toBe('en');
    expect(emitted.variables).toHaveProperty('header.1');
    expect(emitted.variables).toHaveProperty('body.1');
    expect(emitted.variables).toHaveProperty('body.2');
    expect(emitted.variables).toHaveProperty('body.3');
    expect(emitted.variables).toHaveProperty('button.0');
  });

  it('provides button URL suffix for button slots and disallows it for body slots', async () => {
    const wrapper = mount(ShopifyTemplateMapping, {
      props: {
        inboxId: 10,
        kind: 'confirmed',
        modelValue: {
          template_name: 'order_confirmed_template',
          language: 'en',
          variables: {
            'header.1': 'first_name',
            'body.1': 'order_name',
            'button.0': 'order_status_url_suffix',
          },
        },
      },
      global: {
        stubs: {
          Select: true,
          Input: true,
        },
        mocks: {
          $t: key => key,
        },
      },
    });

    const buttonSources = wrapper.vm.getSourcesForSlot({
      slot: 'button.0',
      type: 'button',
    });
    expect(buttonSources.map(s => s.value)).toEqual([
      'order_status_url_suffix',
    ]);

    const bodySources = wrapper.vm.getSourcesForSlot({
      slot: 'body.1',
      type: 'body',
    });
    expect(bodySources.map(s => s.value)).not.toContain(
      'order_status_url_suffix'
    );
    expect(bodySources.map(s => s.value)).toContain('order_name');
    expect(bodySources.map(s => s.value)).toContain('static');
  });

  it('includes tracking sources only for shipped, out_for_delivery, and delivered', () => {
    const confirmedWrapper = mount(ShopifyTemplateMapping, {
      props: {
        inboxId: 10,
        kind: 'confirmed',
        modelValue: {},
      },
      global: { stubs: { Select: true, Input: true } },
    });
    const confirmedSources = confirmedWrapper.vm
      .getSourcesForSlot({ slot: 'body.1', type: 'body' })
      .map(s => s.value);
    expect(confirmedSources).not.toContain('tracking_number');
    expect(confirmedSources).not.toContain('courier');

    const shippedWrapper = mount(ShopifyTemplateMapping, {
      props: {
        inboxId: 10,
        kind: 'shipped',
        modelValue: {},
      },
      global: { stubs: { Select: true, Input: true } },
    });
    const shippedSources = shippedWrapper.vm
      .getSourcesForSlot({ slot: 'body.1', type: 'body' })
      .map(s => s.value);
    expect(shippedSources).toContain('tracking_number');
    expect(shippedSources).toContain('courier');
  });

  it('emits updated variables when slot source is updated', async () => {
    const wrapper = mount(ShopifyTemplateMapping, {
      props: {
        inboxId: 10,
        kind: 'confirmed',
        modelValue: {
          template_name: 'order_confirmed_template',
          language: 'en',
          variables: { 'body.1': '' },
        },
      },
      global: { stubs: { Select: true, Input: true } },
    });

    wrapper.vm.updateSlotSource('body.1', 'first_name');
    await flushPromises();

    expect(wrapper.emitted('update:modelValue')).toBeTruthy();
    const emitted = wrapper.emitted('update:modelValue')[0][0];
    expect(emitted.variables['body.1']).toBe('first_name');
  });

  it('emits static object when static source and text are provided', async () => {
    const wrapper = mount(ShopifyTemplateMapping, {
      props: {
        inboxId: 10,
        kind: 'confirmed',
        modelValue: {
          template_name: 'order_confirmed_template',
          language: 'en',
          variables: { 'body.1': '' },
        },
      },
      global: { stubs: { Select: true, Input: true } },
    });

    wrapper.vm.updateSlotSource('body.1', 'static');
    await flushPromises();
    expect(
      wrapper.emitted('update:modelValue')[0][0].variables['body.1']
    ).toEqual({
      static: '',
    });

    wrapper.vm.updateStaticText('body.1', 'SPECIAL_PROMO');
    await flushPromises();
    expect(
      wrapper.emitted('update:modelValue')[1][0].variables['body.1']
    ).toEqual({
      static: 'SPECIAL_PROMO',
    });
  });
});
