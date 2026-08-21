# frozen_string_literal: true

require "spec_helper"

# A lightweight AR model defined at file scope so AR doesn't complain about
# anonymous classes during boot. The class is named via const_set so
# ActiveRecord::Base.descendants can find it.
class FakeOrder < ActiveRecord::Base
  self.table_name = "orders"
end

RSpec.describe "end-to-end Trino-backed AR model" do
  include TrinoFake

  before do
    ActiveRecord::Base.establish_connection(trino_config)

    stub_trino_query(
      sql: /information_schema\.columns/,
      columns: [%w[column_name varchar], %w[data_type varchar], %w[is_nullable varchar]],
      rows: [
        %w[id bigint NO],
        %w[territory_id integer YES],
        ["total", "decimal(10, 2)", "YES"],
      ],
      query_id: "schema"
    )

    stub_trino_query(
      sql: "SHOW TABLES",
      columns: [%w[Table varchar]],
      rows: [["orders"]],
      query_id: "show_tables"
    )

    FakeOrder.reset_column_information
  end

  after do
    ActiveRecord::Base.connection_handler.clear_all_connections!(:all)
  end

  it "materializes rows through AR" do
    stub_trino_query(
      sql: /SELECT.*FROM "orders"/i,
      columns: [["id", "bigint"], ["territory_id", "integer"], ["total", "decimal(10, 2)"]],
      rows: [
        [1, 42, "199.99"],
        [2, 7, "1500.00"],
      ],
      query_id: "select"
    )

    rows = FakeOrder.all.to_a

    expect(rows.size).to eq(2)
    expect(rows.first.id).to eq(1)
    expect(rows.first.territory_id).to eq(42)
    expect(rows.last.total).to eq(BigDecimal("1500.00"))
  end

  # Regression: Rails 7.2 moved identifier quoting to class-level methods
  # (Calculations#execute_grouped_calculation calls `adapter_class.quote_column_name`),
  # where AbstractAdapter's class method raises NotImplementedError by default. Grouped
  # calculations broke with a bare NotImplementedError until Trino::Quoting exposed
  # quoting via ClassMethods. See lib/active_record/connection_adapters/trino/quoting.rb.
  it "runs a grouped sum without raising" do
    stub_trino_query(
      sql: /SELECT SUM\("orders"\."total"\).*GROUP BY "orders"\."territory_id"/m,
      columns: [["sum_total", "decimal(10, 2)"], ["orders_territory_id", "integer"]],
      rows: [
        ["199.99", 42],
        ["1500.00", 7],
      ],
      query_id: "grouped_sum"
    )

    result = FakeOrder.group(:territory_id).sum(:total)

    expect(result).to be_a(Hash)
    expect(result).to eq(42 => BigDecimal("199.99"), 7 => BigDecimal("1500.00"))
  end

  it "runs a grouped count without raising" do
    stub_trino_query(
      sql: /SELECT COUNT\(\*\).*GROUP BY "orders"\."territory_id"/m,
      columns: [%w[count_all bigint], %w[orders_territory_id integer]],
      rows: [
        ["1", 42],
        ["2", 7],
      ],
      query_id: "grouped_count"
    )

    result = FakeOrder.group(:territory_id).count

    expect(result).to be_a(Hash)
    expect(result).to eq(42 => 1, 7 => 2)
  end

  it "raises for find_each (Trino batching is unsupported)" do
    expect { FakeOrder.find_each { |_o| nil } }
      .to raise_error(ActiveRecord::Trino::Error, /find_each/)
  end

  it "raises when attempting to save" do
    instance = FakeOrder.new
    expect { instance.save }.to raise_error(ActiveRecord::Trino::ReadOnlyError)
  end
end
