class Api::V1::Accounts::ClientsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_client, only: [:update, :destroy]

  def index
    @clients = Current.account.account_users.where(role: :client).includes(:user).map(&:user)
  end

  def create
    username = client_params[:username].to_s.strip.downcase
    email = "#{username}@mmochat.internal"

    ActiveRecord::Base.transaction do
      @client = User.new(
        name: client_params[:name],
        username: username,
        email: email,
        password: client_params[:password],
        password_confirmation: client_params[:password],
        custom_attributes: { 'client_password' => client_params[:password] }
      )
      @client.skip_confirmation!
      @client.save!

      Current.account.account_users.create!(
        user: @client,
        role: :client,
        inviter: current_user
      )

      sync_inboxes(@client, client_params[:inbox_ids])
    end
  rescue ActiveRecord::RecordInvalid => e
    render_could_not_create_error(e.record.errors.full_messages.join(', '))
  end

  def update
    ActiveRecord::Base.transaction do
      update_attributes = { name: client_params[:name] }.compact
      if client_params[:password].present?
        update_attributes[:password] = client_params[:password]
        update_attributes[:password_confirmation] = client_params[:password]
        attrs = (@client.custom_attributes || {}).dup
        attrs['client_password'] = client_params[:password]
        update_attributes[:custom_attributes] = attrs
      end
      @client.update!(update_attributes)

      sync_inboxes(@client, client_params[:inbox_ids]) if client_params.key?(:inbox_ids)
    end
  rescue ActiveRecord::RecordInvalid => e
    render_could_not_create_error(e.record.errors.full_messages.join(', '))
  end

  def destroy
    account_user = @client.account_users.find_by(account: Current.account)
    account_user&.destroy!
    DeleteObjectJob.perform_later(@client) if @client.reload.account_users.blank?
    head :ok
  end

  private

  def check_authorization
    authorize Current.account, :update?
  end

  def fetch_client
    @client = Current.account.users.find(params[:id])
  end

  def client_params
    params.require(:client).permit(:name, :username, :password, inbox_ids: [])
  end

  def sync_inboxes(user, inbox_ids)
    return if inbox_ids.nil?

    valid_inbox_ids = Current.account.inboxes.where(id: inbox_ids).pluck(:id)
    InboxMember.where(inbox: Current.account.inboxes, user: user).where.not(inbox_id: valid_inbox_ids).destroy_all
    valid_inbox_ids.each do |inbox_id|
      InboxMember.find_or_create_by!(inbox_id: inbox_id, user_id: user.id)
    end
  end
end
