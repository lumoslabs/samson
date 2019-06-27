# frozen_string_literal: true
require_relative '../test_helper'

SingleCov.covered!

describe DatadogMonitor do
  def assert_datadog(status: 200, times: 1, **params, &block)
    assert_request(
      :get, monitor_url,
      to_return: {body: api_response.merge(params).to_json, status: status},
      times: times,
      &block
    )
  end

  def assert_datadog_timeout(&block)
    assert_request(:get, monitor_url, to_timeout: [], &block)
  end

  let(:monitor) { DatadogMonitor.new(123) }
  let(:monitor_url) do
    "https://api.datadoghq.com/api/v1/monitor/123?api_key=dapikey&application_key=dappkey&group_states=alert"
  end
  let(:api_response) { JSON.parse('{"name":"Monitor Slow foo","query":"max(last_30m):max:foo.metric.time.max{*} > 20000","overall_state":"Ok","type":"metric alert","message":"This is mostly informative... @foo@bar.com","org_id":1234,"id":123,"options":{"notify_no_data":false,"no_data_timeframe":60,"notify_audit":false,"silenced":{}}}') } # rubocop:disable Metrics/LineLength
  let(:alerting_groups) { {state: {groups: {"pod:pod1": {}}}} }

  describe "#state" do
    let(:groups) { [deploy_groups(:pod1), deploy_groups(:pod2)] }

    before do
      monitor.match_target = "pod"
      monitor.match_source = "deploy_group.permalink"
    end

    it "returns simple state when asking for global state" do
      assert_datadog(overall_state: "OK") do
        monitor.state([]).must_equal "OK"
      end
    end

    it "returns simple state when match_source was not set" do
      assert_datadog(overall_state: "OK") do
        monitor.match_source = ""
        monitor.state(groups).must_equal "OK"
      end
    end

    it "shows unknown using fallback monitor" do
      assert_datadog overall_state: nil do
        monitor.state(groups).must_be_nil
      end
    end

    it "shows OK when groups are not alerting" do
      assert_datadog(state: {groups: {}}) do
        monitor.state(groups).must_equal "OK"
      end
    end

    it "shows Alert when groups are alerting" do
      assert_datadog alerting_groups do
        monitor.state(groups).must_equal "Alert"
      end
    end

    it "shows Alert when nested groups are alerting" do
      assert_datadog(state: {groups: {"foo:bar,pod:pod1,bar:foo": {}}}) do
        monitor.state(groups).must_equal "Alert"
      end
    end

    it "shows OK when other groups are alerting" do
      assert_datadog(state: {groups: {"pod:pod3": {}}}) do
        monitor.state(groups).must_equal "OK"
      end
    end

    it "raises on unknown source" do
      assert_datadog(state: {groups: {"pod:pod3": {}}}) do
        monitor.match_source = "wut"
        assert_raises(ArgumentError) { monitor.state(groups) }
      end
    end

    it "produces no extra sql queries" do
      stage = stages(:test_production) # preload
      assert_sql_queries 2 do # group-stage + groups
        assert_datadog alerting_groups do
          monitor.state(stage.deploy_groups)
        end
      end
    end

    it "runs no sql query when there are no alerts" do
      stage = stages(:test_production) # preload
      assert_sql_queries 0 do
        assert_datadog(state: {groups: {}}) do
          monitor.state(stage.deploy_groups)
        end
      end
    end

    it "can match on environment" do
      monitor.match_source = "environment.permalink"
      assert_datadog(state: {groups: {"pod:production": {}}}) do
        monitor.state(groups).must_equal "Alert"
      end
    end

    it "can match on deploy_group.env_value" do
      monitor.match_source = "deploy_group.env_value"
      assert_datadog(state: {groups: {"pod:pod1": {}}}) do
        monitor.state(groups).must_equal "Alert"
      end
    end

    describe "cluster matching" do
      before { monitor.match_source = "kubernetes_cluster.permalink" }

      it "can query by cluster" do
        assert_datadog(state: {groups: {"pod:foo1": {}}}) do
          groups.each { |g| g.kubernetes_cluster.name = "Foo 1" }
          monitor.state(groups).must_equal "Alert"
        end
      end

      it "ignores missing clusters" do
        assert_datadog(state: {groups: {"pod:foo1": {}}}) do
          groups.each { |g| g.kubernetes_cluster = nil }
          monitor.state(groups).must_equal "OK"
        end
      end
    end
  end

  describe "#name" do
    it "is there" do
      assert_datadog(overall_state: "OK") do
        monitor.name.must_equal "Monitor Slow foo"
      end
    end

    it "is error when request times out" do
      Samson::ErrorNotifier.expects(:notify)
      assert_datadog_timeout do
        silence_stderr { monitor.name.must_equal "api error" }
      end
    end

    it "is error when request fails" do
      assert_datadog(overall_state: "OK", status: 404) do
        silence_stderr { monitor.name.must_equal "api error" }
      end
    end
  end

  describe "#url" do
    it "builds a url" do
      monitor.url.must_equal "https://app.datadoghq.com/monitors/123"
    end
  end

  describe "caching" do
    it "caches the api response" do
      assert_datadog(overall_state: "OK") do
        monitor.name
        monitor.state([])
      end
    end

    it "expires the cache when reloaded" do
      assert_datadog(overall_state: "OK", times: 2) do
        monitor.name
        monitor.reload_from_api
        monitor.name
      end
    end
  end

  describe ".list" do
    let(:url) { "https://api.datadoghq.com/api/v1/monitor?api_key=dapikey&application_key=dappkey&group_states=alert" }

    it "finds multiple" do
      assert_request(:get, url, to_return: {body: [{id: 1, name: "foo"}].to_json}) do
        DatadogMonitor.list({}).map(&:name).must_equal ["foo"]
      end
    end

    it "adds tags" do
      assert_request(:get, url + "&monitor_tags=foo,bar", to_return: {body: [{id: 1, name: "foo"}].to_json}) do
        DatadogMonitor.list("foo,bar")
      end
    end

    it "shows api error in the UI when it times out" do
      Samson::ErrorNotifier.expects(:notify)
      assert_request(:get, url, to_timeout: []) do
        DatadogMonitor.list({}).map(&:name).must_equal ["api error"]
      end
    end

    it "shows api error in the UI when it fails" do
      Samson::ErrorNotifier.expects(:notify)
      assert_request(:get, url, to_return: {status: 500}) do
        DatadogMonitor.list({}).map(&:name).must_equal ["api error"]
      end
    end
  end
end
