local function make_fake_mqtt(overrides)
  overrides = overrides or {}
  local fake_mqtt = { published = {}, disconnected = false }

  function fake_mqtt.client(opts)
    local instance = { _opts = opts }

    function instance:on(handlers)
      self._handlers = handlers
    end

    function instance:publish(args)
      table.insert(fake_mqtt.published, args)
      if overrides.publish then
        return overrides.publish(args)
      end
      return true
    end

    function instance:disconnect()
      fake_mqtt.disconnected = true
    end

    return instance
  end

  function fake_mqtt.run_sync(cl)
    if overrides.run_sync then
      return overrides.run_sync(cl)
    end
    -- simulate a successful connect; the real mqtt.run_sync returns
    -- nothing (nil) when its loop exits cleanly after our own
    -- disconnect() - only `false, err` is an explicit failure - so this
    -- stub matches that instead of returning `true`.
    cl._handlers.connect({ rc = 0 })
    return nil
  end

  return fake_mqtt
end

describe("pling.notifiers.mqtt", function()
  local mqtt_notifier

  local function load_with_mqtt(fake_mqtt)
    package.loaded["mqtt"] = fake_mqtt
    package.loaded["pling.notifiers.mqtt"] = nil
    mqtt_notifier = require("pling.notifiers.mqtt")
  end

  after_each(function()
    package.loaded["mqtt"] = nil
  end)

  it("fails when the destination has no address", function()
    load_with_mqtt(make_fake_mqtt())
    local n = mqtt_notifier.new()
    local ok, err = n:send({ topic = "x" }, {})
    assert.is_false(ok)
    assert.is_not_nil(err)
  end)

  it("fails when the destination has no topic", function()
    load_with_mqtt(make_fake_mqtt())
    local n = mqtt_notifier.new()
    local ok, err = n:send({ address = "tcp://broker:1883" }, {})
    assert.is_false(ok)
    assert.is_not_nil(err)
  end)

  it("publishes the notification as JSON to the destination's topic and disconnects", function()
    local fake_mqtt = make_fake_mqtt()
    load_with_mqtt(fake_mqtt)
    local n = mqtt_notifier.new()

    local ok = n:send({
      address = "tcp://broker:1883",
      topic = "notifications/out",
      qos = 1,
      retain = true,
    }, { id = 1, source = "sensor-1" })

    assert.is_true(ok)
    assert.are.equal(1, #fake_mqtt.published)
    assert.are.equal("notifications/out", fake_mqtt.published[1].topic)
    assert.are.equal(1, fake_mqtt.published[1].qos)
    assert.is_true(fake_mqtt.published[1].retain)
    assert.is_not_nil(fake_mqtt.published[1].payload:find("sensor-1", 1, true))
    assert.is_true(fake_mqtt.disconnected)
  end)

  it("uses the destination's template function when configured", function()
    local fake_mqtt = make_fake_mqtt()
    load_with_mqtt(fake_mqtt)
    local n = mqtt_notifier.new()

    n:send({
      address = "tcp://broker:1883",
      topic = "notifications/out",
      template = function(notification)
        return { custom = true, source = notification.source }
      end,
    }, { source = "sensor-1" })

    assert.is_not_nil(fake_mqtt.published[1].payload:find('"custom":true', 1, true))
  end)

  it("fails when the broker rejects the connection", function()
    local fake_mqtt = make_fake_mqtt()
    fake_mqtt.run_sync = function(cl)
      cl._handlers.connect({
        rc = 5,
        reason_string = function()
          return "not authorized"
        end,
      })
      return nil
    end
    load_with_mqtt(fake_mqtt)
    local n = mqtt_notifier.new()

    local ok, err = n:send({ address = "tcp://broker:1883", topic = "x" }, {})

    assert.is_false(ok)
    assert.is_not_nil(err)
    assert.are.equal(0, #fake_mqtt.published)
  end)

  it("fails when the client reports an error", function()
    local fake_mqtt = make_fake_mqtt()
    fake_mqtt.run_sync = function(cl)
      cl._handlers.error("connection refused")
      return nil
    end
    load_with_mqtt(fake_mqtt)
    local n = mqtt_notifier.new()

    local ok, err = n:send({ address = "tcp://broker:1883", topic = "x" }, {})

    assert.is_false(ok)
    assert.is_not_nil(err)
  end)

  it("fails when run_sync itself fails", function()
    local fake_mqtt = make_fake_mqtt({
      run_sync = function()
        return false, "network unreachable"
      end,
    })
    load_with_mqtt(fake_mqtt)
    local n = mqtt_notifier.new()

    local ok, err = n:send({ address = "tcp://broker:1883", topic = "x" }, {})

    assert.is_false(ok)
    assert.are.equal("network unreachable", err)
  end)

  it("fails when the publish call itself fails", function()
    local fake_mqtt = make_fake_mqtt({
      publish = function()
        return false, "not connected"
      end,
    })
    load_with_mqtt(fake_mqtt)
    local n = mqtt_notifier.new()

    local ok, err = n:send({ address = "tcp://broker:1883", topic = "x" }, {})

    assert.is_false(ok)
    assert.are.equal("not connected", err)
  end)
end)
