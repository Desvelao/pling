--- Audio channel notifier.
-- Plays a sound file for an `audio` destination by shelling out to
-- paplay/aplay/ffplay (first available), parameterized by the destination's
-- own `file` field.
-- @module pling.notifiers.audio

local has_ngx_pipe, ngx_pipe = pcall(require, "ngx.pipe")

local M = {}

--- Creates a new audio notifier.
-- @treturn table audio notifier instance
function M.new()
  return setmetatable({}, { __index = M })
end

--- Plays the destination's sound file. The notification argument is
-- ignored.
-- @tparam table destination destination config: `file` (required, path to
-- a sound file)
-- @tparam table _notification ignored by this notifier
-- @treturn boolean ok
-- @treturn string err present when `ok` is false
function M:send(destination, _notification)
  local file = destination and destination.file
  if not file then
    return false, "destination has no file configured"
  end

  local f = io.open(file, "r")
  if not f then
    return false, "file not found: " .. tostring(file)
  end
  f:close()

  -- Quote an argv for use in a shell command (used only by the
  -- os.execute fallback, which has no argv-based exec API)
  local function shell_quote(argv)
    local parts = {}
    for i, arg in ipairs(argv) do
      parts[i] = "'" .. tostring(arg):gsub("'", "'\\''") .. "'"
    end
    return table.concat(parts, " ")
  end

  -- Check if a command exists
  local function command_exists(cmd)
    local ok = os.execute(shell_quote({ "command", "-v", cmd }) .. " >/dev/null 2>&1")
    return ok == 0 or ok == true
  end

  -- Get file extension
  local extension = file:match("%.([^%.]+)$")
  if extension then
    extension = extension:lower()
  end

  local players

  -- Select players based on format
  if extension == "wav" then
    players = {
      { "paplay", file },
      { "aplay", file },
      { "ffplay", "-nodisp", "-autoexit", file },
    }
  elseif
    extension == "mp3"
    or extension == "ogg"
    or extension == "flac"
    or extension == "m4a"
    or extension == "aac"
  then
    players = {
      { "ffplay", "-nodisp", "-autoexit", file },
      { "paplay", file },
      { "aplay", file },
    }
  else
    -- Unknown format: try everything
    players = {
      { "paplay", file },
      { "aplay", file },
      { "ffplay", "-nodisp", "-autoexit", file },
    }
  end

  -- Try available players. Inside OpenResty (embedded worker), spawn via
  -- ngx.pipe: proc:wait() yields the current light thread instead of
  -- blocking the whole nginx worker process (and its HTTP traffic) for
  -- the duration of playback, unlike os.execute. Outside OpenResty
  -- (standalone lua worker, no ngx.pipe available) os.execute is fine
  -- since it only blocks that worker's own poll loop, not an HTTP server.
  for _, argv in ipairs(players) do
    local app = argv[1]

    if command_exists(app) then
      local ok, err_or_reason, status

      if has_ngx_pipe then
        local proc
        proc, err_or_reason = ngx_pipe.spawn(argv, { merge_stderr = true, wait_timeout = 15000 })
        if proc then
          ok, err_or_reason, status = proc:wait()
        end
      else
        local exec_ok = os.execute(shell_quote(argv) .. " >/dev/null 2>&1")
        ok = exec_ok == 0 or exec_ok == true
      end

      if ok then
        return true
      else
        print("Player failed", app, err_or_reason, status)
      end
    else
      print("Command does not exist", app)
    end
  end

  return false, "no available audio player succeeded"
end

return M
