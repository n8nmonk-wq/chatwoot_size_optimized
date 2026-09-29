# frozen_string_literal: true

class CreateShopifyOrderNotifications < ActiveRecord::Migration[7.1]
  def change
    create_table :shopify_order_notifications do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :order_id, null: false
      t.string :kind, null: false
      t.string :status, null: false
      t.string :reason
      t.datetime :sent_at

      t.timestamps
    end

    add_index :shopify_order_notifications,
              [:account_id, :order_id, :kind],
              unique: true,
              name: 'idx_shopify_order_notifications_uniqueness'
  end
end
