--- MQTT channel notifier.
-- Publishes a notification to an MQTT topic for a `mqtt` destination. Uses
-- luamqtt in its documented one-shot synchronous idiom: open a fresh
-- client, publish on connect, disconnect, then block on mqtt.run_sync()
-- until that disconnect completes - no persistent/reused connection, same
-- one-shot-per-send shape as webhook_transport.lua.
--
-- Self-contained per destination (broker `address`, `topic`, `qos`,
-- `retain`, `client_id` all live on the destination itself).
-- @module pling.notifiers.mqtt

local mqtt = require("mqtt")
local cjson_safe = require("cjson.safe")
local Logger = require("pling.logger")

local M = {}

--- Creates a new MQTT notifier.
-- @treturn table MQTT notifier instance
function M.new()
  return setmetatable({ logger = Logger.new("mqtt_notifier") }, { __index = M })
end

--- Publishes a notification to the destination's MQTT topic.
-- @tparam table destination destination config: `address` (required broker
-- URI), `topic` (required), `qos` (optional, defaults to 0), `retain`
-- (optional boolean), `client_id` (optional),
-- `template` (optional function(notification) -> payload)
-- @tparam table notification opaque, caller-defined notification table
-- @treturn boolean ok
-- @treturn string err present when `ok` is false
function M:send(destination, notification)
  notification = notification or {}
  if not destination or not destination.address then
    return false, "destination has no address configured"
  end
  if not destination.topic then
    return false, "destination has no topic configured"
  end

  local payload = destination.template and destination.template(notification) or notification
  local body, encode_err = cjson_safe.encode(payload)
  if not body then
    return false, "failed to encode payload: " .. tostring(encode_err)
  end

  local result_ok, result_err = false, "did not connect"

  local client = mqtt.client({
    uri = destination.address,
    clean = true,
    id = destination.client_id,
  })

  client:on({
    connect = function(connack)
      if connack.rc ~= 0 then
        result_ok, result_err = false, tostring(connack:reason_string())
        client:disconnect()
        return
      end

      local publish_ok, publish_err = client:publish({
        topic = destination.topic,
        payload = body,
        qos = destination.qos or 0,
        retain = destination.retain or false,
      })

      result_ok, result_err = publish_ok and true or false, publish_err
      client:disconnect()
    end,
    error = function(err)
      result_ok, result_err = false, tostring(err)
    end,
  })

  -- mqtt.run_sync returns nothing (nil) when its loop exits cleanly (our
  -- own client:disconnect() above unset cl.connection) - it only ever
  -- returns `false, err` explicitly, for a lower-level failure (e.g. the
  -- connect attempt itself, or a socket error mid-iteration). So `false`
  -- specifically - not plain falsiness - is what actually signals that.
  local run_ok, run_err = mqtt.run_sync(client)
  if run_ok == false then
    self.logger.error(
      string.format("mqtt publish to %s (%s) failed: %s", destination.address, destination.topic, tostring(run_err))
    )
    return false, run_err
  end

  if not result_ok then
    self.logger.error(
      string.format("mqtt publish to %s (%s) failed: %s", destination.address, destination.topic, tostring(result_err))
    )
  end

  return result_ok, result_err
end

return M
