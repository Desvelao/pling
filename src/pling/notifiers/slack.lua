--- Slack channel notifier.
-- Composes a WebhookTransport (does not subclass it) to post Slack
-- incoming-webhook messages. The notification is an opaque, caller-defined
-- table: `target_cfg.template(notification)` builds the payload when given;
-- otherwise the whole notification is JSON-encoded into `text`.
-- @module pling.notifiers.slack

local cjson_safe = require("cjson.safe")

local M = {}

--- Creates a new Slack notifier.
-- @tparam table transport a webhook_transport instance (see
-- @{pling.notifiers.webhook_transport})
-- @treturn table Slack notifier instance
function M.new(transport)
  local instance = { transport = transport }
  return setmetatable(instance, { __index = M })
end

--- Sends a notification to a Slack incoming webhook.
-- @tparam table target_cfg destination config: `url` (required),
-- `headers` (optional), `template` (optional function(notification) -> payload)
-- @tparam table notification opaque, caller-defined notification table
-- @treturn boolean ok
-- @treturn string err present when `ok` is false
function M:send(target_cfg, notification)
  notification = notification or {}
  if not target_cfg or not target_cfg.url then
    return false, "target has no url configured"
  end

  local payload
  if type(target_cfg.template) == "function" then
    payload = target_cfg.template(notification)
  else
    payload = { text = cjson_safe.encode(notification) }
  end

  return self.transport:send(target_cfg.url, payload, target_cfg.headers)
end

return M
