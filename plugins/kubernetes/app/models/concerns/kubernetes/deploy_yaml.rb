module Kubernetes
  module DeployYaml
    # This key replaces the default kubernetes key: 'deployment.kubernetes.io/podTemplateHash'
    # This label is used bu kubernetes to identify a RC and corresponding Pods
    CUSTOM_UNIQUE_LABEL_KEY = 'rc_unique_identifier'

    def deployment_hash
      @deployment_yaml ||=
        if replication_controller_doc.present?
          JSON.parse(replication_controller_doc).with_indifferent_access
        else
          template.spec.uniqueLabelKey = CUSTOM_UNIQUE_LABEL_KEY
          template.spec.replicas = replica_target
          template.metadata.namespace = deploy_group.kubernetes_namespace
          set_deployment_metadata
          set_selector_metadata
          set_spec_template_metadata
          update_docker_image
          set_resource_usage
          Rails.logger.info "Created K8S hash: #{template}"
          template
        end
    end

    private

    def template
      @template ||= begin
        yaml = YAML.load_stream(raw_template, kubernetes_role.config_file).detect do |doc|
          doc['kind'] == 'ReplicationController' || doc['kind'] == 'Deployment'
        end
        RecursiveOpenStruct.new(yaml, :recurse_over_arrays => true)
      end
    end

    def raw_template
      @raw_template ||= build.file_from_repo(kubernetes_role.config_file)
    end

    # Sets the labels for the Deployment resource metadata
    def set_deployment_metadata
      deployment_labels.each do |key, value|
        template.metadata.labels[key] = value
      end
    end

    def deployment_labels
      release_doc_metadata.except(:release_id)
    end

    # Sets the metadata that is going to be used as the selector. Kubernetes will use this metadata to select the
    # old and new Replication Controllers when managing a new Deployment.
    def set_selector_metadata
      deployment_labels.each do |key, value|
        template.spec.selector[key] = value
      end
    end

    # Sets the labels for each new Pod.
    # Appending the Release ID to allow us to track the progress of a new release from the UI.
    def set_spec_template_metadata
      release_doc_metadata.each do |key, value|
        template.spec.template.metadata.labels[key] = value
      end
    end

    def set_resource_usage
      container.resources = {
        limits: { cpu: kubernetes_role.cpu, memory: kubernetes_role.ram_with_units }
      }
    end

    def update_docker_image
      docker_path = build.docker_repo_digest || "#{build.project.docker_repo}:#{build.docker_ref}"
      # Assume first container is one we want to update docker image in
      container.image = docker_path
    end

    def container
      template.spec.template.spec.containers.first
    end
  end
end
