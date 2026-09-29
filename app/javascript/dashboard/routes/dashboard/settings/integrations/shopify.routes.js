import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';
import Shopify from './Shopify.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/integrations/shopify'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'settings_integrations_shopify',
          component: Shopify,
          meta: {
            permissions: ['administrator'],
          },
          props: route => ({ error: route.query.error }),
        },
      ],
    },
  ],
};
