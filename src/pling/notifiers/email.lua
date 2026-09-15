--- Email channel notifier.
-- Sends notifications by email over SMTP, using LuaSocket's bundled
-- socket.smtp module.
--
-- Supports plain SMTP and implicit TLS (`smtp_cfg.ssl = true`, typically
-- port 465, via LuaSec). STARTTLS (`smtp_cfg.starttls = true`, typically
-- port 587) is deliberately NOT implemented: it requires speaking plain
-- SMTP up through the STARTTLS command/response and then upgrading the
-- same connection to TLS mid-stream, which socket.smtp's transport layer
-- has no hook for - a correct implementation needs its own hand-rolled SMTP
-- conversation, not a `create` factory. Rather than ship an untested
-- half-implementation, `:send` fails fast with a clear error; use implicit
-- TLS or a plain relay for now.
-- @module pling.notifiers.email

local smtp = require("socket.smtp")
local socket = require("socket")
local cjson_safe = require("cjson.safe")
local Logger = require("pling.logger")

local M = {}

local function tls_wrapped_socket(ssl)
  local sock = socket.tcp()
  local wrapped = {}

  function wrapped:connect(host, port)
    local ok, err = sock:connect(host, port)
    if not ok then
      return nil, err
    end
    local tls, tls_err = ssl.wrap(sock, { mode = "client", protocol = "any", verify = "none", options = "all" })
    if not tls then
      return nil, tls_err
    end
    local hs_ok, hs_err = tls:dohandshake()
    if not hs_ok then
      return nil, hs_err
    end
    sock = tls
    return 1
  end

  function wrapped:send(...)
    return sock:send(...)
  end
  function wrapped:receive(...)
    return sock:receive(...)
  end
  function wrapped:close(...)
    return sock:close(...)
  end
  function wrapped:settimeout(...)
    return sock:settimeout(...)
  end

  return wrapped
end

-- RFC 5321's MAIL FROM/RCPT TO commands require the address wrapped in
-- angle brackets (e.g. "<user@example.com>") - socket.smtp does not add
-- these itself (metat.__index:mail/:rcpt send exactly "FROM:"/"TO:" ..
-- whatever string it's given), so every caller must. A bare address (no
-- brackets) is silently accepted by some relays but rejected by strict
-- ones - confirmed against real Gmail, which responds with a misleading
-- "555 5.5.2 Syntax error, cannot decode response" rather than a
-- MAIL-FROM-specific error. Idempotent: an already-bracketed address is
-- left alone.
local function angle_wrap(address)
  if address:sub(1, 1) == "<" then
    return address
  end
  return "<" .. address .. ">"
end

--- Creates a new email notifier.
-- @tparam table smtp_cfg SMTP config: `host` (required), `port` (optional,
-- defaults to 25), `from` (required), `user`, `password` (optional
-- credentials), `ssl` (optional boolean, implicit TLS), `subject_prefix`
-- (optional default subject), `create` (optional socket factory override)
-- @treturn table email notifier instance
function M.new(smtp_cfg)
  local instance = {
    logger = Logger.new("email_notifier"),
    smtp_cfg = smtp_cfg or {},
  }

  return setmetatable(instance, { __index = M })
end

--- Sends a notification by email.
-- @tparam table target_cfg destination config: `to` (required list of
-- recipient addresses), `subject_prefix` (optional),
-- `template` (optional function(notification) -> { subject, body })
-- @tparam table notification opaque, caller-defined notification table
-- @treturn boolean ok
-- @treturn string err present when `ok` is false
function M:send(target_cfg, notification)
  notification = notification or {}
  if not target_cfg or not target_cfg.to or #target_cfg.to == 0 then
    return false, "target has no recipients configured"
  end
  if not self.smtp_cfg.host then
    return false, "smtp host is not configured"
  end
  if not self.smtp_cfg.from then
    return false, "smtp from address is not configured"
  end
  if self.smtp_cfg.starttls then
    self.logger.error(
      "STARTTLS is not supported yet - use implicit TLS (ssl=true, typically port 465) or a plain relay"
    )
    return false, "starttls is not supported yet"
  end

  local subject, body
  if type(target_cfg.template) == "function" then
    local template_result = target_cfg.template(notification) or {}
    subject = template_result.subject
    body = template_result.body
  end
  subject = subject or self.smtp_cfg.subject_prefix or target_cfg.subject_prefix or "Notification"
  body = body or cjson_safe.encode(notification)

  -- smtp_cfg.create, when given, replaces the default LuaSocket/LuaSec
  -- tls_wrapped_socket construction below with a caller-supplied socket
  -- factory - the same DI convention this project's webhook/discord
  -- notifiers already expose via an injectable `transport`. Needed by
  -- callers that can't use real blocking LuaSocket sockets (e.g. inside an
  -- OpenResty/ngx_lua worker process) but still want to drive this
  -- module's SMTP protocol handling (socket.smtp/socket.tp) over their own
  -- cosocket-based connection.
  local create = self.smtp_cfg.create
  if not create and self.smtp_cfg.ssl then
    local ok, ssl = pcall(require, "ssl")
    if not ok then
      return false, "luasec (ssl) is required for smtp.ssl = true"
    end
    create = function()
      return tls_wrapped_socket(ssl)
    end
  end

  local wrapped_rcpt = {}
  for i, address in ipairs(target_cfg.to) do
    wrapped_rcpt[i] = angle_wrap(address)
  end

  local ok, err = smtp.send({
    from = angle_wrap(self.smtp_cfg.from),
    rcpt = wrapped_rcpt,
    source = smtp.message({
      headers = { to = table.concat(target_cfg.to, ", "), subject = subject },
      body = body,
    }),
    server = self.smtp_cfg.host,
    port = self.smtp_cfg.port or 25,
    user = self.smtp_cfg.user,
    password = self.smtp_cfg.password,
    create = create,
  })

  if not ok then
    self.logger.error(string.format("email send to %s failed: %s", table.concat(target_cfg.to, ", "), tostring(err)))
    return false, err
  end

  return true
end

return M
