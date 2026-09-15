describe("pling.notifiers.audio", function()
  local audio_notifier
  local original_execute
  local tmp_path

  before_each(function()
    package.loaded["pling.notifiers.audio"] = nil
    audio_notifier = require("pling.notifiers.audio")
    original_execute = os.execute
    tmp_path = os.tmpname() .. ".wav"
    local f = io.open(tmp_path, "w")
    f:write("not really audio")
    f:close()
  end)

  after_each(function()
    os.execute = original_execute
    os.remove(tmp_path)
  end)

  it("fails when the destination has no file configured", function()
    local n = audio_notifier.new()
    local ok, err = n:send({}, {})
    assert.is_false(ok)
    assert.is_not_nil(err)
  end)

  it("fails when the configured file doesn't exist", function()
    local n = audio_notifier.new()
    local ok, err = n:send({ file = "/nonexistent/path.wav" }, {})
    assert.is_false(ok)
    assert.is_not_nil(err)
  end)

  -- `command -v <x>` existence checks are shell_quote'd as `'command'
  -- '-v' '<x>'` (each arg individually quoted) - "'-v' '<x>'" only ever
  -- appears in an existence probe, never in the actual play invocation
  -- (`'<x>' '<file>' ...`), so it's what these stubs key off of.
  local function is_probe(cmd, player)
    return cmd:find("'-v' '" .. player .. "'", 1, true) ~= nil
  end

  it("succeeds when a player command is available and spawns cleanly", function()
    os.execute = function(cmd)
      if is_probe(cmd, "paplay") then
        return true
      end
      if cmd:find("'-v'", 1, true) then
        return false
      end
      -- the actual paplay invocation
      return true
    end

    local n = audio_notifier.new()
    local ok = n:send({ file = tmp_path }, {})
    assert.is_true(ok)
  end)

  it("fails when no player command is available at all", function()
    os.execute = function(cmd)
      if cmd:find("'-v'", 1, true) then
        return false
      end
      return true
    end

    local n = audio_notifier.new()
    local ok, err = n:send({ file = tmp_path }, {})
    assert.is_false(ok)
    assert.is_not_nil(err)
  end)

  it("reports failure when the only available player fails to spawn", function()
    os.execute = function(cmd)
      if is_probe(cmd, "paplay") then
        return true
      end
      if cmd:find("'-v'", 1, true) then
        return false
      end
      -- the actual paplay invocation itself fails
      return false
    end

    local n = audio_notifier.new()
    local ok = n:send({ file = tmp_path }, {})
    assert.is_false(ok)
  end)
end)
