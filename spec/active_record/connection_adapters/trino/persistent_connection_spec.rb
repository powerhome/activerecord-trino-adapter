# frozen_string_literal: true

require "spec_helper"

RSpec.describe ActiveRecord::ConnectionAdapters::TrinoAdapter, "persistent HTTP connections" do
  include TrinoFake

  def faraday_instances_used(adapter, *sqls)
    instances = []
    allow(Trino::Client::StatementClient).to receive(:new).and_wrap_original do |original, faraday, *args|
      instances << faraday
      original.call(faraday, *args)
    end
    sqls.each { |sql| adapter.exec_query(sql) }
    instances
  end

  describe "with persistent: true" do
    let(:adapter) do
      ActiveRecord::ConnectionAdapters::TrinoAdapter.new(trino_config(persistent: true))
    end

    it "serves consecutive queries through the same Faraday connection" do
      stub_trino_query(sql: "SELECT 1", columns: [%w[n integer]], rows: [[1]])
      stub_trino_query(sql: "SELECT 2", columns: [%w[n integer]], rows: [[2]])

      instances = faraday_instances_used(adapter, "SELECT 1", "SELECT 2")

      expect(instances.size).to eq(2)
      expect(instances.uniq(&:object_id).size).to eq(1)
    end

    it "uses the net_http_persistent Faraday adapter" do
      faraday = adapter.send(:persistent_faraday)
      expect(faraday.builder.adapter.klass).to eq(Faraday::Adapter::NetHttpPersistent)
    end

    it "still returns correct results" do
      stub_trino_query(
        sql: "SELECT id FROM t",
        columns: [%w[id integer]],
        rows: [[1], [2]]
      )

      result = adapter.exec_query("SELECT id FROM t")
      expect(result.rows).to eq([[1], [2]])
    end

    it "keeps the gzip middleware when gzip: true is also configured" do
      gzip_adapter = ActiveRecord::ConnectionAdapters::TrinoAdapter.new(
        trino_config(persistent: true, gzip: true)
      )
      faraday = gzip_adapter.send(:persistent_faraday)
      expect(faraday.builder.handlers.map(&:klass)).to include(Faraday::Gzip::Middleware)
    end

    describe "#disconnect! / #reconnect!" do
      it "closes and discards the memoized connection, then rebuilds it after reconnect!" do
        stub_trino_query(sql: "SELECT 1", columns: [%w[n integer]], rows: [[1]])
        stub_trino_query(sql: "SELECT 2", columns: [%w[n integer]], rows: [[2]])

        adapter.exec_query("SELECT 1")
        first = adapter.instance_variable_get(:@persistent_faraday)
        expect(first).not_to be_nil

        expect(first).to receive(:close).and_call_original
        adapter.disconnect!
        expect(adapter.instance_variable_get(:@persistent_faraday)).to be_nil

        adapter.reconnect!
        adapter.exec_query("SELECT 2")
        second = adapter.instance_variable_get(:@persistent_faraday)
        expect(second).not_to be_nil
        expect(second).not_to equal(first)
      end

      it "keeps active? semantics unchanged" do
        expect(adapter.active?).to be true
        adapter.disconnect!
        expect(adapter.active?).to be false
        adapter.reconnect!
        expect(adapter.active?).to be true
      end
    end

    describe "retry on a kept-alive socket closed by the server" do
      it "re-opens transparently and completes the query" do
        statement_url = "#{TrinoFake::BASE_URL}/v1/statement"
        next_url = "#{TrinoFake::BASE_URL}/v1/next/q1"
        column_spec = { name: "n", type: "integer", typeSignature: { rawType: "integer" } }

        WebMock.stub_request(:post, statement_url).with(body: "SELECT 1")
               .to_return(
                 status: 200,
                 body: { id: "q1", nextUri: next_url, stats: { state: "RUNNING" } }.to_json,
                 headers: { "Content-Type" => "application/json" }
               )

        WebMock.stub_request(:get, next_url)
               .to_raise(Errno::ECONNRESET)
               .then
               .to_return(
                 status: 200,
                 body: {
                   id: "q1",
                   columns: [column_spec],
                   data: [[1]],
                   stats: { state: "FINISHED" },
                 }.to_json,
                 headers: { "Content-Type" => "application/json" }
               )

        result = adapter.exec_query("SELECT 1")

        expect(result.rows).to eq([[1]])
        expect(WebMock).to have_requested(:get, next_url).twice
      end
    end
  end

  describe "with persistent off or absent" do
    let(:adapter) do
      ActiveRecord::ConnectionAdapters::TrinoAdapter.new(trino_config)
    end

    it "builds a new Faraday connection per query" do
      stub_trino_query(sql: "SELECT 1", columns: [%w[n integer]], rows: [[1]])
      stub_trino_query(sql: "SELECT 2", columns: [%w[n integer]], rows: [[2]])

      instances = faraday_instances_used(adapter, "SELECT 1", "SELECT 2")

      expect(instances.size).to eq(2)
      expect(instances.uniq(&:object_id).size).to eq(2)
    end

    it "never memoizes a persistent Faraday connection" do
      stub_trino_query(sql: "SELECT 1", columns: [%w[n integer]], rows: [[1]])

      adapter.exec_query("SELECT 1")

      expect(adapter.instance_variable_get(:@persistent_faraday)).to be_nil
    end

    it "is also off when persistent: false is explicit" do
      explicit = ActiveRecord::ConnectionAdapters::TrinoAdapter.new(trino_config(persistent: false))
      stub_trino_query(sql: "SELECT 1", columns: [%w[n integer]], rows: [[1]])

      explicit.exec_query("SELECT 1")

      expect(explicit.instance_variable_get(:@persistent_faraday)).to be_nil
    end
  end
end
