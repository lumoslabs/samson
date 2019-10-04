# frozen_string_literal: true
class UserEnvironmentRolesController < ApplicationController
  include CurrentEnvironment

  before_action :authorize_resource!

  def index
    options = params.to_unsafe_h
    options[:environment_id] = current_environment.id # override permalink with id
    options[:role_id] = Role::VIEWER.id if options[:role_id].blank? # force the join so we get environment_role_id

    @pagy, @users = pagy(
      User.search_by_criteria(options),
      page: params[:page],
      items: 15
    )
    @users = @users.select('users.*, user_environment_roles.role_id AS user_environment_role_id') # avoid breaking joins

    respond_to do |format|
      format.html
      format.json { render json: {users: @users} }
    end
  end

  def create
    user = User.find(params[:user_id])
    uer = UserEnvironmentRole.where(user: user, environment: current_environment).first_or_initialize
    uer.role_id = params[:role_id].presence

    if uer.role_id
      uer.save!
      user.update!(access_request_pending: false)
    elsif uer.persisted?
      uer.destroy!
    end

    role_name = (uer.role&.display_name || 'None')
    Rails.logger.info(
      "#{current_user.name_and_email} set the role #{role_name} to #{user.name} on environment #{current_environment.name}"
    )

    if request.xhr?
      render plain: "Saved!"
    else
      redirect_back fallback_location: "/", notice: "Saved!"
    end
  end
end
