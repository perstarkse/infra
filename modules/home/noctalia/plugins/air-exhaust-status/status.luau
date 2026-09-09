--!nonstrict
-- air-exhaust fan status: streams air-exhaust/fan/status over MQTT and shows
-- "<duty>% · <room>°C". Read-only display, no click actions by design.

local duty = nil
local room = nil
local stale = false
local mode = nil
local up = nil
local lastSeen = 0
local streamStarted = false
local lastAttempt = 0
local loadedAt = os.time()

local OFFLINE_AFTER_SECS = 30
-- A stream that dies before the first message (bad creds at load, broker
-- mid-restart) never recovers on its own: respawn while nothing was ever
-- received, paced, inside a startup window. Past the window we leave a live
-- (possibly silent) stream alone — respawning then could stack duplicates.
local RETRY_PACE_SECS = 60
local RETRY_WINDOW_SECS = 15 * 60

local function cfg(key, fallback)
  local value = barWidget.getConfig(key)
  if value == nil or value == "" then
    return fallback
  end
  return value
end

local function credPath()
  return noctalia.expandPath(cfg("cred_file", "~/.config/air-exhaust/mqtt.env"))
end

local function readPassword()
  local raw = noctalia.readFile(credPath())
  if not raw then
    return nil
  end
  -- File format (written by the air-exhaust-mqtt secret generator):
  -- username=charon-ro\npassword=<base64 without /+=>
  local pass = string.match(raw, "password=([^\r\n]+)")
  if pass then
    pass = noctalia.string.trim(pass)
  end
  if pass == nil or pass == "" then
    return nil
  end
  return pass
end

local function render()
  barWidget.setGlyph("fan")
  if lastSeen == 0 or os.time() - lastSeen > OFFLINE_AFTER_SECS then
    barWidget.setText("--")
    barWidget.setTooltip("air-exhaust: offline (no status for >30 s)")
    barWidget.setGlyphColor("error")
    barWidget.setColor("error")
    return
  end
  barWidget.setText(string.format("%d%% · %.1f°C", duty, room))
  local tip = string.format("air-exhaust fan\nmode: %s\nuptime: %ds", mode, up)
  if stale then
    tip = tip .. "\nroom temp STALE (>10 min)"
  end
  barWidget.setTooltip(tip)
  if stale then
    barWidget.setGlyphColor("tertiary")
    barWidget.setColor("tertiary")
  else
    barWidget.setGlyphColor("primary")
    barWidget.setColor("primary")
  end
end

local function onStatusLine(line)
  local trimmed = noctalia.string.trim(line or "")
  if trimmed == "" then
    return
  end
  local parsed = noctalia.json.decode(trimmed)
  if not parsed or type(parsed.duty) ~= "number" or type(parsed.room) ~= "number" then
    return
  end
  duty = parsed.duty
  room = parsed.room
  stale = parsed.stale == true
  mode = parsed.mode or "?"
  up = parsed.up or 0
  lastSeen = os.time()
  render()
end

local function startStream()
  if streamStarted then
    return
  end
  lastAttempt = os.time()
  local sub = cfg("mosquitto_sub_cmd", "mosquitto_sub")
  if string.find(sub, "/", 1, true) then
    if not noctalia.fileExists(sub) then
      noctalia.log("air-exhaust-status: mosquitto_sub not found at " .. sub)
      return
    end
  elseif not noctalia.commandExists(sub) then
    noctalia.log("air-exhaust-status: mosquitto_sub not on PATH")
    return
  end
  local pass = readPassword()
  if not pass then
    noctalia.log("air-exhaust-status: no MQTT password at " .. credPath())
    return
  end
  -- mosquitto_sub has no password-file flag, so the password travels on the
  -- command line. The generator charset is base64 minus /+=, so there is no
  -- shell-quoting hazard; single quotes as belt and braces.
  local cmd = string.format(
    "%s -h %s -p %s -u %s -P '%s' -t %s",
    sub,
    cfg("mqtt_host", "10.0.0.1"),
    cfg("mqtt_port", "1883"),
    cfg("mqtt_username", "charon-ro"),
    pass,
    cfg("mqtt_topic", "air-exhaust/fan/status")
  )
  streamStarted = noctalia.runStream(cmd, onStatusLine)
end

function update()
  noctalia.setUpdateInterval(5000)
  if lastSeen == 0 and os.time() - lastAttempt >= RETRY_PACE_SECS
      and os.time() - loadedAt < RETRY_WINDOW_SECS then
    streamStarted = false
    startStream()
  elseif not streamStarted then
    startStream()
  end
  render()
end
