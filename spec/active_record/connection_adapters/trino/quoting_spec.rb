# frozen_string_literal: true

require "spec_helper"
require "bigdecimal"

RSpec.describe ActiveRecord::ConnectionAdapters::Trino::Quoting do
  let(:host_class) do
    Class.new do
      include ActiveRecord::ConnectionAdapters::Trino::Quoting
    end
  end

  let(:host) { host_class.new }

  describe "#quote" do
    it "renders nil as NULL" do
      expect(host.quote(nil)).to eq("NULL")
    end

    it "renders true and false" do
      expect(host.quote(true)).to eq("true")
      expect(host.quote(false)).to eq("false")
    end

    it "renders integers and floats as bare numerics" do
      expect(host.quote(42)).to eq("42")
      expect(host.quote(-17)).to eq("-17")
      expect(host.quote(3.14)).to eq("3.14")
    end

    it "renders BigDecimal without scientific notation" do
      expect(host.quote(BigDecimal("12345.6789"))).to eq("12345.6789")
    end

    it "renders Date as Trino DATE literal" do
      expect(host.quote(Date.new(2024, 1, 31))).to eq("DATE '2024-01-31'")
    end

    it "renders Time as Trino TIMESTAMP literal in UTC" do
      t = Time.utc(2024, 1, 31, 12, 34, 56)
      expect(host.quote(t)).to eq("TIMESTAMP '2024-01-31 12:34:56.000'")
    end

    it "single-quotes strings and doubles internal apostrophes" do
      expect(host.quote("hello")).to eq("'hello'")
      expect(host.quote("it's")).to eq("'it''s'")
    end

    it "single-quotes symbols" do
      expect(host.quote(:status)).to eq("'status'")
    end
  end

  describe "#quote_string SQL-injection payloads" do
    payloads = [
      "normal value",
      "'; DROP TABLE users; --",
      "Robert'); DROP TABLE students;",
      "1' OR '1'='1",
      "admin' --",
      "''",
      "''''",
      "abc'def",
      "abc''def",
      "abc\\def",
      "abc\ndef",
      "abc\tdef",
      "abc\rdef",
      "ñ",
      "你好",
      "𝕏",
    ]

    payloads.each do |payload|
      it "round-trips #{payload.inspect}" do
        quoted = host.quote(payload)
        expect(quoted.start_with?("'")).to be true
        expect(quoted.end_with?("'")).to be true
        inner = quoted[1..-2]
        unquoted = inner.gsub("''", "'")
        expect(unquoted).to eq(payload)
      end
    end

    it "raises on a NUL byte" do
      nul_string = "abc#{0.chr}def"
      expect { host.quote_string(nul_string) }.to raise_error(ActiveRecord::Trino::Error, /NUL byte/)
    end

    it "raises through #quote when a NUL byte is embedded" do
      nul_string = "abc#{0.chr}def"
      expect { host.quote(nul_string) }.to raise_error(ActiveRecord::Trino::Error, /NUL byte/)
    end
  end

  describe "#quote_column_name" do
    it "double-quotes simple identifiers" do
      expect(host.quote_column_name("col_a")).to eq(%("col_a"))
    end

    it "doubles internal double-quotes" do
      expect(host.quote_column_name(%(weird"name))).to eq(%("weird""name"))
    end
  end

  describe "#quote_table_name" do
    it "quotes a single segment" do
      expect(host.quote_table_name("orders")).to eq(%("orders"))
    end

    it "quotes catalog.schema.table by splitting on dots" do
      expect(host.quote_table_name("hive.public.orders"))
        .to eq(%("hive"."public"."orders"))
    end

    it "doubles internal double-quotes per segment" do
      expect(host.quote_table_name(%(weird"schema.orders)))
        .to eq(%("weird""schema"."orders"))
    end
  end

  describe "#quoted_true / #quoted_false" do
    it { expect(host.quoted_true).to eq("true") }
    it { expect(host.quoted_false).to eq("false") }
  end

  # Rails 7.2+ quotes identifiers at the class level, so `include Trino::Quoting`
  # must expose quote_column_name/quote_table_name as class methods too. The instance
  # methods above delegate to these. See quoting.rb's ClassMethods.
  describe "class-level quoting (Rails 7.2+)" do
    it "double-quotes and escapes column names on the class" do
      expect(host_class.quote_column_name("col_a")).to eq(%("col_a"))
      expect(host_class.quote_column_name(%(a"b))).to eq(%("a""b"))
    end

    it "quotes dotted table names on the class" do
      expect(host_class.quote_table_name("schema.tbl")).to eq(%("schema"."tbl"))
    end

    it "exposes the same class methods on the real TrinoAdapter" do
      require "active_record/connection_adapters/trino_adapter"
      adapter = ActiveRecord::ConnectionAdapters::TrinoAdapter
      expect(adapter.quote_column_name(%(a"b))).to eq(%("a""b"))
      expect(adapter.quote_table_name("schema.tbl")).to eq(%("schema"."tbl"))
    end

    it "delegates the instance methods to the class methods" do
      expect(host.quote_column_name("col_a")).to eq(host_class.quote_column_name("col_a"))
      expect(host.quote_table_name("schema.tbl")).to eq(host_class.quote_table_name("schema.tbl"))
    end
  end
end
