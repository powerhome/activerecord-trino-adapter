# Changelog

## [0.2.0] - 2026-06-12

### Added

- Opt-in persistent HTTP connections via a new `persistent: true` key in
  `database.yml`. The adapter memoizes one keep-alive Faraday connection per
  adapter instance (built on `faraday-net_http_persistent`), eliminating the
  TCP + TLS handshake that was previously paid on every one of the 4-6 HTTP
  requests a Trino query makes. Off by default; when off, behavior is
  identical to 0.1.0. `disconnect!` shuts down the keep-alive pool and
  `reconnect!` rebuilds it.
- `gzip: true` passthrough to trino-client to compress HTTP response bodies.

### Changed

- New runtime dependency on `faraday-net_http_persistent` (>= 2.0).

## [0.1.0] - 2026-05-21

- Initial release: read-only ActiveRecord adapter for Trino, extracted from
  the power-tools `stagecoach` gem.
