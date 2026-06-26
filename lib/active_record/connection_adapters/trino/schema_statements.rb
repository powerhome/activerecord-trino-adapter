# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module Trino
      module SchemaStatements
        def columns(table_name)
          table = table_name.to_s
          declared = ActiveRecord::Trino.static_columns[table]
          return build_static_columns(declared) if declared

          if bulk_column_reflection?
            column_definitions.fetch(table, [])
          else
            build_columns(run_trino_query(table_columns_query(table)).rows)
          end
        end

        def data_sources
          return ActiveRecord::Trino.static_columns.keys if static_schema?

          run_trino_query("SHOW TABLES").rows.map(&:first)
        end
        alias tables data_sources

        def table_exists?(table_name)
          data_sources.include?(table_name.to_s)
        end
        alias data_source_exists? table_exists?

        def primary_key(_table_name)
          nil
        end

        def indexes(_table_name)
          []
        end

        def foreign_keys(_table_name)
          []
        end

        def views
          []
        end

        def view_exists?(_view_name)
          false
        end

        def clear_column_cache!
          @column_definitions = nil
        end

      private

        def build_columns(rows)
          rows.map do |name, data_type, is_nullable|
            Trino::Column.new(
              name: name,
              sql_type: data_type,
              type: type_map.lookup(data_type),
              null: nullable?(is_nullable)
            )
          end
        end

        def build_static_columns(definitions)
          definitions.map do |definition|
            sql_type = definition.fetch(:sql_type)
            Trino::Column.new(
              name: definition.fetch(:name).to_s,
              sql_type: sql_type,
              type: type_map.lookup(sql_type),
              null: definition.fetch(:null, true)
            )
          end
        end

        def column_definitions
          @column_definitions ||= load_column_definitions
        end

        def load_column_definitions
          run_trino_query(all_columns_query).rows.group_by(&:first).transform_values do |rows|
            build_columns(rows.map { |row| row.drop(1) })
          end
        end

        def table_columns_query(table_name)
          <<~SQL.strip
            SELECT column_name, data_type, is_nullable
            FROM information_schema.columns
            WHERE table_catalog = #{quote(trino_catalog)}
              AND table_schema = #{quote(trino_schema)}
              AND table_name = #{quote(table_name)}
            ORDER BY ordinal_position
          SQL
        end

        def all_columns_query
          <<~SQL.strip
            SELECT table_name, column_name, data_type, is_nullable
            FROM information_schema.columns
            WHERE table_catalog = #{quote(trino_catalog)}
              AND table_schema = #{quote(trino_schema)}
            ORDER BY table_name, ordinal_position
          SQL
        end

        def trino_catalog
          @client_options[:catalog]
        end

        def trino_schema
          @client_options[:schema]
        end

        def nullable?(value)
          value.to_s.casecmp?("yes")
        end
      end
    end
  end
end
