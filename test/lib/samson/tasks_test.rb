require_relative '../../test_helper'

describe Samson::Tasks do
  describe ".start" do
    before do
      Samson::Tasks::LockCleaner.expects(:start).once
    end

    it 'starts the tasks' do
      Samson::Tasks.start
    end
  end
end
