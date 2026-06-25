# frozen_string_literal: true

require "spec_helper"

RSpec.describe ActiveRecord::ConnectionAdapters::Trino::SchemaStatements do
  include TrinoFake

  let(:adapter) do
    ActiveRecord::ConnectionAdapters::TrinoAdapter.new(trino_config)
  end

  let(:statement_url) { "#{TrinoFake::BASE_URL}/v1/statement" }

  describe "#columns (default: per-table reflection)" do
    it "queries information_schema.columns for the single table and returns Trino::Column instances" do
      expected_sql = <<~SQL.strip
        SELECT column_name, data_type, is_nullable
        FROM information_schema.columns
        WHERE table_catalog = 'test_catalog'
          AND table_schema = 'test_schema'
          AND table_name = 'orders'
        ORDER BY ordinal_position
      SQL

      stub_trino_query(
        sql: expected_sql,
        columns: [%w[column_name varchar], %w[data_type varchar], %w[is_nullable varchar]],
        rows: [
          %w[id bigint NO],
          %w[name varchar YES],
          ["created_at", "timestamp(3)", "YES"],
        ]
      )

      columns = adapter.columns("orders")

      expect(columns.map(&:name)).to eq(%w[id name created_at])
      expect(columns.first.sql_type).to eq("bigint")
      expect(columns.first.null).to be false
      expect(columns[1].null).to be true
      expect(columns.last.cast_type).to be_a(ActiveModel::Type::DateTime)
    end

    it "reflects each table independently (one query per table)" do
      stub_trino_query(
        sql: /table_name = 'orders'/, columns: [%w[c varchar]], rows: [%w[id bigint NO]], query_id: "o"
      )
      stub_trino_query(
        sql: /table_name = 'users'/, columns: [%w[c varchar]], rows: [%w[email varchar YES]], query_id: "u"
      )

      adapter.columns("orders")
      adapter.columns("users")

      expect(a_request(:post, statement_url).with(body: /information_schema\.columns/)).to have_been_made.twice
    end
  end

  describe "#columns (bulk_column_reflection: true)" do
    let(:adapter) do
      ActiveRecord::ConnectionAdapters::TrinoAdapter.new(trino_config(bulk_column_reflection: true))
    end

    let(:bulk_sql) do
      <<~SQL.strip
        SELECT table_name, column_name, data_type, is_nullable
        FROM information_schema.columns
        WHERE table_catalog = 'test_catalog'
          AND table_schema = 'test_schema'
        ORDER BY table_name, ordinal_position
      SQL
    end

    it "serves every table from a single reflection query (no per-table round trips)" do
      stub_trino_query(
        sql: bulk_sql,
        columns: [%w[table_name varchar], %w[column_name varchar], %w[data_type varchar], %w[is_nullable varchar]],
        rows: [
          %w[orders id bigint NO],
          %w[users email varchar YES],
        ]
      )

      expect(adapter.columns("orders").map(&:name)).to eq(%w[id])
      expect(adapter.columns("users").map(&:name)).to eq(%w[email])
      expect(adapter.columns("missing")).to eq([])

      expect(a_request(:post, statement_url).with(body: bulk_sql)).to have_been_made.once
    end

    it "re-runs the reflection after the column cache is cleared" do
      stub_trino_query(
        sql: bulk_sql,
        columns: [%w[table_name varchar], %w[column_name varchar], %w[data_type varchar], %w[is_nullable varchar]],
        rows: [%w[orders id bigint NO]]
      )

      adapter.columns("orders")
      adapter.clear_column_cache!
      adapter.columns("orders")

      expect(a_request(:post, statement_url).with(body: bulk_sql)).to have_been_made.twice
    end
  end

  describe "#data_sources" do
    it "parses SHOW TABLES" do
      stub_trino_query(
        sql: "SHOW TABLES",
        columns: [%w[Table varchar]],
        rows: [["orders"], ["users"]]
      )

      expect(adapter.data_sources).to eq(%w[orders users])
    end
  end

  describe "#primary_key / #indexes / #foreign_keys" do
    it "always returns nil/empty (Trino has no PKs/indexes/FKs)" do
      expect(adapter.primary_key("anything")).to be_nil
      expect(adapter.indexes("anything")).to eq([])
      expect(adapter.foreign_keys("anything")).to eq([])
    end
  end
end
