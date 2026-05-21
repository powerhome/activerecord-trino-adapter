# frozen_string_literal: true

module ActiveRecord
  module Trino
    class Error < StandardError; end

    class ReadOnlyError < Error; end

    class UnsupportedTypeError < Error; end

    class ConfigurationError < Error; end
  end
end
