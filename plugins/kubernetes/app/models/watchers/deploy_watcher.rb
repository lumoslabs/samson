module Watchers
  # Instantiated when a Kubernetes deploy is created to watch the status
  class DeployWatcher
    include Celluloid
    include Celluloid::Notifications
    include Celluloid::Internals::Logger

    finalizer :on_termination

    def initialize(release)
      @release = release
      @current_rcs = {}
      info "Start watching K8s deploy: #{@release}"
      async :watch
    end

    def watch
      subscribe("pod-events-#{@release.build.project.id}", :handle_update)
    end

    def handle_update(topic, data)
      info "Got Pod Event on topic: #{topic}"
      event = Events::PodEvent.new(data)
      return error('Invalid Kubernetes Pod Event') unless event.valid?
      handle_pod_event(event)
    end

    private

    def handle_pod_event(pod_event)
      pod = pod_event.pod
      project = Project.find(pod.project_id)
      release = Kubernetes::Release.find(pod.release_id)
      release_doc = release.release_doc_for(pod.deploy_group_id, pod.role_id)

      rc = rc_pods(release_doc.replication_controller_name)

      if pod_event.deleted?
        # Pod deleted event => Release is spinning down (most probably the previous release)
        rc.delete(pod.name)
        update_release_progress(release_doc)
      else
        # Current release => update replica count, otherwise ignore event (e.g. pod modified events for the previous release)
        if current_release?(release)
          rc[pod.name] = pod
          update_release_progress(release_doc)
        end
      end

      end_deploy if deploy_finished?(project)
    end

    def update_release_progress(release_doc)
      live_replicas = live_replicas_count(release_doc)

      if release_doc.live_replicas_changed?(live_replicas)
        update_replica_count(release_doc, live_replicas)
        update_release_status(release_doc)

        send_event({
          project: project.id,
          build: release_doc.release.build.label,
          release: release_doc.kubernetes_release.id,
          role: release_doc.kubernetes_role.id,
          deploy_group: release_doc.deploy_group.id,
          target_replicas: release_doc.replica_target,
          live_replicas: release_doc.replicas_live
        })
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

    def live_replicas_changed?(release_doc, live_replicas)
      release_doc.replicas_live != live_replicas
    end

    def current_release?(release)
      @release == release
    end

    def live_replicas_count(release_doc)
      rc = rc_pods(release_doc.replication_controller_name)
      rc.reduce(0) { |count, (_pod_name, _pod)| count += 1 if _pod.ready? and related?(_pod, release_doc); count }
    end

    def related?(pod, release_doc)
      release_doc.kubernetes_release.id == pod.release_id and release_doc.kubernetes_role.id == pod.role_id and
        release_doc.deploy_group.id == pod.deploy_group_id
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
      @release.live? && project.kubernetes_releases.select { |release| release != @release }.all?(&:dead?)
    end

    def on_termination
      Rails.logger.info('Finished Watching Deploy!')
    end

    def end_deploy
      @release.deploy_finished!
      Rails.logger.info("Deploy finished. Current release is #{@release.status}!")
      terminate
    end

    def rc_pods(name)
      @current_rcs[name] ||= {}
      @current_rcs[name]
    end

    def send_event(options)
      Rails.logger.info("[SSE] Sending: #{options}")
      SseRailsEngine.send_event('k8s', options)
    end
  end
end
