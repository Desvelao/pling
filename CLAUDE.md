# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`pling` is a standalone Lua library for sending notifications through pluggable channels: audio, GPIO, MQTT, Slack, Discord, a generic webhook, and email (SMTP). Every channel follows the same duck-typed convention, no shared base class:

```lua
local instance = M.new(...)
local ok, err = instance:send(destination, notification)
```

A **notification** is an opaque, caller-defined Lua table — the library never assumes any particular fields (no `priority`, `source`, `pattern`, etc.). That vocabulary belongs to the application using the library.

There is **no router**. The library ships only the channel notifiers, each usable standalone; routing/rule-based fan-out to multiple destinations is left entirely to the calling application. Do not add routing/orchestration logic here — it doesn't belong in this library.

## Development — everything runs through Docker

No `lua`/`luarocks`/`busted`/`stylua`/`ldoc` toolchain is expected on the host. All commands below are run via `docker compose exec dev ...` after `docker compose up -d`.

```
docker compose up -d
docker compose exec dev luarocks make pling-0.1.0-1.rockspec
docker compose exec dev busted spec
docker compose exec dev stylua src spec
docker compose exec dev ldoc .
docker compose down
```

Notes specific to this setup:
- **`luarocks make`/`install` must run WITHOUT `--local`** — the container runs as root, and `--local` is rejected for the superuser.
- **The rockspec filename is versioned** (`pling-0.1.0-1.rockspec`, currently) and gets renamed on every version bump (`package.version` + filename together). Commands referencing it need the current filename — check what's actually in the repo root before assuming.
- **`luarocks make`-installed rocks don't survive container recreation.** Only the Docker image's own build step (`RUN luarocks install --only-deps ...`, baked into the image layers) persists across `docker compose down`/`up`. Compiled C dependencies (`lua-cjson`, `luasec`, `luasocket`, `luamqtt`, `luabitop`) are always available for this reason; the pure-Lua `pling` package itself is not, until `luarocks make` is run again in a fresh container.
- To run a single spec file: `docker compose exec dev busted spec/slack_spec.lua`.
- `stylua.toml` overrides only `indent_type`/`indent_width` (2-space) to match this codebase's existing style; everything else is StyLua's defaults (notably `column_width = 120`).
- `examples/test_channels.lua` requires `pling` directly from `src/` via a `package.path` override instead of `require`-ing an installed rock, specifically so it works without a prior `luarocks make` — see the comment at the top of that file before "fixing" it to use `require("pling")` directly.

## Architecture

- `src/pling/init.lua` is the public entry point: a flat table of `require`d notifier submodules (`pling.audio`, `pling.slack`, etc.). It has no logic of its own — just re-exports.
- Each notifier under `src/pling/notifiers/` is an independent module (`M.new(...)` / `M:send(destination, notification)`), not sharing code with each other except:
  - `pling.notifiers.webhook_transport` — a generic "POST JSON to a URL" HTTP transport, **composed** (not subclassed) by `slack`, `discord`, and `webhook`. Each of those three calls `self.transport:send(url, payload, headers, ...)` after building its own payload shape.
  - `pling.logger` — a small tagged logger (`debug`/`info`/`warn`/`error`), used internally by notifiers that need to log delivery failures (not part of the notifier public API surface exported from `init.lua`).
- The `template` hook: `mqtt`, `slack`, `discord`, `webhook`, and `email` all accept an optional `template` function on the destination/target config, giving the caller full control over the outgoing payload shape. Without one, each channel falls back to a schema-agnostic default that JSON-encodes the whole notification table (exact shape differs per channel — see each notifier's `M:send` doc comment or the README's table). `audio` and `gpio` ignore the notification entirely; they only act on their own destination config (a file to play / a pin to pulse).
- Every rockspec module path mirrors its file path 1:1 under `src/` (`pling.notifiers.slack` → `src/pling/notifiers/slack.lua`, `pling` → `src/pling/init.lua`). When adding a new notifier, both `pling-0.1.0-1.rockspec`'s `build.modules` table and `src/pling/init.lua`'s re-export table need the new entry.
- Docs are LDoc-generated from doc comments in `src/`. Use LDoc's own tag convention — `@tparam <type> <name> <description>` and `@treturn <type> <description>` (not the EmmyLua `@param name type description` order) — and give the doc'd parameter name exactly matching the actual formal argument name (including a leading `_` for intentionally-unused ones like `_notification`), or `ldoc .` warns.
- No `.git` repository exists in this project yet.
