# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Shopify::TemplateValidator do
  describe '.validate' do
    let(:text_template) do
      {
        'name' => 'cart_reminder',
        'language' => 'en',
        'status' => 'APPROVED',
        'components' => [
          { 'type' => 'BODY', 'text' => 'Hi {{1}}, items: {{2}}, total: {{3}}' },
          { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'URL', 'url' => 'https://example.com/{{1}}' }] }
        ]
      }
    end

    let(:image_template) do
      {
        'name' => 'cart_reminder_image',
        'language' => 'en',
        'status' => 'APPROVED',
        'components' => [
          { 'type' => 'HEADER', 'format' => 'IMAGE' },
          { 'type' => 'BODY', 'text' => 'Hi {{1}}, items: {{2}}, total: {{3}}' },
          { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'URL', 'url' => 'https://example.com/{{1}}' }] }
        ]
      }
    end

    let(:video_template) do
      {
        'name' => 'cart_reminder_video',
        'language' => 'en',
        'status' => 'APPROVED',
        'components' => [
          { 'type' => 'HEADER', 'format' => 'VIDEO' },
          { 'type' => 'BODY', 'text' => 'Hi {{1}}' }
        ]
      }
    end

    let(:valid_cart_mapping) do
      {
        'template_name' => 'cart_reminder',
        'language' => 'en',
        'variables' => {
          'body.1' => 'first_name',
          'body.2' => 'item_summary',
          'body.3' => 'total',
          'button.0' => 'checkout_url_suffix'
        }
      }
    end

    it 'returns error if template is blank' do
      expect(described_class.validate(nil, valid_cart_mapping, 'abandoned_cart')).to eq('Template not found')
    end

    it 'returns error if template is not approved' do
      unapproved = text_template.merge('status' => 'PENDING')
      expect(described_class.validate(unapproved, valid_cart_mapping, 'abandoned_cart')).to eq('Template is not approved')
    end

    it 'returns nil for a valid text template mapping' do
      expect(described_class.validate(text_template, valid_cart_mapping, 'abandoned_cart')).to be_nil
    end

    context 'when kind is abandoned_cart and template has IMAGE header' do
      it 'returns nil when valid https header_image_url is present' do
        mapping = valid_cart_mapping.merge('header_image_url' => 'https://cdn.shopify.com/logo.png')
        expect(described_class.validate(image_template, mapping, 'abandoned_cart')).to be_nil
      end

      it 'returns error when header_image_url is missing' do
        expect(described_class.validate(image_template, valid_cart_mapping, 'abandoned_cart'))
          .to eq('Header image URL is required for this template')
      end

      it 'returns error when header_image_url is blank' do
        mapping = valid_cart_mapping.merge('header_image_url' => '   ')
        expect(described_class.validate(image_template, mapping, 'abandoned_cart'))
          .to eq('Header image URL is required for this template')
      end

      it 'returns error when header_image_url is http instead of https' do
        mapping = valid_cart_mapping.merge('header_image_url' => 'http://cdn.shopify.com/logo.png')
        expect(described_class.validate(image_template, mapping, 'abandoned_cart'))
          .to eq('Header image URL must start with https://')
      end

      it 'returns error when header_image_url has no host' do
        mapping = valid_cart_mapping.merge('header_image_url' => 'https:///logo.png')
        expect(described_class.validate(image_template, mapping, 'abandoned_cart'))
          .to eq('Header image URL must start with https://')
      end

      it 'returns error when header_image_url is not a valid URL' do
        mapping = valid_cart_mapping.merge('header_image_url' => 'not-a-valid-url')
        expect(described_class.validate(image_template, mapping, 'abandoned_cart'))
          .to eq('Header image URL must start with https://')
      end

      it 'rejects VIDEO headers even for abandoned_cart' do
        mapping = { 'variables' => { 'body.1' => 'first_name' }, 'header_image_url' => 'https://example.com/v.mp4' }
        expect(described_class.validate(video_template, mapping, 'abandoned_cart'))
          .to eq('Media header templates are not supported')
      end
    end

    context 'when kind is an order milestone' do
      it 'rejects IMAGE headers for confirmed milestone' do
        mapping = valid_cart_mapping.merge(
          'header_image_url' => 'https://cdn.shopify.com/logo.png',
          'variables' => {
            'body.1' => 'first_name',
            'body.2' => 'item_summary',
            'body.3' => 'total',
            'button.0' => 'order_status_url_suffix'
          }
        )
        expect(described_class.validate(image_template, mapping, 'confirmed'))
          .to eq('Media header templates are not supported')
      end

      it 'rejects header_image_url in mapping even for text templates' do
        mapping = valid_cart_mapping.merge(
          'header_image_url' => 'https://cdn.shopify.com/logo.png',
          'variables' => {
            'body.1' => 'first_name',
            'body.2' => 'item_summary',
            'body.3' => 'total',
            'button.0' => 'order_status_url_suffix'
          }
        )
        expect(described_class.validate(text_template, mapping, 'confirmed'))
          .to eq('Header image is not supported for order updates')
      end
    end
  end
end
