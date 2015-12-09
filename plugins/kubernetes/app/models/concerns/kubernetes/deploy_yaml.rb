module Kubernetes
  module DeployYaml
    def deployment_hash
      @deployment_yaml ||=
        if replication_controller_doc.present?
          JSON.parse(replication_controller_doc).with_indifferent_access
        else
          template[:spec][:replicas] = replica_target
          add_labels
          update_docker_image
          set_resource_usage
        end
    end

    private

    def template
      @template ||=
        YAML.load_stream(raw_template, kubernetes_role.config_file).detect do |doc|
          doc['kind'] == 'ReplicationController' || doc['kind'] == 'Deployment'
        end.with_indifferent_access
    end

    def raw_template
      @raw_template ||= build.file_from_repo(kubernetes_role.config_file)
    end

    def add_labels
      template[:metadata][:labels].merge!(labels)
      template[:spec][:selector].merge!(labels)
      template[:spec][:template][:metadata][:labels].merge!(labels)
    end

    def set_resource_usage
      container_hash[:resources] = {
        limits: { cpu: kubernetes_role.cpu, memory: kubernetes_role.ram_with_units }
      }
    end

    def labels
      kubernetes_release.pod_labels.merge(role: kubernetes_role.label_name)
    end

    def update_docker_image
      docker_path = build.docker_repo_digest || "#{build.project.docker_repo}:#{build.docker_ref}"
      # Assume first container is one we want to update docker image in
      container_hash = template[:spec][:template][:spec][:containers].first
      container_hash[:image] = docker_path
    end
  end
end
