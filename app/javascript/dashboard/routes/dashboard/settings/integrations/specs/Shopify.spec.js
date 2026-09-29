import { flushPromises, mount } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import Shopify from '../Shopify.vue';
import ShopifyAPI from 'dashboard/api/integrations/shopify';
import shopifyRoutes from '../shopify.routes';
import { useAlert } from 'dashboard/composables';

vi.mock('dashboard/api/integrations/shopify', () => ({
  default: {
    get: vi.fn(),
    update: vi.fn(),
    disconnect: vi.fn(),
  },
}));

vi.mock('dashboard/api/integrations', () => ({
  default: {
    connectShopify: vi.fn(),
  },
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: getter => {
    if (getter === 'inboxes/getInboxes') {
      return {
        value: [
          { id: 10, name: 'WhatsApp Sales', channel_type: 'Channel::Whatsapp' },
          { id: 20, name: 'Web Widget', channel_type: 'Channel::WebWidget' },
        ],
      };
    }
    return { value: null };
  },
}));

const mockDispatch = vi.fn();
vi.mock('vuex', async importOriginal => {
  const actual = await importOriginal();
  return {
    ...actual,
    useStore: () => ({
      dispatch: mockDispatch,
      getters: {},
    }),
  };
});

describe('Shopify.vue', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('has administrator permissions on the route', () => {
    const route = shopifyRoutes.routes[0].children[0];
    expect(route.name).toBe('settings_integrations_shopify');
    expect(route.meta.permissions).toEqual(['administrator']);
  });

  it('renders not-connected state when hook is not present', async () => {
    ShopifyAPI.get.mockResolvedValue({
      data: { connected: false },
    });

    const wrapper = mount(Shopify, {
      global: {
        stubs: {
          SettingsLayout: {
            template: '<div><slot name="header"/><slot name="body"/></div>',
          },
          BaseSettingsHeader: true,
          Dialog: true,
          Button: true,
          Input: true,
          Switch: true,
          Select: true,
          Icon: true,
        },
        mocks: {
          $t: key => key,
        },
      },
    });

    await flushPromises();

    expect(ShopifyAPI.get).toHaveBeenCalled();
    expect(wrapper.text()).toContain(
      'INTEGRATION_SETTINGS.SHOPIFY.NOT_CONNECTED'
    );
  });

  it('renders connected state and populates reminder settings from real API response shape', async () => {
    ShopifyAPI.get.mockResolvedValue({
      data: {
        connected: true,
        reference_id: 'test-store.myshopify.com',
        expires_at: '2026-10-01T00:00:00Z',
        settings: {
          abandoned_cart: {
            enabled: true,
            inbox_id: 10,
            template_name: 'reminder_tmpl',
            language: 'en',
            store_domain: 'test-store.com',
            require_marketing_consent: true,
            test_phones: ['+919876543210'],
            delay_hours: 2,
          },
        },
      },
    });

    const wrapper = mount(Shopify, {
      global: {
        stubs: {
          SettingsLayout: {
            template: '<div><slot name="header"/><slot name="body"/></div>',
          },
          BaseSettingsHeader: true,
          Dialog: true,
          Button: true,
          Input: true,
          Switch: true,
          Select: true,
          Icon: true,
        },
        mocks: {
          $t: key => key,
        },
      },
    });

    await flushPromises();

    expect(wrapper.text()).toContain('INTEGRATION_SETTINGS.SHOPIFY.CONNECTED');
    expect(wrapper.text()).toContain(
      'INTEGRATION_SETTINGS.SHOPIFY.REMINDERS.TEST_MODE_NOTICE'
    );
    expect(wrapper.vm.enabled).toBe(true);
    expect(wrapper.vm.inboxId).toBe(10);
    expect(wrapper.vm.templateName).toBe('reminder_tmpl');
    expect(wrapper.vm.language).toBe('en');
    expect(wrapper.vm.storeDomain).toBe('test-store.com');
    expect(wrapper.vm.requireMarketingConsent).toBe(true);
    expect(wrapper.vm.testPhones).toBe('+919876543210');
    expect(wrapper.vm.delayHours).toBe(2);
  });

  it('saves only the permitted reminder keys and updates form from response settings', async () => {
    ShopifyAPI.get.mockResolvedValue({
      data: {
        connected: true,
        reference_id: 'test-store.myshopify.com',
        expires_at: '2026-10-01T00:00:00Z',
        settings: {
          abandoned_cart: {
            enabled: false,
            inbox_id: null,
            template_name: '',
            language: 'en',
            store_domain: '',
            require_marketing_consent: false,
            test_phones: [],
            delay_hours: 24,
          },
        },
      },
    });

    ShopifyAPI.update.mockResolvedValue({
      data: {
        connected: true,
        reference_id: 'test-store.myshopify.com',
        expires_at: '2026-10-01T00:00:00Z',
        settings: {
          abandoned_cart: {
            enabled: true,
            inbox_id: 10,
            template_name: 'new_reminder',
            language: 'en',
            store_domain: 'biotane.in',
            require_marketing_consent: true,
            test_phones: ['919876543210', '919812143700'],
            delay_hours: 2,
          },
        },
      },
    });

    const wrapper = mount(Shopify, {
      global: {
        stubs: {
          SettingsLayout: {
            template: '<div><slot name="header"/><slot name="body"/></div>',
          },
          BaseSettingsHeader: true,
          Dialog: true,
          Button: true,
          Input: true,
          Switch: true,
          Select: true,
          Icon: true,
        },
        mocks: {
          $t: key => key,
        },
      },
    });

    await flushPromises();

    // Trigger save with form values
    wrapper.vm.enabled = true;
    wrapper.vm.inboxId = 10;
    wrapper.vm.templateName = 'new_reminder';
    wrapper.vm.language = 'en';
    wrapper.vm.storeDomain = 'biotane.in';
    wrapper.vm.requireMarketingConsent = true;
    wrapper.vm.testPhones = '919876543210, 919812143700';
    wrapper.vm.delayHours = 2;

    await wrapper.vm.handleSaveSettings();
    await flushPromises();

    expect(ShopifyAPI.update).toHaveBeenCalledWith({
      abandoned_cart: {
        enabled: true,
        inbox_id: 10,
        template_name: 'new_reminder',
        language: 'en',
        store_domain: 'biotane.in',
        require_marketing_consent: true,
        test_phones: ['919876543210', '919812143700'],
        delay_hours: 2,
      },
    });

    // Verify form preserves values returned by real update response
    expect(wrapper.vm.enabled).toBe(true);
    expect(wrapper.vm.inboxId).toBe(10);
    expect(wrapper.vm.templateName).toBe('new_reminder');
    expect(wrapper.vm.language).toBe('en');
    expect(wrapper.vm.storeDomain).toBe('biotane.in');
    expect(wrapper.vm.requireMarketingConsent).toBe(true);
    expect(wrapper.vm.testPhones).toBe('919876543210, 919812143700');
    expect(wrapper.vm.delayHours).toBe(2);
  });

  it('displays the API error message when save fails with 422 { error: message }', async () => {
    ShopifyAPI.get.mockResolvedValue({
      data: {
        connected: true,
        reference_id: 'test-store.myshopify.com',
        settings: { abandoned_cart: {} },
      },
    });

    ShopifyAPI.update.mockRejectedValue({
      response: {
        status: 422,
        data: { error: 'Invalid store domain' },
      },
    });

    const wrapper = mount(Shopify, {
      global: {
        stubs: {
          SettingsLayout: {
            template: '<div><slot name="header"/><slot name="body"/></div>',
          },
          BaseSettingsHeader: true,
          Dialog: true,
          Button: true,
          Input: true,
          Switch: true,
          Select: true,
          Icon: true,
        },
        mocks: {
          $t: key => key,
        },
      },
    });

    await flushPromises();

    await wrapper.vm.handleSaveSettings();
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('Invalid store domain');
  });
});
