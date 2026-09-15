describe("pling.notifiers.webhook_transport", function()
  local webhook_transport
  local http_calls, https_calls
  local http_response

  local function make_transport_mock(calls)
    return {
      request = function(req)
        table.insert(calls, req)
        if req.sink then
          if http_response.body then
            req.sink(http_response.body)
          end
          req.sink(nil)
        end
        return 1, http_response.code, http_response.headers, http_response.status
      end,
    }
  end

  before_each(function()
    http_calls = {}
    https_calls = {}
    http_response = {
      code = 200,
      headers = {},
      body = "",
      status = "HTTP/1.1 200 OK",
    }

    package.loaded["socket.http"] = make_transport_mock(http_calls)
    package.loaded["ssl.https"] = make_transport_mock(https_calls)

    package.loaded["pling.notifiers.webhook_transport"] = nil
    webhook_transport = require("pling.notifiers.webhook_transport")
  end)

  after_each(function()
    package.loaded["socket.http"] = nil
    package.loaded["ssl.https"] = nil
    package.preload["ssl.https"] = nil
  end)

  it("requires a url", function()
    local t = webhook_transport.new()
    local ok, err = t:send(nil, { text = "hi" })
    assert.is_false(ok)
    assert.are.equal("url was not provided", err)
    assert.are.equal(0, #http_calls)
    assert.are.equal(0, #https_calls)
  end)

  it("POSTs a JSON-encoded payload with merged headers over https", function()
    local t = webhook_transport.new()
    local ok = t:send("https://example.com/hook", { text = "hi" }, { ["X-Extra"] = "1" })

    assert.is_true(ok)
    assert.are.equal(0, #http_calls)
    assert.are.equal(1, #https_calls)
    assert.are.equal("https://example.com/hook", https_calls[1].url)
    assert.are.equal("POST", https_calls[1].method)
    assert.are.equal("application/json", https_calls[1].headers["Content-Type"])
    assert.are.equal("1", https_calls[1].headers["X-Extra"])
  end)

  it("routes a plain http:// URL through socket.http, not ssl.https", function()
    local t = webhook_transport.new()
    local ok = t:send("http://example.com/hook", { text = "hi" })

    assert.is_true(ok)
    assert.are.equal(1, #http_calls)
    assert.are.equal(0, #https_calls)
  end)

  it("uses the given method instead of POST when provided", function()
    local t = webhook_transport.new()
    local ok = t:send("https://example.com/hook", { text = "hi" }, nil, "PUT")

    assert.is_true(ok)
    assert.are.equal("PUT", https_calls[1].method)
  end)

  it("returns false for a non-2xx response", function()
    http_response.code = 500
    local t = webhook_transport.new()
    local ok, err = t:send("https://example.com/hook", { text = "hi" })
    assert.is_false(ok)
    assert.is_not_nil(err)
  end)

  it("returns false when the underlying request raises", function()
    package.loaded["ssl.https"] = {
      request = function()
        error("boom")
      end,
    }
    package.loaded["pling.notifiers.webhook_transport"] = nil
    webhook_transport = require("pling.notifiers.webhook_transport")

    local t = webhook_transport.new()
    local ok, err = t:send("https://example.com/hook", { text = "hi" })
    assert.is_false(ok)
    assert.is_not_nil(err)
  end)

  it("fails fast on an https:// URL when ssl.https is not installed", function()
    package.loaded["ssl.https"] = nil
    package.preload["ssl.https"] = function()
      error("module 'ssl.https' not found")
    end
    package.loaded["pling.notifiers.webhook_transport"] = nil
    webhook_transport = require("pling.notifiers.webhook_transport")

    local t = webhook_transport.new()
    local ok, err = t:send("https://example.com/hook", { text = "hi" })

    assert.is_false(ok)
    assert.are.equal("https URL requested but ssl.https (LuaSec) is not installed", err)
    assert.are.equal(0, #http_calls)
  end)
end)
