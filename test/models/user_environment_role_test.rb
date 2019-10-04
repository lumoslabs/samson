# frozen_string_literal: true
require_relative '../test_helper'

SingleCov.covered!

describe UserEnvironmentRole do
  let(:user) { users(:viewer) }
  let(:environment) { environments(:staging) }
  let!(:environment_role) { UserEnvironmentRole.create!(user_id: user.id, environment_id: environment.id, role_id: Role::DEPLOYER.id) }

  describe "creates a new environment role from a hash" do
    it "is persisted" do
      environment_role.persisted?.must_equal(true)
    end

    it "it created the mapping with the user and the environment" do
      environment_role.user.wont_be_nil
      environment_role.environment.wont_be_nil
    end
  end

  describe "fails to create an environment role with an invalid role" do
    let(:invalid_role) { UserEnvironmentRole.create(user_id: user.id, environment_id: environment.id, role_id: 3) }

    it "is not persisted" do
      invalid_role.persisted?.must_equal(false)
    end

    it "contains errors" do
      invalid_role.errors.wont_be_empty
    end
  end

  describe "fails to create yet another environment role for same user and environment" do
    let(:another_role) { UserEnvironmentRole.create(user_id: user.id, environment_id: environment.id, role_id: Role::DEPLOYER.id) }

    it "is not persisted" do
      another_role.persisted?.must_equal(false)
    end

    it "contains errors" do
      another_role.errors.wont_be_empty
    end
  end

  describe "updates an existing environment role" do
    before do
      environment_role.update(role_id: Role::DEPLOYER.id)
    end

    it "does not update the user" do
      environment_role.user.must_equal user
    end

    it "does not update the environment" do
      environment_role.environment.must_equal environment
    end

    it "updated the role" do
      environment_role.role_id.must_equal Role::DEPLOYER.id
    end
  end

  describe "fails to update an environment role with an invalid role" do
    before do
      environment_role.update(role_id: 3)
    end

    it "is persisted" do
      environment_role.persisted?.must_equal(true)
    end

    it "contains errors" do
      environment_role.errors.wont_be_empty
    end
  end

  describe "audits" do
    it "tracks important changes" do
      environment_role.audits.size.must_equal 1
      environment_role.update_attributes!(role_id: 0)
      environment_role.audits.size.must_equal 2
    end

    it "ignores unimportant changes" do
      environment_role.update_attributes!(updated_at: 1.second.from_now)
      environment_role.audits.size.must_equal 1
    end
  end
end
