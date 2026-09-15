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

describe("pling.notifiers.discord", function()
  local discord

  before_each(function()
    package.loaded["pling.notifiers.discord"] = nil
    discord = require("pling.notifiers.discord")
  end)

  it("fails when the target has no url", function()
    local transport = make_fake_transport()
    local n = discord.new(transport)
    local ok = n:send({}, { source = "s" })
    assert.is_false(ok)
  end)

  it("uses the target's template function to build the payload", function()
    local transport, calls = make_fake_transport()
    local n = discord.new(transport)

    local ok = n:send({
      url = "https://discord.com/api/webhooks/x",
      template = function(notification)
        return { embeds = { { description = notification.source } } }
      end,
    }, { source = "sensor-1" })

    assert.is_true(ok)
    assert.are.equal(1, #calls)
    assert.are.equal("sensor-1", calls[1].payload.embeds[1].description)
  end)

  it("falls back to a JSON-encoded notification in the embed description when no template is configured", function()
    local transport, calls = make_fake_transport()
    local n = discord.new(transport)
    local notification = { source = "sensor-1", value = 42 }

    local ok = n:send({ url = "https://discord.com/api/webhooks/x" }, notification)

    assert.is_true(ok)
    assert.are.equal(cjson_safe.encode(notification), calls[1].payload.embeds[1].description)
  end)
end)
