module Watchers
  class DeployWatcher
    include Celluloid
    include Celluloid::Notifications
    include Celluloid::Internals::Logger

    finalizer :on_termination

    def initialize(project)
      @project = project
      start_watching
    end

    def start_watching
      sync_with_cluster
      info 'Start watching for deployments'
      async :watch
    end

    def watch
      subscribe("pod-events-project-#{@project.id}", :handle_event)
    end

    def handle_event(topic, data)
      info "Got Pod Event on topic #{topic}"
      event = Events::PodEvent.new(data)
      return error('Invalid Kubernetes Pod Event') unless event.valid?

      pod = event.pod

      # Inject attribute accessor to check if the Pod has been deleted when we get a deleted event
      if event.deleted?
        class << pod
          attr_accessor :deleted
          alias :deleted? :deleted
        end
        pod.deleted = true
      end

      handle_pod_update(event.pod) do |release_doc|
        send_event(release_doc)
        terminate_watcher if deploy_finished?(project)
      end
    end

    private

    def project
      @project
    end

    def rcs
      @rcs ||= {}
    end

    def rc_pods(rc_unique_id)
      rcs[rc_unique_id] ||= {}
      rcs[rc_unique_id]
    end

    def release_ids_from_cluster
      rcs.map { |_, pods| pods.map { |_, pod| pod.release_id } }.flatten.uniq
    end

    # Gets the database in-sync with the Kubernetes Cluster
    def sync_with_cluster
      fetch_cluster_data
      reconcile_old_releases
      reconcile_db_with_cluster
    end

    # From the target environment for the current Release, fetches all existing Pods from the corresponding
    # Kubernetes Clusters and updates the internal data structures used by the watcher.
    def fetch_cluster_data
      env = last_release(project).deploy_groups.first.environment

      env.cluster_deploy_groups.each do |cdg|
        cdg.cluster.client.get_pods(namespace: cdg.namespace, label_selector: "project_id=#{project.id}").each do |pod|
          pod = Kubernetes::Api::Pod.new(pod)
          rc = rc_pods(pod.rc_unique_identifier)
          rc[pod.name] = pod
        end
      end
    end

    # Will mark as :dead each previous Release for which there is no Pod in the cluster.
    # Will mark as :dead each ReleaseDoc belonging to a previous Release for which there is no Pod in the cluster.
    def reconcile_old_releases
      excluded_from_sync = release_ids_from_cluster << last_release(project).id

      scope = project.kubernetes_releases.excluding(excluded_from_sync)

      # Updates the Releases status to :dead
      scope.not_dead.update_all(status: :dead)

      # Updates all relevant ReleaseDocs status to :dead
      scope.with_not_dead_release_docs.distinct.each { |rel| rel.release_docs.update_all(status: :dead) }
    end

    # Get previous releases in sync with the cluster (when there's at least a Pod in the cluster)
    def reconcile_db_with_cluster
      rcs.each_value { |pods| pods.each_value { |pod| handle_pod_update(pod) } }
    end

    def handle_pod_update(pod)
      rc = rc_pods(pod.rc_unique_identifier)
      rc[pod.name] = pod
      release = Kubernetes::Release.find(pod.release_id)
      release_doc = release.release_doc_for(pod.deploy_group_id, pod.role_id)

      live_pods = count_live_pods(pod.rc_unique_identifier)

      if release_doc.live_replicas_changed?(live_pods)
        release_doc.update_release_progress(live_pods)
        yield release_doc if block_given?
      end
    end

    def last_release(project)
      project.kubernetes_releases.last
    end

    def count_live_pods(rc_unique_identifier)
      rc = rc_pods(rc_unique_identifier)
      rc.reduce(0) { |count, (_, pod)| count += 1 if pod.live? && !deleted?(pod); count }
    end

    def deleted?(pod)
      pod.respond_to?(:deleted?) && pod.deleted?
    end

    def deploy_finished?(project)
      last_release(project).live? && project.kubernetes_releases.excluding(last_release(project).id).all?(&:dead?)
    end

    def on_termination
      info('Finished Watching Deployments!')
    end

    def terminate_watcher
      info('Deploy finished!')
      terminate
    end

    def send_event(release_doc)
      debug("[SSE] Sending: #{sse_event_data(release_doc)}")
      SseRailsEngine.send_event('k8s', sse_event_data(release_doc))
    end

    def sse_event_data(release_doc)
      {
        project: release_doc.kubernetes_release.project.id,
        build: release_doc.kubernetes_release.build.label,
        release: release_doc.kubernetes_release.id,
        role: release_doc.kubernetes_role.id,
        deploy_group: release_doc.deploy_group.id,
        target_replicas: release_doc.replica_target,
        live_replicas: release_doc.replicas_live
      }
    end
  end
end
