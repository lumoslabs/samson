module Samson::Tasks
  class LockCleaner

    def self.start
      new.start
    end

    def start
      task.tap(&:execute)
    end

    def task
      @task ||= Concurrent::TimerTask.new(run_now: true, execution_interval: 60, timeout_interval: 10) do
        Lock.remove_expired_locks
      end.with_observer(self)
    end

    # called by Concurrent::TimerTask
    def update(time, result, ex)
      if ex
        Rails.logger.error "(#{time}) Samson::Tasks::LockCleaner failed with error #{ex}\n"
        Rails.logger.error ex.backtrace.join("\n")
      end
    end
  end
end
