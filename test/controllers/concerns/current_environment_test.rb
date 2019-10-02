# frozen_string_literal: true
require_relative '../../test_helper'

SingleCov.covered!

class CurrentEnvironmentConcernTest < ActionController::TestCase
  class CurrentEnvironmentTestController < ApplicationController
    include CurrentEnvironment

    def show
      render inline: '<%= current_environment.class.name %>'
    end
  end

  tests CurrentEnvironmentTestController
  use_test_routes CurrentEnvironmentTestController

  let(:environment) { environments(:production) }

  before { login_as(users(:viewer)) }

  it "finds current environment" do
    get :show, params: {environment_id: environment.id, test_route: true}
    response.body.must_equal 'Environment'
  end

  it "fails with invalid environment id" do
    assert_raises ActiveRecord::RecordNotFound do
      get :show, params: {environment_id: 123456, test_route: true}
    end
  end

  it "does not fail without environment" do
    get :show, params: {test_route: true}
    response.body.must_equal 'NilClass'
  end
end
