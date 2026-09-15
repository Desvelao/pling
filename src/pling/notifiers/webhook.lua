--- Generic webhook channel notifier.
-- Composes a WebhookTransport (does not subclass it) to post to an
-- arbitrary third-party webhook. The payload shape is caller-defined per
-- target: `target_cfg.template` is a plain Lua function receiving the
-- notification and returning the JSON-able payload table to send. Falls
-- back to a fixed generic envelope when no template is configured.
-- @module pling.notifiers.webhook

local M = {}

--- Creates a new generic webhook notifier.
-- @tparam table transport a webhook_transport instance (see
-- @{pling.notifiers.webhook_transport})
-- @treturn table webhook notifier instance
function M.new(transport)
  local instance = { transport = transport }
  return setmetatable(instance, { __index = M })
end

--- Sends a notification to an arbitrary webhook URL.
-- @tparam table target_cfg destination config: `url` (required),
-- `headers` (optional), `method` (optional, defaults to POST),
-- `template` (optional function(notification) -> payload)
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
    payload = { event = "notification", notification = notification }
  end

  return self.transport:send(target_cfg.url, payload, target_cfg.headers, target_cfg.method)
end

return M
