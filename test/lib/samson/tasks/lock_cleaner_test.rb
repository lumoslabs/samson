require_relative '../../../test_helper'

describe Samson::Tasks::LockCleaner do
  subject { Samson::Tasks::LockCleaner.new }

  describe "#start" do
    before { Concurrent::TimerTask.any_instance.expects(:execute).once }

    it "starts the timer task" do
      subject.start
    end
  end

  describe "#task" do
    it 'sets the timeout interval' do
      subject.task.timeout_interval.must_equal 10
    end

    it "sets the execution interval" do
      subject.task.execution_interval.must_equal 60
    end

    it "adds an observer" do
      subject.task.count_observers.must_equal 1
    end
  end

  describe "#update" do
    let(:exp) { Exception.new("test").tap {|e| e.set_backtrace([]) } }

    it "does nothing without an exception" do
      Rails.logger.expects(:error).never
      subject.update(Time.now, nil, nil)
    end

    it "logs when given an exception" do
      Rails.logger.expects(:error).twice
      subject.update(Time.now, nil, exp)
    end
  end
end
