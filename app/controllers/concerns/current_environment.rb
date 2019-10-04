# frozen_string_literal: true
module CurrentEnvironment
  extend ActiveSupport::Concern

  included do
    before_action :require_environment
    helper_method :current_environment
  end

  protected

  def current_environment
    @environment
  end

  def require_environment
    @environment = (Environment.find_by_param!(params[:environment_id]) if params[:environment_id])
  end
end
