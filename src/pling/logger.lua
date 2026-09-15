--- Logger class with debug, warn, error, and info levels
-- Supports rendering date and custom tags
-- @module pling.logger
local Logger = {}

---Formats a message with timestamp and tag
---@tparam string level Log level (DEBUG, INFO, WARN, ERROR)
---@tparam string tag Tag to identify the logger source
---@tparam string message The message to log
---@treturn string Formatted log message
local function format_message(level, tag, message)
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  return string.format("[%s] [%s] [%s] %s", timestamp, level, tag, message)
end

---Creates a new logger instance
---@tparam string tag Optional tag to identify the logger source
---@treturn table Logger instance with log level functions
function Logger.new(tag)
  tag = tag or "Logger"

  local instance = {}

  ---Logs a debug level message
  ---@tparam string message The message to log
  function instance.debug(message)
    local formatted = format_message("DEBUG", tag, message)
    print(formatted)
  end

  ---Logs an info level message
  ---@tparam string message The message to log
  function instance.info(message)
    local formatted = format_message("INFO", tag, message)
    print(formatted)
  end

  ---Logs a warn level message
  ---@tparam string message The message to log
  function instance.warn(message)
    local formatted = format_message("WARN", tag, message)
    print(formatted)
  end

  ---Logs an error level message
  ---@tparam string message The message to log
  function instance.error(message)
    local formatted = format_message("ERROR", tag, message)
    print(formatted)
  end

  return instance
end

return Logger
