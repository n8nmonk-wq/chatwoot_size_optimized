# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Shopify::OrderNotification, type: :model do
  let(:account) { create(:account) }

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
  end

  describe 'validations' do
    subject { described_class.new(account: account, order_id: 'order_12345', kind: 'confirmed', status: 'sent') }

    it { is_expected.to validate_presence_of(:account_id) }
    it { is_expected.to validate_presence_of(:order_id) }
    it { is_expected.to validate_uniqueness_of(:order_id).scoped_to([:account_id, :kind]) }
    it { is_expected.to validate_presence_of(:kind) }
    it { is_expected.to validate_inclusion_of(:kind).in_array(%w[confirmed shipped out_for_delivery delivered]) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[sent skipped failed]) }
  end
end
