# frozen_string_literal: true
class UserEnvironmentRole < ActiveRecord::Base
  include HasRole
  extend AuditOnAssociation

  audited
  audits_on_association :user, :user_environment_roles do |user|
    user.user_environment_roles.map { |uer| [uer.environment.permalink, uer.role_id] }.to_h
  end

  belongs_to :environment, inverse_of: :user_environment_roles
  belongs_to :user, inverse_of: :user_environment_roles

  ROLES = [Role::VIEWER, Role::DEPLOYER].freeze

  validates_presence_of :environment, :user
  validates :role_id, inclusion: {in: ROLES.map(&:id)}
  validates_uniqueness_of :environment_id, scope: :user_id
end
