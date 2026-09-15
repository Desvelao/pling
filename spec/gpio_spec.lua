describe("pling.notifiers.gpio", function()
  local gpio_notifier
  local original_io_open
  local original_execute
  local writes
  local existing_paths
  local fail_write_paths

  before_each(function()
    package.loaded["pling.notifiers.gpio"] = nil
    gpio_notifier = require("pling.notifiers.gpio")

    writes = {}
    existing_paths = {}
    fail_write_paths = {}
    original_io_open = io.open
    original_execute = os.execute

    io.open = function(path, mode)
      if mode == "r" then
        if existing_paths[path] then
          return { close = function() end }
        end
        return nil
      end

      if fail_write_paths[path] then
        return nil
      end

      return {
        write = function(_self, contents)
          table.insert(writes, { path = path, contents = contents })
        end,
        close = function() end,
      }
    end

    os.execute = function()
      return true
    end
  end)

  after_each(function()
    io.open = original_io_open
    os.execute = original_execute
  end)

  local function write_paths()
    local paths = {}
    for _, w in ipairs(writes) do
      table.insert(paths, w.path)
    end
    return paths
  end

  it("fails when the destination has no pin", function()
    local n = gpio_notifier.new()
    local ok, err = n:send({}, {})
    assert.is_false(ok)
    assert.is_not_nil(err)
  end)

  it("exports the pin when not already exported, then sets direction and pulses active/inactive", function()
    local n = gpio_notifier.new()
    local ok = n:send({ pin = 17, duration_ms = 100 }, {})

    assert.is_true(ok)
    assert.are.same({
      "/sys/class/gpio/export",
      "/sys/class/gpio/gpio17/direction",
      "/sys/class/gpio/gpio17/value",
      "/sys/class/gpio/gpio17/value",
    }, write_paths())
    assert.are.equal("17", writes[1].contents)
    assert.are.equal("out", writes[2].contents)
    assert.are.equal("1", writes[3].contents)
    assert.are.equal("0", writes[4].contents)
  end)

  it("skips exporting when the pin is already exported", function()
    existing_paths["/sys/class/gpio/gpio17"] = true
    local n = gpio_notifier.new()

    n:send({ pin = 17 }, {})

    for _, path in ipairs(write_paths()) do
      assert.are_not.equal("/sys/class/gpio/export", path)
    end
  end)

  it("inverts active/inactive values for active_low destinations", function()
    local n = gpio_notifier.new()
    n:send({ pin = 4, active_low = true, duration_ms = 10 }, {})

    assert.are.equal("0", writes[3].contents)
    assert.are.equal("1", writes[4].contents)
  end)

  it("fails when exporting the pin fails", function()
    fail_write_paths["/sys/class/gpio/export"] = true
    local n = gpio_notifier.new()

    local ok, err = n:send({ pin = 17 }, {})

    assert.is_false(ok)
    assert.is_not_nil(err)
  end)

  it("fails when setting direction fails", function()
    fail_write_paths["/sys/class/gpio/gpio17/direction"] = true
    local n = gpio_notifier.new()

    local ok, err = n:send({ pin = 17 }, {})

    assert.is_false(ok)
    assert.is_not_nil(err)
  end)

  it("fails when activating the pin fails", function()
    fail_write_paths["/sys/class/gpio/gpio17/value"] = true
    local n = gpio_notifier.new()

    local ok, err = n:send({ pin = 17 }, {})

    assert.is_false(ok)
    assert.is_not_nil(err)
  end)
end)
