/* global axios */

import ApiClient from '../ApiClient';

class ShopifyAPI extends ApiClient {
  constructor() {
    super('integrations/shopify', { accountScoped: true });
  }

  getOrders(contactId) {
    return axios.get(`${this.url}/orders`, {
      params: { contact_id: contactId },
    });
  }

  update(data) {
    return axios.patch(this.url, data);
  }

  disconnect() {
    return axios.delete(this.url);
  }
}

export default new ShopifyAPI();
