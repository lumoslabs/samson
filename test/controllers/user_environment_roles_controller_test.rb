# frozen_string_literal: true
require_relative '../test_helper'

SingleCov.covered!

describe UserEnvironmentRolesController do
  let(:environment) { environments(:production) }

  as_a :viewer do
    describe "#index" do
      it 'renders' do
        get :index, params: {environment_id: environment.to_param}
        assert_template :index
        assigns(:users).size.must_equal User.count
      end

      it 'renders JSON' do
        get :index, params: {environment_id: environment.to_param, format: 'json'}
        users = JSON.parse(response.body).fetch('users')
        users.size.must_equal User.count
      end

      it 'filters' do
        get :index, params: {environment_id: environment.to_param, search: "Admin"}
        assert_template :index
        users = assigns(:users).sort_by(&:name)
        users.map(&:name).sort.must_equal ["Admin", "Deployer Project Admin", "Super Admin"]
        users.first.user_environment_role_id.must_equal nil
      end

      it 'filters by role' do
        get :index, params: {environment_id: environment.to_param, role_id: Role::ADMIN.id}
        assert_template :index
        assigns(:users).map(&:name).sort.must_equal ["Admin", "Super Admin"]
      end

      it 'filters by environment role' do
        role = UserEnvironmentRole.create!(role_id: Role::DEPLOYER.id, environment: environments(:production), user: users(:deployer))
        get :index, params: {environment_id: environment.to_param, role_id: Role::DEPLOYER.id}
        assert_template :index
        assigns(:users).map(&:name).sort.must_equal ["Admin",
                                                    "Deployer",
                                                    "Deployer Project Admin",
                                                    "DeployerBuddy",
                                                    "Environment Deployer Global Deployer",
                                                    "Environment Deployer Global Viewer",
                                                    "Environment Limited Project Deployer",
                                                    "Environment Viewer Global Deployer",
                                                    "Super Admin"]
        assigns(:users).map(&:user_environment_role_id).must_include role.role_id
      end
    end
  end

  as_a :deployer do
    unauthorized :post, :create, environment_id: :production
  end

  as_a :admin do
    describe "#create" do
      def create(role_id, **options)
        post :create, params: {environment_id: environment, user_id: new_viewer.id, role_id: role_id}, **options
      end

      let(:new_viewer) { users(:deployer) }

      it 'creates new environment role' do
        create Role::VIEWER.id
        assert_response :redirect
        role = new_viewer.user_environment_roles.first
        role.role_id.must_equal Role::VIEWER.id
      end

      it 'updates existing role' do
        new_viewer.user_environment_roles.create!(role_id: Role::DEPLOYER.id, environment: environment)
        create Role::VIEWER.id
        assert_response :redirect
        role = new_viewer.user_environment_roles.first.reload
        role.role_id.must_equal Role::VIEWER.id
      end

      it 'deletes existing role when setting to None' do
        new_viewer.user_environment_roles.create!(role_id: Role::DEPLOYER.id, environment: environment)
        create ''
        assert_response :redirect
        refute new_viewer.reload.user_environment_roles.first
      end

      it 'does nothing when setting from None to None' do
        create ''
        assert_response :redirect
        refute new_viewer.user_environment_roles.first
      end

      it 'clears the access request pending flag' do
        check_pending_request_flag(new_viewer) do
          create Role::VIEWER.id
          assert_response :redirect
        end
      end

      it 'renders text for xhr requests' do
        create Role::VIEWER.id, xhr: true
        assert_response :success
      end
    end
  end

  private

  def check_pending_request_flag(user)
    user.update!(access_request_pending: true)
    assert(user.access_request_pending)
    yield
    user.reload
    refute(user.access_request_pending)
  end
end
