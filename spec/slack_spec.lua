local cjson_safe = require("cjson.safe")

local function make_fake_transport(result)
  local calls = {}
  local transport = {
    send = function(_self, url, payload, headers)
      table.insert(calls, { url = url, payload = payload, headers = headers })
      if result then
        return result.ok, result.err
      end
      return true
    end,
  }
  return transport, calls
end

describe("pling.notifiers.slack", function()
  local slack

  before_each(function()
    package.loaded["pling.notifiers.slack"] = nil
    slack = require("pling.notifiers.slack")
  end)

  it("fails when the target has no url", function()
    local transport = make_fake_transport()
    local n = slack.new(transport)
    local ok, err = n:send({}, { source = "s" })
    assert.is_false(ok)
    assert.is_not_nil(err)
  end)

  it("uses the target's template function to build the payload", function()
    local transport, calls = make_fake_transport()
    local n = slack.new(transport)

    local ok = n:send({
      url = "https://hooks.slack.com/x",
      headers = { ["X-Extra"] = "1" },
      template = function(notification)
        return { text = "custom: " .. tostring(notification.source) }
      end,
    }, { source = "sensor-1" })

    assert.is_true(ok)
    assert.are.equal(1, #calls)
    assert.are.equal("https://hooks.slack.com/x", calls[1].url)
    assert.are.equal("1", calls[1].headers["X-Extra"])
    assert.are.equal("custom: sensor-1", calls[1].payload.text)
  end)

  it("falls back to a JSON-encoded notification when no template is configured", function()
    local transport, calls = make_fake_transport()
    local n = slack.new(transport)
    local notification = { source = "sensor-1", value = 42 }

    local ok = n:send({ url = "https://hooks.slack.com/x" }, notification)

    assert.is_true(ok)
    assert.are.equal(cjson_safe.encode(notification), calls[1].payload.text)
  end)

  it("propagates the transport's failure result", function()
    local transport = make_fake_transport({ ok = false, err = "boom" })
    local n = slack.new(transport)
    local ok, err = n:send({ url = "https://hooks.slack.com/x" }, {})
    assert.is_false(ok)
    assert.are.equal("boom", err)
  end)
end)
