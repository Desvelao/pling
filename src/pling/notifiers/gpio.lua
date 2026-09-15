--- GPIO channel notifier.
-- Pulses a GPIO pin for a `gpio` destination, using the Linux sysfs GPIO
-- interface (/sys/class/gpio).
--
-- `destination.pin` is the BCM GPIO number (as used by /sys/class/gpio's
-- own gpio<N> naming). Pulses `destination.duration_ms` (default 500ms)
-- active, then back to inactive - a one-shot action, not a latch a second
-- dispatch has to turn back off.
-- @module pling.notifiers.gpio

local Logger = require("pling.logger")

local M = {}

--- Creates a new GPIO notifier.
-- @treturn table GPIO notifier instance
function M.new()
  return setmetatable({ logger = Logger.new("gpio_notifier") }, { __index = M })
end

local function write_file(path, contents)
  local f = io.open(path, "w")
  if not f then
    return false
  end
  f:write(contents)
  f:close()
  return true
end

local function file_exists(path)
  local f = io.open(path, "r")
  if f then
    f:close()
    return true
  end
  return false
end

--- Pulses a GPIO pin. The notification argument is ignored.
-- @tparam table destination destination config: `pin` (required, BCM GPIO
-- number), `active_low` (optional boolean), `duration_ms` (optional,
-- defaults to 500)
-- @tparam table _notification ignored by this notifier
-- @treturn boolean ok
-- @treturn string err present when `ok` is false
function M:send(destination, _notification)
  local pin = destination and destination.pin
  if not pin then
    return false, "destination has no pin configured"
  end
  pin = tostring(pin)

  local gpio_path = "/sys/class/gpio/gpio" .. pin

  if not file_exists(gpio_path) then
    if not write_file("/sys/class/gpio/export", pin) then
      return false, "failed to export gpio " .. pin .. " (is /sys/class/gpio available and writable?)"
    end
  end

  if not write_file(gpio_path .. "/direction", "out") then
    return false, "failed to set gpio " .. pin .. " direction to out"
  end

  local active_value = destination.active_low and "0" or "1"
  local inactive_value = destination.active_low and "1" or "0"
  local duration_seconds = (destination.duration_ms or 500) / 1000

  if not write_file(gpio_path .. "/value", active_value) then
    return false, "failed to activate gpio " .. pin
  end

  os.execute(string.format("sleep %s", tostring(duration_seconds)))

  if not write_file(gpio_path .. "/value", inactive_value) then
    self.logger.warn("gpio " .. pin .. " pulsed but failed to reset to inactive")
  end

  return true
end

return M
