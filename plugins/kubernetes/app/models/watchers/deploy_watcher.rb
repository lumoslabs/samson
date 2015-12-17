module Watchers
  # Instantiated when a Kubernetes deploy is created to watch the status
  class DeployWatcher
    include Celluloid
    include Celluloid::Notifications
    include Celluloid::Internals::Logger

    finalizer :on_termination

    def initialize(project)
      @project = project
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

      handle_pod_update(event.pod) do |release_doc|
        send_event({
          project: release_doc.kubernetes_release.project.id,
          build: release_doc.kubernetes_release.build.label,
          release: release_doc.kubernetes_release.id,
          role: release_doc.kubernetes_role.id,
          deploy_group: release_doc.deploy_group.id,
          target_replicas: release_doc.replica_target,
          live_replicas: release_doc.replicas_live
        })

        terminate_watcher if deploy_finished?(release_doc.kubernetes_release.project)
      end
    end

    private

    def rcs
      @rcs ||= {}
    end

    def rc_pods(rc_unique_id)
      rcs[rc_unique_id] ||= {}
      rcs[rc_unique_id]
    end

    def sync_with_cluster
      # Fetches data from all clusters and builds the internal data structures
      Environment.all.each do |env|
        env.cluster_deploy_groups.each do |cdg|
          cdg.cluster.client.get_pods(namespace: cdg.namespace, label_selector: "project_id=#{@project.id}").each do |pod|
            pod = Kubernetes::Api::Pod.new(pod)
            rc = rc_pods(pod.rc_unique_identifier)
            rc[pod.name] = pod
          end
        end
      end

      # Gets the database in sync with the data retrieved from the cluster
      rcs.each_value do |pods|
        pods.each_value do |pod|
          handle_pod_update(pod)
        end
      end
    end

    def handle_pod_update(pod)
      project = Project.find(pod.project_id)
      release = Kubernetes::Release.find(pod.release_id)
      release_doc = release.release_doc_for(pod.deploy_group_id, pod.role_id)

      rc = rc_pods(pod.rc_unique_identifier)
      rc[pod.name] = pod

      if old_release?(project, release)
        update_previous_release(pod, release_doc)
      else
        update_current_release(pod, release_doc)
      end

      yield release_doc if block_given?
    end

    def update_previous_release(pod, release_doc)
      terminated_pods = terminated_pods_count(pod.rc_unique_identifier)
      live_pods = release_doc.replica_target - terminated_pods
      Rails.logger.debug("[Previous Release] Current Live: #{live_pods}, Terminated: #{terminated_pods}")
      update_release_progress(release_doc, live_pods)
    end

    def update_current_release(pod, release_doc)
      live_pods = live_pods_count(pod.rc_unique_identifier)
      Rails.logger.debug("[Current Release] Current Live: #{live_pods}")
      update_release_progress(release_doc, live_pods)
    end

    def update_release_progress(release_doc, live_pods)
      if release_doc.live_replicas_changed?(live_pods)
        update_replica_count(release_doc, live_pods)
        update_release_status(release_doc)
      end
    end

    def update_replica_count(release_doc, live_replicas)
      release_doc.update_replica_count(live_replicas)
      release_doc.save!
    end

    def update_release_status(release_doc)
      release = release_doc.kubernetes_release
      case
      when live?(release) then
        release.status = :live
      when spinning_up?(release_doc) then
        release.status = :spinning_up
      when spinning_down?(release_doc) then
        release.status = :spinning_down
      when dead?(release) then
        release.status = :dead
      else
        Rails.logger.debug("Release status: #{release.status}")
      end
      release.save!
    end

    def old_release?(project, release)
      last_release(project).id > release.id
    end

    def current_release?(project, release)
      last_release(project) == release
    end

    def last_release(project)
      project.kubernetes_releases.last
    end

    def terminated_pods_count(rc_unique_identifier)
      rc = rc_pods(rc_unique_identifier)
      rc.reduce(0) { |count, (_pod_name, _pod)| count += 1 if _pod.not_ready?; count }
    end

    def live_pods_count(rc_unique_identifier)
      rc = rc_pods(rc_unique_identifier)
      rc.reduce(0) { |count, (_pod_name, _pod)| count += 1 if _pod.live?; count }
    end

    def live?(release)
      release.release_docs.all?(&:live?)
    end

    def dead?(release)
      release.release_docs.all?(&:dead?)
    end

    def spinning_up?(release_doc)
      release_doc.spinning_up?
    end

    def spinning_down?(release_doc)
      release_doc.spinning_down?
    end

    def deploy_finished?(project)
      last_release(project).live? && project.kubernetes_releases.where("id < ?", last_release(project).id).all?(&:dead?)
    end

    def on_termination
      info('Finished Watching Deployments!')
    end

    def terminate_watcher
      info('Deploy finished!')
      terminate
    end

    def send_event(options)
      info("[SSE] Sending: #{options}")
      SseRailsEngine.send_event('k8s', options)
    end
  end
end
