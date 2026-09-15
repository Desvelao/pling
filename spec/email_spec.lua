local cjson_safe = require("cjson.safe")

describe("pling.notifiers.email", function()
  local email
  local smtp_calls
  local smtp_result

  before_each(function()
    smtp_calls = {}
    smtp_result = { ok = 1 }

    package.loaded["socket.smtp"] = {
      send = function(opts)
        table.insert(smtp_calls, opts)
        if smtp_result.ok then
          return smtp_result.ok
        end
        return nil, smtp_result.err
      end,
      message = function(msg)
        return { __message = msg }
      end,
    }
    package.loaded["socket"] = {
      tcp = function()
        return {}
      end,
    }

    package.loaded["pling.notifiers.email"] = nil
    email = require("pling.notifiers.email")
  end)

  after_each(function()
    package.loaded["socket.smtp"] = nil
    package.loaded["socket"] = nil
    package.loaded["ssl"] = nil
  end)

  it("fails when the target has no recipients", function()
    local n = email.new({ host = "smtp.example.com" })
    local ok, err = n:send({}, { source = "s" })
    assert.is_false(ok)
    assert.is_not_nil(err)
    assert.are.equal(0, #smtp_calls)
  end)

  it("fails when smtp host is not configured", function()
    local n = email.new({})
    local ok, err = n:send({ to = { "a@example.com" } }, {})
    assert.is_false(ok)
    assert.is_not_nil(err)
  end)

  it("fails fast with a clear error when starttls is requested", function()
    local n = email.new({
      host = "smtp.example.com",
      from = "alerts@example.com",
      starttls = true,
    })
    local ok, err = n:send({ to = { "a@example.com" } }, {})
    assert.is_false(ok)
    assert.are.equal("starttls is not supported yet", err)
    assert.are.equal(0, #smtp_calls)
  end)

  it(
    "sends over plain smtp, falling back to a default subject and JSON-encoded body when no template is configured",
    function()
      local n = email.new({
        host = "smtp.example.com",
        port = 25,
        from = "alerts@example.com",
      })
      local notification = { source = "sensor-1", value = 42 }

      local ok = n:send({ to = { "ops@example.com" } }, notification)

      assert.is_true(ok)
      assert.are.equal(1, #smtp_calls)
      assert.are.equal("<alerts@example.com>", smtp_calls[1].from)
      assert.are.same({ "<ops@example.com>" }, smtp_calls[1].rcpt)
      assert.are.equal("smtp.example.com", smtp_calls[1].server)
      assert.are.equal(25, smtp_calls[1].port)
      assert.is_nil(smtp_calls[1].create)
      assert.are.equal("Notification", smtp_calls[1].source.__message.headers.subject)
      assert.are.equal(cjson_safe.encode(notification), smtp_calls[1].source.__message.body)
    end
  )

  it("prefers smtp_cfg.subject_prefix, then target_cfg.subject_prefix, as the default subject", function()
    local n = email.new({
      host = "smtp.example.com",
      from = "alerts@example.com",
      subject_prefix = "[ALERT]",
    })
    n:send({ to = { "ops@example.com" }, subject_prefix = "[TARGET]" }, {})
    assert.are.equal("[ALERT]", smtp_calls[1].source.__message.headers.subject)

    local n2 = email.new({ host = "smtp.example.com", from = "alerts@example.com" })
    n2:send({ to = { "ops@example.com" }, subject_prefix = "[TARGET]" }, {})
    assert.are.equal("[TARGET]", smtp_calls[2].source.__message.headers.subject)
  end)

  it("uses the target's template function when configured", function()
    local n = email.new({ host = "smtp.example.com", from = "alerts@example.com" })

    local ok = n:send({
      to = { "ops@example.com" },
      template = function(notification)
        return {
          subject = "custom: " .. tostring(notification.source),
          body = "body for " .. tostring(notification.source),
        }
      end,
    }, { source = "sensor-1" })

    assert.is_true(ok)
    assert.are.equal("custom: sensor-1", smtp_calls[1].source.__message.headers.subject)
    assert.are.equal("body for sensor-1", smtp_calls[1].source.__message.body)
  end)

  it("passes a create function for implicit TLS", function()
    package.loaded["ssl"] = { wrap = function() end }
    local n = email.new({
      host = "smtp.example.com",
      from = "alerts@example.com",
      port = 465,
      ssl = true,
    })
    local ok = n:send({ to = { "ops@example.com" } }, {})

    assert.is_true(ok)
    assert.are.equal("function", type(smtp_calls[1].create))
  end)

  it("propagates the smtp library's failure result", function()
    smtp_result = { ok = nil, err = "connection refused" }
    local n = email.new({ host = "smtp.example.com", from = "alerts@example.com" })
    local ok, err = n:send({ to = { "ops@example.com" } }, {})
    assert.is_false(ok)
    assert.are.equal("connection refused", err)
  end)
end)
