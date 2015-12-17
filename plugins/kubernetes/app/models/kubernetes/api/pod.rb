module Kubernetes
  module Api
    class Pod
      def initialize(api_pod)
        @pod = api_pod
      end

      def ready?
        condition_ready?
        # @pod.status.phase == 'Running' && condition_ready?
      end

      def name
        @pod.metadata.name
      end

      def project_id
        @pod.metadata.labels.project_id.to_i
      end

      def release_id
        @pod.metadata.labels.release_id.to_i
      end

      def deploy_group_id
        @pod.metadata.labels.deploy_group_id.to_i
      end

      def role_id
        @pod.metadata.labels.role_id.to_i
      end

      private

      def condition_ready?
        if @pod.status.conditions.present?
          ready = @pod.status.conditions.find { |c| c['type'] == 'Ready' }
          ready && ready['status'] == 'True'
        else
          false
        end
      end
    end
  end
end
