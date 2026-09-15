# pling

A standalone Lua library for sending notifications through pluggable
channels: audio, GPIO, MQTT, Slack, Discord, a generic webhook, and email
(SMTP).

Every channel follows the same duck-typed convention — no shared base
class/interface, just:

```lua
local instance = M.new(...)
local ok, err = instance:send(destination, notification)
```

A **notification** is an opaque, caller-defined Lua table. This library
never assumes any particular fields (no `priority`, `source`, `pattern`,
`id`, ...) — that vocabulary belongs to the application using this library,
not to `pling` itself.

There is **no router**. `pling` ships only the channel notifiers, each
usable standalone; routing/rule-based fan-out to multiple destinations is
left entirely to the calling application.

## Installation

```
luarocks install pling-0.1.0-1.rockspec
```

## Usage

```lua
local pling = require("pling")

-- Webhook-style channels (slack, discord, webhook) are composed with a
-- shared HTTP transport:
local transport = pling.webhook_transport.new({ timeout = 10 })
local slack = pling.slack.new(transport)

local ok, err = slack:send(
  { url = "https://hooks.slack.com/services/..." },
  { source = "sensor-1", value = 42 }
)
```

Each notifier's constructor and destination-config shape:

| Channel    | `M.new(...)`             | `destination` / `target_cfg` fields                                             |
| ---------- | ------------------------- | -------------------------------------------------------------------------------- |
| `audio`    | `M.new()`                 | `file` (path to a sound file)                                                    |
| `gpio`     | `M.new()`                 | `pin`, `active_low` (bool), `duration_ms` (default 500)                          |
| `mqtt`     | `M.new()`                 | `address`, `topic`, `qos`, `retain`, `client_id`, `template`                     |
| `slack`    | `M.new(transport)`        | `url`, `headers`, `template`                                                     |
| `discord`  | `M.new(transport)`        | `url`, `headers`, `template`                                                     |
| `webhook`  | `M.new(transport)`        | `url`, `headers`, `template`                                                     |
| `email`    | `M.new(smtp_cfg)`         | `to`, `subject_prefix`, `template`; `smtp_cfg`: `host`, `port`, `from`, `user`, `password`, `ssl`, `subject_prefix` |

### The `template` hook

`mqtt`, `slack`, `discord`, `webhook`, and `email` all accept an optional
`template` function on the destination/target config, giving the caller
full control over the outgoing payload:

- `mqtt` / `slack` / `discord` / `webhook`: `template(notification) ->
  payload_table`
- `email`: `template(notification) -> { subject = ..., body = ... }`

When no `template` is given, each channel falls back to a schema-agnostic
default that JSON-encodes the whole notification table:

- `mqtt`: publishes the notification (or `template` result) as-is
- `slack`: `{ text = json_encode(notification) }`
- `discord`: `{ embeds = { { description = json_encode(notification) } } }`
- `webhook`: `{ event = "notification", notification = notification }`
- `email`: subject `smtp_cfg.subject_prefix or target_cfg.subject_prefix or
  "Notification"`, body `json_encode(notification)`

`audio` and `gpio` ignore the notification entirely — they only act on
their own destination config (a file to play / a pin to pulse).

## Development

All development and testing happens through Docker — no `lua`/`luarocks`/
`busted` toolchain is expected on the host.

```
docker compose up -d
docker compose exec dev luarocks make pling-0.1.0-1.rockspec
docker compose exec dev busted spec
docker compose exec dev stylua src spec
docker compose exec dev ldoc .
docker compose down
```

## License

MIT — see [LICENSE](./LICENSE).
