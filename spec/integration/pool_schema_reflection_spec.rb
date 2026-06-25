# frozen_string_literal: true

require "spec_helper"

# Regression test for the per-connection schema cache.

RSpec.describe "pool-level schema reflection" do
  include TrinoFake

  let(:statement_url) { "#{TrinoFake::BASE_URL}/v1/statement" }

  before do
    ActiveRecord::Base.establish_connection(trino_config(pool: 5))

    stub_trino_query(
      sql: "SHOW TABLES",
      columns: [%w[Table varchar]],
      rows: [["orders"]],
      query_id: "show_tables"
    )
    stub_trino_query(
      sql: /information_schema\.columns/,
      columns: [%w[table_name varchar], %w[column_name varchar], %w[data_type varchar], %w[is_nullable varchar]],
      rows: [%w[orders id bigint NO]],
      query_id: "columns"
    )
  end

  after do
    ActiveRecord::Base.connection_handler.clear_all_connections!(:all)
  end

  it "runs SHOW TABLES only once across separate pooled connections" do
    pool = ActiveRecord::Base.connection_pool
    conn_a = pool.checkout
    conn_b = pool.checkout

    begin
      expect(conn_a).not_to equal(conn_b)

      conn_a.schema_cache.data_source_exists?("orders")
      conn_b.schema_cache.data_source_exists?("orders")
    ensure
      pool.checkin(conn_a)
      pool.checkin(conn_b)
    end

    expect(
      a_request(:post, statement_url).with(body: "SHOW TABLES")
    ).to have_been_made.once
  end

  it "reflects columns only once across separate pooled connections" do
    pool = ActiveRecord::Base.connection_pool
    conn_a = pool.checkout
    conn_b = pool.checkout

    begin
      conn_a.schema_cache.columns("orders")
      conn_b.schema_cache.columns("orders")
    ensure
      pool.checkin(conn_a)
      pool.checkin(conn_b)
    end

    expect(
      a_request(:post, statement_url).with(body: /information_schema\.columns/)
    ).to have_been_made.once
  end
end
