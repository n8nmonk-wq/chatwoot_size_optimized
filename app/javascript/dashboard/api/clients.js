import ApiClient from './ApiClient';

class Clients extends ApiClient {
  constructor() {
    super('clients', { accountScoped: true });
  }
}

export default new Clients();
