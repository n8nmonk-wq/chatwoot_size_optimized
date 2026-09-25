class ContactPolicy < ApplicationPolicy
  def index?
    !@account_user.client?
  end

  def active?
    !@account_user.client?
  end

  def import?
    @account_user.administrator?
  end

  def export?
    @account_user.administrator?
  end

  def search?
    !@account_user.client?
  end

  def filter?
    !@account_user.client?
  end

  def update?
    !@account_user.client?
  end

  def contactable_inboxes?
    !@account_user.client?
  end

  def destroy_custom_attributes?
    !@account_user.client?
  end

  def show?
    !@account_user.client?
  end

  def create?
    !@account_user.client?
  end

  def avatar?
    !@account_user.client?
  end

  def destroy?
    @account_user.administrator?
  end
end

ContactPolicy.prepend_mod_with('ContactPolicy')
