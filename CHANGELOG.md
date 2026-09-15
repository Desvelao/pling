# Changelog

All notable changes to this project are documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] - 2026-09-15

### Added
- Initial release: channel notifiers for audio, GPIO, MQTT, Slack, Discord, a generic webhook, and email (SMTP, plain + implicit TLS), each following a shared `M.new(...)` / `instance:send(destination, notification) -> ok, err` convention.
- `template` hook on `mqtt`/`slack`/`discord`/`webhook`/`email` destinations for full control over the outgoing payload, with a schema-agnostic JSON-encoded default when no template is given.
- Docker-based dev/test environment (Alpine + Lua 5.1 + LuaRocks, busted test suite, stylua formatter).
- GitHub Actions CI: `test.yml` (busted tests + a `stylua --check` formatting gate) and `publish.yml` (LDoc → GitHub Pages, LuaRocks upload on tag push).
- LDoc documentation for every public module (`pling`, `pling.logger`, and all 8 `pling.notifiers.*`), covering constructors, `send` parameters/returns, and destination-config field shapes.
