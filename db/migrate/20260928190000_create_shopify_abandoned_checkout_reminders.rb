# frozen_string_literal: true

class CreateShopifyAbandonedCheckoutReminders < ActiveRecord::Migration[7.1]
  def change
    create_table :shopify_abandoned_checkout_reminders do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :checkout_id, null: false
      t.string :status, null: false
      t.string :reason
      t.datetime :sent_at

      t.timestamps
    end

    add_index :shopify_abandoned_checkout_reminders, [:account_id, :checkout_id], unique: true
  end
end
