--- Generic HTTP transport for webhook-style notifiers.
-- "POST a JSON payload to a URL" transport, shared by every webhook-style
-- notifier (Slack/Discord/custom webhook).
-- @module pling.notifiers.webhook_transport

local http = require("socket.http")
local https_ok, https = pcall(require, "ssl.https")
local ltn12 = require("ltn12")
local cjson_safe = require("cjson.safe")
local Logger = require("pling.logger")

local M = {}

--- Creates a new webhook transport.
-- @tparam table opts optional config: `timeout` in seconds (default 10)
-- @treturn table webhook_transport instance
function M.new(opts)
  opts = opts or {}
  local instance = {
    logger = Logger.new("webhook_transport"),
    timeout = opts.timeout or 10,
  }

  return setmetatable(instance, { __index = M })
end

--- POSTs (or sends via another method) a JSON-encoded payload to a URL.
-- @tparam string url destination URL; `https://` routes through LuaSec,
-- `http://` through plain socket.http
-- @tparam table payload JSON-encodable payload table
-- @tparam table headers optional extra request headers, merged over the
-- default `Content-Type`/`Content-Length`
-- @tparam string method optional HTTP method, defaults to `"POST"`
-- @treturn boolean ok
-- @treturn string err present when `ok` is false
function M:send(url, payload, headers, method)
  if not url or url == "" then
    return false, "url was not provided"
  end
  method = method or "POST"

  local transport = http
  if url:match("^https://") then
    if not https_ok then
      self.logger.error(string.format("webhook request to %s failed: ssl.https (LuaSec) is not installed", url))
      return false, "https URL requested but ssl.https (LuaSec) is not installed"
    end
    transport = https
  end

  local body, encode_err = cjson_safe.encode(payload)
  if not body then
    return false, "failed to encode payload: " .. tostring(encode_err)
  end

  local resp_body = {}
  local req_headers = {
    ["Content-Type"] = "application/json",
    ["Content-Length"] = tostring(#body),
  }
  for k, v in pairs(headers or {}) do
    req_headers[k] = v
  end

  local ok, res, code, _resp_headers, status = pcall(function()
    return transport.request({
      url = url,
      method = method,
      source = ltn12.source.string(body),
      sink = ltn12.sink.table(resp_body),
      headers = req_headers,
      timeout = self.timeout,
    })
  end)

  if not ok then
    self.logger.error(string.format("webhook request to %s raised an error: %s", url, tostring(res)))
    return false, tostring(res)
  end

  if not res then
    self.logger.error(string.format("webhook request to %s failed: %s", url, tostring(code)))
    return false, tostring(code)
  end

  local code_as_number = tonumber(code)
  if not code_as_number or code_as_number < 200 or code_as_number >= 300 then
    self.logger.error(
      string.format("webhook request to %s returned status %s: %s", url, tostring(code), table.concat(resp_body))
    )
    return false, "http status " .. tostring(code) .. " " .. tostring(status)
  end

  self.logger.info(
    string.format("webhook request to %s succeeded: status=%s body=%s", url, tostring(code), table.concat(resp_body))
  )
  return true
end

return M
