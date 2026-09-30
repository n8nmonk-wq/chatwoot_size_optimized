# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Shopify::OrderUpdateJob, type: :job do
  subject(:job) { described_class.new }

  let(:account_id) { 1 }
  let(:topic) { 'orders/create' }
  let(:payload) { { 'id' => 123, 'name' => '#1001' } }
  let(:service_double) { instance_double(Shopify::OrderUpdateService) }

  it 'enqueues on the default queue' do
    expect(described_class.new.queue_name).to eq('default')
  end

  it 'delegates execution to Shopify::OrderUpdateService' do
    expect(Shopify::OrderUpdateService).to receive(:new).with(
      account_id: account_id,
      topic: topic,
      payload: payload
    ).and_return(service_double)
    expect(service_double).to receive(:perform)

    job.perform(account_id, topic, payload)
  end

  it 'propagates errors so Sidekiq retries the job' do
    allow(Shopify::OrderUpdateService).to receive(:new).with(
      account_id: account_id,
      topic: topic,
      payload: payload
    ).and_return(service_double)
    allow(service_double).to receive(:perform).and_raise(StandardError.new('Shopify rate limit'))

    expect do
      job.perform(account_id, topic, payload)
    end.to raise_error(StandardError, 'Shopify rate limit')
  end
end
