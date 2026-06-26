## [0.2.1] - 2026-06-26

- New runtime dependency on `faraday-net_http_persistent` (>= 1.2). The 1.x line
  is supported so consumers pinned to faraday 1.x (e.g. via elasticsearch-transport
  or kickbox)

## [0.2.0] - 2026-06-26

- Opt-in persistent HTTP connections via a new `persistent: true` key in
  `database.yml`. The adapter memoizes one keep-alive Faraday connection per
  adapter instance (built on `faraday-net_http_persistent`), eliminating the
  TCP + TLS handshake that was previously paid on every one of the 4-6 HTTP
  requests a Trino query makes. Off by default; when off, behavior is
  identical to 0.1.0. `disconnect!` shuts down the keep-alive pool and
  `reconnect!` rebuilds it.
- `gzip: true` passthrough to trino-client to compress HTTP response bodies.
- Schema reflection is now shared across a connection pool instead of being
  cached per connection. The adapter no longer overrides `schema_cache`, so it
  falls back to Rails' pool-level `schema_reflection`.
- Opt-in bulk column reflection via a new `bulk_column_reflection: true` key in
  `database.yml`. When enabled, schema reflection runs a single
  `information_schema.columns` query for the whole catalog/schema.
- Opt-in static schema declarations. `ActiveRecord::Trino.define_columns(table,
  defs)` registers a table's columns so the adapter serves them instead of
  querying `information_schema`. With `static_schema: true` in `database.yml`,
  `#data_sources` is served from the declared tables too, skipping `SHOW TABLES`.
  Lets consumers that own their warehouse schema bypass reflection entirely.

## [0.1.0] - 2026-05-21

- Initial release: read-only ActiveRecord adapter for Trino, extracted from
  the power-tools `stagecoach` gem.
