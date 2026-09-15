-- Manual test script: sends one notification to Discord, Slack, and Email
-- through pling. Fill in the variables below with real credentials, then
-- run inside the dev container:
--
--   docker compose exec dev lua examples/test_channels.lua
--
-- A channel is skipped (not an error) if its required variable is left
-- empty, so you can test one channel at a time.

-- Requires pling directly from source, no `luarocks make` step needed —
-- adds the repo's src/ directory to Lua's module search path. Assumes the
-- script is run from /app (the dev container's WORKDIR), per the
-- `docker compose exec dev lua examples/test_channels.lua` command above.
package.path = "./src/?.lua;./src/?/init.lua;" .. package.path

local pling = require("pling")

-- Discord: an incoming webhook URL for the target channel.
-- https://support.discord.com/hc/en-us/articles/228383668
local DISCORD_WEBHOOK_URL = ""

-- Slack: an incoming webhook URL for the target channel.
-- https://api.slack.com/messaging/webhooks
local SLACK_WEBHOOK_URL = ""

-- Email: SMTP server + recipient(s).
local SMTP_HOST = ""
local SMTP_PORT = 587 -- 465 for implicit TLS (set SMTP_SSL = true below)
local SMTP_FROM = ""
local SMTP_USER = nil -- leave nil if the relay doesn't require auth
local SMTP_PASSWORD = nil
local SMTP_SSL = false -- true for implicit TLS on port 465; STARTTLS (587) is not supported
local EMAIL_TO = { "" }

-- The notification sent to every channel. Opaque, caller-defined table;
-- with no `template` configured below, each channel falls back to
-- JSON-encoding this whole table (see README's "template hook" section).
local NOTIFICATION = {
  source = "pling-test-script",
  message = "Hello from pling!",
  timestamp = os.date("%Y-%m-%d %H:%M:%S"),
}

local transport = pling.webhook_transport.new({ timeout = 10 })

local function report(channel, ok, err)
  if ok then
    print(string.format("[%s] OK", channel))
  else
    print(string.format("[%s] FAILED: %s", channel, tostring(err)))
  end
end

if DISCORD_WEBHOOK_URL ~= "" then
  local discord = pling.discord.new(transport)
  local ok, err = discord:send({ url = DISCORD_WEBHOOK_URL }, NOTIFICATION)
  report("discord", ok, err)
else
  print("[discord] skipped: DISCORD_WEBHOOK_URL is empty")
end

if SLACK_WEBHOOK_URL ~= "" then
  local slack = pling.slack.new(transport)
  local ok, err = slack:send({ url = SLACK_WEBHOOK_URL }, NOTIFICATION)
  report("slack", ok, err)
else
  print("[slack] skipped: SLACK_WEBHOOK_URL is empty")
end

if SMTP_HOST ~= "" then
  local email = pling.email.new({
    host = SMTP_HOST,
    port = SMTP_PORT,
    from = SMTP_FROM,
    user = SMTP_USER,
    password = SMTP_PASSWORD,
    ssl = SMTP_SSL,
  })
  local ok, err = email:send({ to = EMAIL_TO }, NOTIFICATION)
  report("email", ok, err)
else
  print("[email] skipped: SMTP_HOST is empty")
end
