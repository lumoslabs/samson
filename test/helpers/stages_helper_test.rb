# frozen_string_literal: true
# rubocop:disable Metrics/LineLength
require_relative '../test_helper'

SingleCov.covered!

describe StagesHelper do
  include ApplicationHelper

  describe "#edit_command_link" do
    let(:current_user) { users(:admin) }

    it "links to global edit" do
      command = commands(:global)
      html = edit_command_link(command)
      html.must_equal "<a title=\"Edit global command\" class=\"edit-command glyphicon glyphicon-globe no-hover\" href=\"/commands/#{command.id}\"></a>"
    end

    it "links to local edit" do
      command = commands(:echo)
      html = edit_command_link(command)
      html.must_equal "<a title=\"Edit\" class=\"edit-command glyphicon glyphicon-edit no-hover\" href=\"/commands/#{command.id}\"></a>"
    end
  end

  describe "#stage_template_icon" do
    it "renders icon" do
      stage_template_icon.must_include "glyphicon-duplicate"
    end
  end

  describe "#deployer_for_stage?" do
    let(:current_user) { users(:deployer) }

    it "works" do
      @project = projects(:test)
      deployer_for_stage?(stages(:test_staging)).must_equal true
    end
  end
end
# rubocop:enable Metrics/LineLength
