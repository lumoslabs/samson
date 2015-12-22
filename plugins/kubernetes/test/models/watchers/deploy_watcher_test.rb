require_relative "../../test_helper"
require 'celluloid/current'


describe Watchers::DeployWatcher do
  let(:deploying_release) { kubernetes_releases(:test_release_deploying) }
  let(:complete_release) { kubernetes_releases(:test_release_complete) }

  before do
    Celluloid.shutdown; Celluloid.boot
    Watchers::DeployWatcher.any_instance.stubs(:end_deploy)
    Watchers::DeployWatcher.any_instance.stubs(:last_release).returns(deploying_release)
  end

  after { Celluloid.shutdown }

  describe '#initialize' do
    it 'gets in sync with the cluster' do
      Watchers::DeployWatcher.any_instance.expects(:sync_with_cluster).once
      Watchers::DeployWatcher.new(deploying_release.project)
    end

    it 'starts listening for pod events' do
      Watchers::DeployWatcher.any_instance.expects(:watch).once
      Watchers::DeployWatcher.new(deploying_release.project)
    end
  end

  describe '#sync_with_cluster' do
    before do
      Kubeclient::Client.any_instance.expects(:get_pods).once.returns([])
    end

    it 'fetches the current state from the Kubernetes cluster' do
      Watchers::DeployWatcher.new(deploying_release.project)
    end
  end

  # describe '#watch' do
  #
  #   it 'sets deploy as finished when all pods active' do
  #     watcher = Watchers::DeployWatcher.new(deploying_release.project)
  #
  #     deploying_release.release_docs.each do |release_doc|
  #       release_doc.replica_target.times do |i|
  #         msg = create_msg(name: "foo-#{i}", ready: 'True')
  #         watcher.handle_update(release_doc.replication_controller_name, msg)
  #       end
  #     end
  #     watcher.send(:deploy_finished?).must_equal true
  #   end
  #
  #   it 'sends SSE event when event received' do
  #     watcher = Watchers::DeployWatcher.new(deploying_release)
  #     SseRailsEngine.expects(:send_event).once
  #     watcher.handle_update(deploying_release.release_docs.first.replication_controller_name,
  #                           create_msg(name: 'foo', ready: 'True'))
  #   end
  # end

  def create_msg(type: 'ADDED', kind: 'Pod', status: 'Running', name:, ready: 'True')
    RecursiveOpenStruct.new(
      {
        type: type,
        object: {
          kind: kind,
          metadata: { name: name },
          status: {
            phase: status,
            conditions: [
              { type: 'Ready', status: ready }
            ]
          }
        },
      })
  end

  class FakeClient

    def initialize

    end

    def get_pods(options = {})
      []
    end

  end
end
