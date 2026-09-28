# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Shopify::AbandonedCheckoutReminder, type: :model do
  let(:account) { create(:account) }

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
  end

  describe 'validations' do
    subject { described_class.new(account: account, checkout_id: 'gid://shopify/Checkout/12345', status: 'sent') }

    it { is_expected.to validate_presence_of(:account_id) }
    it { is_expected.to validate_presence_of(:checkout_id) }
    it { is_expected.to validate_uniqueness_of(:checkout_id).scoped_to(:account_id) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[sent skipped failed]) }
  end
end
