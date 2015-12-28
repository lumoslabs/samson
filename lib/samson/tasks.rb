module Samson::Tasks
  def self.start
    LockCleaner.start
  end
end
