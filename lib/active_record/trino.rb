# frozen_string_literal: true

require "active_record"
require "active_support"
require "active_support/notifications"
require "trino-client"

require_relative "trino/version"
require_relative "trino/errors"
require_relative "trino/config"
require_relative "trino/type/json"
require_relative "trino/type/timestamp_with_zone"
require_relative "trino/type/unsupported"
require_relative "trino/diagnostics"

if ActiveRecord::ConnectionAdapters.respond_to?(:register)
  ActiveRecord::ConnectionAdapters.register(
    "trino",
    "ActiveRecord::ConnectionAdapters::TrinoAdapter",
    "active_record/connection_adapters/trino_adapter"
  )
else
  # Rails 7.1 uses the legacy adapter_method pattern: ActiveRecord::Base needs
  # a trino_connection class method that returns a new TrinoAdapter. Rails 7.2+
  # replaced this with ConnectionAdapters.register above.
  require "active_record/connection_adapters/trino_adapter"
  ActiveRecord::Base.singleton_class.define_method(:trino_connection) do |config|
    ActiveRecord::ConnectionAdapters::TrinoAdapter.new(config)
  end
end

module ActiveRecord
  module Trino
    def self.reset_schema_cache!(model_class)
      model_class.reset_column_information

      model_class.connection_pool.connections.each do |conn|
        conn.clear_column_cache! if conn.respond_to?(:clear_column_cache!)
      end

      return unless model_class.connection.respond_to?(:schema_cache)

      model_class.connection.schema_cache.clear!
    end
  end
end
