import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import ClientsAPI from '../../api/clients';

export const state = {
  records: [],
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
  },
};

export const getters = {
  getClients($state) {
    return $state.records;
  },
  getUIFlags($state) {
    return $state.uiFlags;
  },
  getClientById: $state => id => {
    return $state.records.find(record => record.id === Number(id)) || {};
  },
};

export const actions = {
  get: async ({ commit }) => {
    commit('SET_FETCHING_STATUS', true);
    try {
      const response = await ClientsAPI.get();
      commit('SET_FETCHING_STATUS', false);
      commit('SET_CLIENTS', response.data);
    } catch (error) {
      commit('SET_FETCHING_STATUS', false);
    }
  },
  create: async ({ commit }, clientInfo) => {
    commit('SET_CREATING_STATUS', true);
    try {
      const response = await ClientsAPI.create(clientInfo);
      commit('ADD_CLIENT', response.data);
      commit('SET_CREATING_STATUS', false);
      return response.data;
    } catch (error) {
      commit('SET_CREATING_STATUS', false);
      throw error;
    }
  },
  update: async ({ commit }, { id, ...clientParams }) => {
    commit('SET_UPDATING_STATUS', true);
    try {
      const response = await ClientsAPI.update(id, clientParams);
      commit('EDIT_CLIENT', response.data);
      commit('SET_UPDATING_STATUS', false);
      return response.data;
    } catch (error) {
      commit('SET_UPDATING_STATUS', false);
      throw error;
    }
  },
  delete: async ({ commit }, clientId) => {
    commit('SET_DELETING_STATUS', true);
    try {
      await ClientsAPI.delete(clientId);
      commit('DELETE_CLIENT', clientId);
      commit('SET_DELETING_STATUS', false);
    } catch (error) {
      commit('SET_DELETING_STATUS', false);
      throw error;
    }
  },
};

export const mutations = {
  SET_FETCHING_STATUS($state, status) {
    $state.uiFlags.isFetching = status;
  },
  SET_CREATING_STATUS($state, status) {
    $state.uiFlags.isCreating = status;
  },
  SET_UPDATING_STATUS($state, status) {
    $state.uiFlags.isUpdating = status;
  },
  SET_DELETING_STATUS($state, status) {
    $state.uiFlags.isDeleting = status;
  },
  SET_CLIENTS: MutationHelpers.set,
  ADD_CLIENT: MutationHelpers.create,
  EDIT_CLIENT: MutationHelpers.update,
  DELETE_CLIENT: MutationHelpers.destroy,
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
