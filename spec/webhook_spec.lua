local function make_fake_transport(result)
  local calls = {}
  local transport = {
    send = function(_self, url, payload, headers, method)
      table.insert(calls, { url = url, payload = payload, headers = headers, method = method })
      if result then
        return result.ok, result.err
      end
      return true
    end,
  }
  return transport, calls
end

describe("pling.notifiers.webhook", function()
  local webhook

  before_each(function()
    package.loaded["pling.notifiers.webhook"] = nil
    webhook = require("pling.notifiers.webhook")
  end)

  it("fails when the target has no url", function()
    local transport = make_fake_transport()
    local n = webhook.new(transport)
    local ok = n:send({}, {})
    assert.is_false(ok)
  end)

  it("sends a fixed generic envelope when no template is configured", function()
    local transport, calls = make_fake_transport()
    local n = webhook.new(transport)
    local notification = { id = 1, source = "sensor-1" }

    local ok = n:send({ url = "https://example.com/hook" }, notification)

    assert.is_true(ok)
    assert.are.equal("notification", calls[1].payload.event)
    assert.are.same(notification, calls[1].payload.notification)
  end)

  it("passes the target's method through to the transport", function()
    local transport, calls = make_fake_transport()
    local n = webhook.new(transport)

    local ok = n:send({ url = "https://example.com/hook", method = "PUT" }, {})

    assert.is_true(ok)
    assert.are.equal("PUT", calls[1].method)
  end)

  it("uses the target's template function when configured", function()
    local transport, calls = make_fake_transport()
    local n = webhook.new(transport)

    local ok = n:send({
      url = "https://example.com/hook",
      template = function(notification)
        return { custom = true, source = notification.source }
      end,
    }, { source = "sensor-1" })

    assert.is_true(ok)
    assert.are.same({ custom = true, source = "sensor-1" }, calls[1].payload)
  end)
end)
