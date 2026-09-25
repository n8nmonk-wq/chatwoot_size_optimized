import { createStore } from 'vuex';

import accounts from './modules/accounts';
import agentBots from './modules/agentBots';
import agentCapacityPolicies from './modules/agentCapacityPolicies';
import agents from './modules/agents';
import assignmentPolicies from './modules/assignmentPolicies';
import attributes from './modules/attributes';
import auditlogs from './modules/auditlogs';
import auth from './modules/auth';
import automations from './modules/automations';
import bulkActions from './modules/bulkActions';
import campaigns from './modules/campaigns';
import cannedResponse from './modules/cannedResponse';
import clients from './modules/clients';
import contactConversations from './modules/contactConversations';
import contactLabels from './modules/contactLabels';
import contactNotes from './modules/contactNotes';
import contacts from './modules/contacts';
import conversationLabels from './modules/conversationLabels';
import conversationMetadata from './modules/conversationMetadata';
import conversationPage from './modules/conversationPage';
import conversations from './modules/conversations';
import conversationSearch from './modules/conversationSearch';
import conversationStats from './modules/conversationStats';
import conversationTypingStatus from './modules/conversationTypingStatus';
import conversationUnreadCounts from './modules/conversationUnreadCounts';
import conversationWatchers from './modules/conversationWatchers';
import csat from './modules/csat';
import customViews from './modules/customViews';
import dashboardApps from './modules/dashboardApps';
import draftMessages from './modules/draftMessages';
import globalConfig from 'shared/store/globalConfig';
import inboxAssignableAgents from './modules/inboxAssignableAgents';
import inboxes from './modules/inboxes';
import inboxMembers from './modules/inboxMembers';
import integrations from './modules/integrations';
import labels from './modules/labels';
import notifications from './modules/notifications';
import reports from './modules/reports';
import sla from './modules/sla';
import slaReports from './modules/SLAReports';
import sidebarSortPreferences from './modules/sidebarSortPreferences';
import summaryReports from './modules/summaryReports';
import userNotificationSettings from './modules/userNotificationSettings';
import webhooks from './modules/webhooks';

const plugins = [];

export default createStore({
  modules: {
    accounts,
    agentBots,
    agentCapacityPolicies,
    agents,
    assignmentPolicies,
    attributes,
    auditlogs,
    auth,
    automations,
    bulkActions,
    campaigns,
    cannedResponse,
    clients,
    contactConversations,
    contactLabels,
    contactNotes,
    contacts,
    conversationLabels,
    conversationMetadata,
    conversationPage,
    conversations,
    conversationSearch,
    conversationStats,
    conversationTypingStatus,
    conversationUnreadCounts,
    conversationWatchers,
    csat,
    customViews,
    dashboardApps,
    draftMessages,
    globalConfig,
    inboxAssignableAgents,
    inboxes,
    inboxMembers,
    integrations,
    labels,
    notifications,
    reports,
    sla,
    slaReports,
    sidebarSortPreferences,
    summaryReports,
    userNotificationSettings,
    webhooks,
  },
  plugins,
});

