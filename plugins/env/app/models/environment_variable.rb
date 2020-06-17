# frozen_string_literal: true
require 'validates_lengths_from_database'

class EnvironmentVariable < ActiveRecord::Base
  FAILED_LOOKUP_MARK = ' X' # SpaceX
  PARENT_PRIORITY = ["Deploy", "Stage", "Project", "EnvironmentVariableGroup"].freeze

  include GroupScope
  extend Inlinable
  audited

  belongs_to :parent, polymorphic: true # Resource they are set on

  validates :name, presence: true
  validates :parent_type, inclusion: PARENT_PRIORITY

  include ValidatesLengthsFromDatabase
  validates_lengths_from_database only: :value

  allow_inline delegate :name, to: :parent, prefix: true, allow_nil: true
  allow_inline delegate :name, to: :scope, prefix: true, allow_nil: true

  class << self
    # preview parameter can be used to not raise an error,
    # but return a value with a helpful message
    # also used by an external plugin
    def env(deploy, deploy_group, resolve_secrets:, project_specific: nil)
      env = {}

      if deploy_group
        env.merge! env_vars_from_external_groups(deploy.project, deploy_group)
      end

      if deploy_group && (env_repo_name = ENV["DEPLOYMENT_ENV_REPO"]) && deploy.project.use_env_repo
        env.merge! env_vars_from_repo(env_repo_name, deploy.project, deploy_group)
      end

      env.merge! env_vars_from_db(deploy, deploy_group, project_specific: project_specific)

      resolve_dollar_variables(env)
      resolve_secrets(deploy.project, deploy_group, env, preview: resolve_secrets == :preview) if resolve_secrets

      env
    end

    # scopes is given as argument since it needs to be cached
    def sort_by_scopes(variables, scopes)
      variables.sort_by { |x| [x.name, scopes.index { |_, s| s == x.scope_type_and_id } || 999] }
    end

    # env_scopes is given as argument since it needs to be cached
    def serialize(variables, env_scopes)
      sorted = EnvironmentVariable.sort_by_scopes(variables, env_scopes)
      sorted.map do |var|
        "#{var.name}=#{var.value.inspect} # #{var.scope&.name || "All"}"
      end.join("\n")
    end

    private

    def env_vars_from_db(deploy, deploy_group, **args)
      variables =
        deploy.environment_variables +
        (deploy.stage&.environment_variables || []) +
        deploy.project.nested_environment_variables(**args)
      variables.sort_by!(&:priority)
      variables.each_with_object({}) do |ev, all|
        all[ev.name] = ev.value if !all[ev.name] && ev.matches_scope?(deploy_group)
      end
    end

    def env_vars_from_repo(env_repo_name, project, deploy_group)
      path = "generated/#{project.permalink}/#{deploy_group.permalink}.env"
      content = GITHUB.contents(env_repo_name, path: path, headers: {Accept: 'applications/vnd.github.v3.raw'})
      Dotenv::Parser.call(content)
    rescue StandardError => e
      raise Samson::Hooks::UserError, "Cannot download env file #{path} from #{env_repo_name} (#{e.message})"
    end

    def env_vars_from_external_groups(project, deploy_group)
      project.external_environment_variable_groups.each_with_object({}) do |group, envs|
        group_env = group.read[deploy_group.permalink]
        envs.merge! group_env if group_env
      end
    rescue StandardError => e
      raise Samson::Hooks::UserError, "Error reading env vars from external env-groups: #{e.message}"
    end

    def resolve_dollar_variables(env)
      env.each do |k, value|
        env[k] = value.gsub(/\$\{(\w+)\}|\$(\w+)/) { |original| env[$1 || $2] || original }
      end
    end

    def resolve_secrets(project, deploy_group, env, preview:)
      resolver = Samson::Secrets::KeyResolver.new(project, Array(deploy_group))
      env.each do |key, value|
        next unless secret_key = value.dup.sub!(/^#{Regexp.escape TerminalExecutor::SECRET_PREFIX}/, '')
        found = resolver.read(secret_key)
        resolved =
          if preview
            path = resolver.expand_key(secret_key)
            path ? "#{TerminalExecutor::SECRET_PREFIX}#{path}" : "#{value}#{FAILED_LOOKUP_MARK}"
          else
            found.to_s
          end
        env[key] = resolved
      end
      resolver.verify! unless preview
    end
  end

  def priority
    [PARENT_PRIORITY.index(parent_type) || 999, super]
  end

  private

  # callback for audited
  def auditing_enabled
    parent_type != "Deploy" && super
  end
end
