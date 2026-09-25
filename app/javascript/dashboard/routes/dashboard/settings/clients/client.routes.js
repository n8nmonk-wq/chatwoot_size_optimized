import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';
import ClientHome from './Index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/clients'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          redirect: to => {
            return { name: 'client_list', params: to.params };
          },
        },
        {
          path: 'list',
          name: 'client_list',
          component: ClientHome,
          meta: {
            permissions: ['administrator'],
          },
        },
      ],
    },
  ],
};
