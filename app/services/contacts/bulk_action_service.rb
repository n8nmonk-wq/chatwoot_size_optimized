class Contacts::BulkActionService
  def initialize(account:, user:, params:)
    @account = account
    @user = user
    @params = params.deep_symbolize_keys
  end

  def perform
    return delete_contacts if delete_requested?
    return move_group if move_group_requested?

    if labels_to_add.any? || labels_to_remove.any?
      remove_labels if labels_to_remove.any?
      assign_labels if labels_to_add.any?
      return { success: true }
    end

    Rails.logger.warn("Unknown contact bulk operation payload: #{@params.keys}")
    { success: false, error: 'unknown_operation' }
  end

  private

  def move_group_requested?
    @params[:action_name] == 'move_group'
  end

  def move_group
    contacts = @account.contacts.where(id: ids)
    target_labels = labels_to_add

    contacts.find_each do |contact|
      current_tags = contact.label_list
      tags_to_remove = current_tags.select { |t| t.start_with?('wa_batch_', 'batch_') } + labels_to_remove
      cleaned_tags = current_tags - tags_to_remove
      new_tags = (cleaned_tags + target_labels).uniq
      contact.update!(label_list: new_tags)
    end

    { success: true, updated_contact_ids: contacts.pluck(:id) }
  end

  def assign_labels
    Contacts::BulkAssignLabelsService.new(
      account: @account,
      contact_ids: ids,
      labels: labels_to_add
    ).perform
  end

  def remove_labels
    Contacts::BulkRemoveLabelsService.new(
      account: @account,
      contact_ids: ids,
      labels: labels_to_remove
    ).perform
  end

  def delete_contacts
    Contacts::BulkDeleteService.new(
      account: @account,
      contact_ids: ids
    ).perform
  end

  def ids
    Array(@params[:ids]).compact
  end

  def labels_to_add
    @labels_to_add ||= Array(@params.dig(:labels, :add)).reject(&:blank?)
  end

  def labels_to_remove
    @labels_to_remove ||= Array(@params.dig(:labels, :remove)).reject(&:blank?)
  end

  def delete_requested?
    @params[:action_name] == 'delete'
  end
end
