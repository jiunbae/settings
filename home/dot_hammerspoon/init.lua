local application = require "hs.application"

-- Logging
hs.logger.defaultLogLevel = "info"
local log = hs.logger.new("init", "info")
log.i("init.lua loaded at " .. os.date())

-- pcall + logging wrapper for hs.hotkey.bind callbacks so silent Lua errors
-- don't leave the keystroke unhandled (which would leak alt+u/i as dead keys)
local function safeBind(mods, key, name, fn)
  return hs.hotkey.bind(mods, key, function()
    local ok, err = pcall(fn)
    if not ok then log.ef("hotkey [%s] error: %s", name, tostring(err)) end
  end)
end

-- Fn + I/J/K/L to arrow keys for internal keyboards
local fnDown = false
local INTERNAL_TYPES = { 91 }

-- Function to convert flags table to a list of modifiers
local function flagsToList(flags)
  local list = {}
  for mod, on in pairs(flags) do
    if on and mod ~= "fn" then
      table.insert(list, mod)
    end
  end
  return list
end

-- Function to check if the event is from an internal keyboard
local function isInternal(event)
  local kt = event:getProperty(hs.eventtap.event.properties.keyboardEventKeyboardType)
  for _, v in ipairs(INTERNAL_TYPES) do
    if kt == v then return true end
  end
end

-- tracking Fn key state (stored in module-level local so GC won't reap it)
local fnFlagsTap = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged }, function(e)
  fnDown = e:getFlags().fn or false
  return false
end)
fnFlagsTap:start()

local MAP = { 
  i = "up", j = "left", k = "down", l = "right",
  ["ㅑ"] = "up", ["ㅓ"] = "left", ["ㅏ"] = "down", ["ㅣ"] = "right",
}

local fnRemapTap = hs.eventtap.new(
  { hs.eventtap.event.types.keyDown, hs.eventtap.event.types.keyUp },
  function(e)
    if not fnDown then return false end
    if not isInternal(e) then return false end

    local char = (e:getCharacters(true) or ""):lower()
    local arrow = MAP[char]
    if not arrow then return false end

    local modsList = flagsToList(e:getFlags())
    local isDown   = (e:getType() == hs.eventtap.event.types.keyDown)

    hs.eventtap.event.newKeyEvent(modsList, arrow, isDown):post()
    return true
  end
)
fnRemapTap:start()

-- Watchdog: macOS silently disables event taps that take too long or after
-- some sleep/wake cycles. Re-arm them every 30s if they've gone inactive.
local eventtapWatchdog = hs.timer.doEvery(30, function()
  if not fnFlagsTap:isEnabled() then
    log.w("fnFlagsTap disabled by system, restarting")
    fnFlagsTap:start()
  end
  if not fnRemapTap:isEnabled() then
    log.w("fnRemapTap disabled by system, restarting")
    fnRemapTap:start()
  end
end)

-- Function to move the mouse to a specific screen
function moveMouseToScreen(screenIndex)
  local screens = hs.screen.allScreens()
  if #screens >= screenIndex then
    local targetScreen = screens[screenIndex]
    local pt = hs.geometry.rectMidPoint(targetScreen:fullFrame())
    hs.mouse.absolutePosition(pt)

    local orderedWindows = hs.window.orderedWindows()
    for _, window in ipairs(orderedWindows) do
      if window:screen():id() == targetScreen:id() and window:title() ~= "" then
        window:focus()
        break
      end
    end
  end
end

--- Function to move window to a specific display
function moveWindowToScreen(screenIndex)
  local screens = hs.screen.allScreens()
  if #screens >= screenIndex then
    local targetScreen = screens[screenIndex]
    local window = hs.window.focusedWindow()
    window:moveToScreen(targetScreen, false, true)
  end
end

local function focusAndCenterMouse(window)
  if not window then return end
  window:focus()
  hs.mouse.absolutePosition(hs.geometry.rectMidPoint(window:frame()))
end

-- Rotate focus among windows on the current screen using a stable spatial
-- order (top -> bottom, then left -> right). Using window position instead of
-- z-order avoids the A<->B oscillation that happens when :focus() reshuffles
-- z-order between calls.
function rotateWindowFocus(direction)
  local focusedWindow = hs.window.focusedWindow()
  if not focusedWindow then return end
  local focusedScreenId = focusedWindow:screen():id()
  local focusedId = focusedWindow:id()

  local items = {}
  for _, w in ipairs(hs.window.visibleWindows()) do
    local s = w:screen()
    if s and s:id() == focusedScreenId then
      local t = w:title()
      if t and t ~= "" then
        local f = w:frame()
        items[#items + 1] = { w = w, id = w:id(), x = f.x, y = f.y }
      end
    end
  end
  if #items <= 1 then return end

  table.sort(items, function(a, b)
    if a.y ~= b.y then return a.y < b.y end
    if a.x ~= b.x then return a.x < b.x end
    return a.id < b.id
  end)

  local idx
  for i, it in ipairs(items) do
    if it.id == focusedId then idx = i; break end
  end

  local nextIdx
  if idx == nil then
    nextIdx = direction == "forward" and 1 or #items
  elseif direction == "forward" then
    nextIdx = idx % #items + 1
  else
    nextIdx = (idx - 2) % #items + 1
  end

  focusAndCenterMouse(items[nextIdx].w)
end

-- Hotkeys to switch mouse focus to the first or second screen
safeBind({"alt", "shift"}, "i", "mouse->screen1", function() moveMouseToScreen(1) end)
safeBind({"alt", "shift"}, "u", "mouse->screen2", function() moveMouseToScreen(2) end)

-- Hotkeys to switch window to the first or second screen
safeBind({"ctrl", "alt", "shift"}, "i", "window->screen1", function() moveWindowToScreen(1) end)
safeBind({"ctrl", "alt", "shift"}, "u", "window->screen2", function() moveWindowToScreen(2) end)

-- Hotkey to cycle window focus
safeBind({"alt", "shift"}, "j", "rotate-backward", function() rotateWindowFocus("backward") end)
safeBind({"alt", "shift"}, "k", "rotate-forward",  function() rotateWindowFocus("forward")  end)

log.i("hotkeys registered")
