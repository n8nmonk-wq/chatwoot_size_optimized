# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Shopify::AbandonedCartReminderJob, type: :job do
  subject(:job) { described_class.new }

  let(:account1) { create(:account) }
  let(:account2) { create(:account) }
  let(:account3) { create(:account) }
  let(:account4) { create(:account) }
  let(:account5) { create(:account) }

  let!(:active_hook1) do
    create(:integrations_hook, :shopify,
           account: account1,
           status: :enabled,
           settings: { 'abandoned_cart' => { 'enabled' => true } })
  end
  let!(:active_hook2) do
    create(:integrations_hook, :shopify,
           account: account2,
           status: :enabled,
           settings: { 'abandoned_cart' => { 'enabled' => true } })
  end
  let!(:disabled_hook) do
    create(:integrations_hook, :shopify,
           account: account3,
           status: :disabled,
           settings: { 'abandoned_cart' => { 'enabled' => true } })
  end
  let!(:unconfigured_hook) do
    create(:integrations_hook, :shopify,
           account: account4,
           status: :enabled,
           settings: { 'abandoned_cart' => { 'enabled' => false } })
  end
  let!(:slack_hook) do
    create(:integrations_hook,
           app_id: 'slack',
           account: account5,
           status: :enabled,
           settings: { 'abandoned_cart' => { 'enabled' => true } })
  end

  it 'enqueues on the scheduled_jobs queue' do
    expect(described_class.new.queue_name).to eq('scheduled_jobs')
  end

  it 'calls Shopify::AbandonedCartReminderService only for enabled shopify hooks with abandoned_cart enabled' do
    expect(Shopify::AbandonedCartReminderService).to receive(:perform).with(active_hook1)
    expect(Shopify::AbandonedCartReminderService).to receive(:perform).with(active_hook2)
    expect(Shopify::AbandonedCartReminderService).not_to receive(:perform).with(disabled_hook)
    expect(Shopify::AbandonedCartReminderService).not_to receive(:perform).with(unconfigured_hook)
    expect(Shopify::AbandonedCartReminderService).not_to receive(:perform).with(slack_hook)

    job.perform_now
  end

  it 'continues processing remaining hooks if one hook raises an error' do
    allow(Shopify::AbandonedCartReminderService).to receive(:perform).with(active_hook1).and_raise(StandardError.new('API timeout'))
    expect(Shopify::AbandonedCartReminderService).to receive(:perform).with(active_hook2)

    expect { job.perform_now }.not_to raise_error
  end
end
