require 'celluloid/current'
require 'logger'

Celluloid.logger = Rails.logger
$CELLULOID_DEBUG = true

if ENV['SERVER_MODE'] && !ENV['PRECOMPILE']
  Kubernetes::Cluster.all.each { |cluster| Watchers::ClusterPodWatcher::start_watcher(cluster) }
end
