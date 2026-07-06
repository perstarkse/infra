--!nonstrict
-- v5 port of https://github.com/phumberdroz/voxtype-noctalia

local state = "stopped"
local streamStarted = false

local icons = {
  recording = "player-record-filled",
  transcribing = "loader-2",
  idle = "microphone",
  stopped = "microphone-off",
}

local labels = {
  recording = "rec",
  transcribing = "...",
  idle = "vox",
  stopped = "off",
}

local function voxtypeCmd()
  return barWidget.getConfig("voxtype_cmd") or "voxtype"
end

local function systemctlCmd()
  return barWidget.getConfig("systemctl_cmd") or "systemctl"
end

local function commandAvailable(cmd)
  if string.find(cmd, "/", 1, true) then
    return noctalia.fileExists(cmd)
  end
  return noctalia.commandExists(cmd)
end

local function normalizeState(raw)
  local value = noctalia.string.trim(raw or "")
  value = string.lower(value)
  if value == "idle" or value == "recording" or value == "transcribing" or value == "stopped" then
    return value
  end
  if value == "" then
    return "stopped"
  end
  return "idle"
end

local function tooltipFor(current)
  if current == "recording" then
    return "Voxtype: recording\nLeft click: stop\nMiddle click: force stop\nRight click: restart daemon"
  elseif current == "transcribing" then
    return "Voxtype: transcribing\nRight click: restart daemon"
  elseif current == "idle" then
    return "Voxtype: ready\nLeft click: toggle recording\nMiddle click: stop\nRight click: restart daemon"
  end
  return "Voxtype: stopped or unavailable\nLeft click: toggle recording\nRight click: restart daemon"
end

local function render()
  barWidget.setGlyph(icons[state] or icons.stopped)
  barWidget.setText(labels[state] or labels.stopped)
  barWidget.setTooltip(tooltipFor(state))

  if state == "recording" then
    barWidget.setGlyphColor("error")
    barWidget.setColor("error")
  elseif state == "transcribing" then
    barWidget.setGlyphColor("tertiary")
    barWidget.setColor("tertiary")
  elseif state == "idle" then
    barWidget.setGlyphColor("primary")
    barWidget.setColor("primary")
  else
    barWidget.setGlyphColor("on_surface_variant")
    barWidget.setColor("on_surface_variant")
  end
end

local function onStatusLine(line)
  local trimmed = noctalia.string.trim(line or "")
  if trimmed == "" then
    return
  end

  local parsed = noctalia.json.decode(trimmed)
  if parsed then
    state = normalizeState(parsed.class or parsed.alt)
  else
    state = normalizeState(trimmed)
  end
  render()
end

local function startStream()
  if streamStarted then
    return
  end

  local cmd = voxtypeCmd()
  if not commandAvailable(cmd) then
    state = "stopped"
    render()
    return
  end

  streamStarted = noctalia.runStream(cmd .. " status --follow --format json", onStatusLine)
  if not streamStarted then
    state = "stopped"
    render()
  end
end

function update()
  noctalia.setUpdateInterval(5000)
  if not streamStarted then
    startStream()
  end
  render()
end

function onClick()
  noctalia.runAsync(voxtypeCmd() .. " record toggle")
end

function onMiddleClick()
  noctalia.runAsync(voxtypeCmd() .. " record stop")
end

function onRightClick()
  noctalia.runAsync(systemctlCmd() .. " --user restart voxtype")
end
