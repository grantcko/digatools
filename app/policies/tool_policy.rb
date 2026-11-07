class ToolPolicy < ApplicationPolicy
  def create?
    user.present? && record.user_id == user.id
  end

  def show?
    create?
  end

  def update?
    create?
  end

  def destroy?
    create?
  end

  class Scope < Scope
    def resolve
      scope.where(user: user)
    end
  end
end
