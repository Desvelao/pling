--- Standalone Lua library for sending notifications through pluggable
-- channels. Each notifier follows the same duck-typed convention:
-- `local instance = M.new(...)` / `local ok, err = instance:send(destination,
-- notification)`. A notification is an opaque, caller-defined table; this
-- library never assumes any particular fields.
-- @usage
-- local pling = require("pling")
-- local transport = pling.webhook_transport.new({ timeout = 10 })
-- local slack = pling.slack.new(transport)
-- local ok, err = slack:send({ url = "..." }, { source = "sensor-1" })
-- @module pling
return {
  audio = require("pling.notifiers.audio"),
  gpio = require("pling.notifiers.gpio"),
  mqtt = require("pling.notifiers.mqtt"),
  slack = require("pling.notifiers.slack"),
  discord = require("pling.notifiers.discord"),
  webhook = require("pling.notifiers.webhook"),
  webhook_transport = require("pling.notifiers.webhook_transport"),
  email = require("pling.notifiers.email"),
}
