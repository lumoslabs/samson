# frozen_string_literal: true
require_relative '../test_helper'

SingleCov.covered!

describe UserEnvironmentRolesHelper do
  let(:environment) { environments(:test) }

  describe "#user_environment_role_radio" do
    it "allows downgrade for unchecked" do
      result = user_environment_role_radio users(:deployer), 'Foo', Role::VIEWER.id, nil
      result.wont_include 'checked'
      result.wont_include 'global'
      result.wont_include 'disabled="disabled"'
    end

    context "with global access" do
      it "blocks upgrades" do
        result = user_environment_role_radio users(:viewer), 'Foo', Role::DEPLOYER.id, nil
        result.wont_include 'checked'
        result.must_include 'global'
        result.must_include 'disabled="disabled"'
      end

      it "allows downgrades" do
        result = user_environment_role_radio users(:deployer), 'Foo', Role::VIEWER.id, nil
        result.wont_include 'checked'
        result.wont_include 'global'
        result.wont_include 'disabled="disabled"'
      end
    end

    context 'with environment access' do
      it "allows to re-check current" do
        result = user_environment_role_radio users(:environment_viewer_global_deployer), 'Foo', Role::VIEWER.id, Role::VIEWER.id
        result.must_include 'checked'
        result.wont_include 'global'
        result.wont_include 'disabled="disabled"'
      end

      it "allows downgrades" do
        result = user_environment_role_radio users(:environment_deployer_global_deployer), 'Foo', Role::VIEWER.id, Role::DEPLOYER.id
        result.must_include 'checked'
        result.wont_include 'global'
        result.wont_include 'disabled="disabled"'
      end

      it "allows upgrade" do
        result = user_environment_role_radio users(:environment_viewer_global_deployer), 'Foo', Role::DEPLOYER.id, Role::VIEWER.id
        result.wont_include 'checked'
        result.wont_include 'global'
        result.wont_include 'disabled="disabled"'
      end
    end
  end
end
