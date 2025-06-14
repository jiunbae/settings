local application = require "hs.application"

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

-- tracking Fn key state
hs.eventtap.new({ hs.eventtap.event.types.flagsChanged }, function(e)
  fnDown = e:getFlags().fn or false
  return false
end):start()

local MAP = { 
  i = "up", j = "left", k = "down", l = "right",
  ["ㅑ"] = "up", ["ㅓ"] = "left", ["ㅏ"] = "down", ["ㅣ"] = "right",
}

hs.eventtap.new(
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
):start()

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

--- Function to rotate window focus forward or backward within the same screen and space
function rotateWindowFocus(direction)
  local focusedWindow = hs.window.focusedWindow()
  if not focusedWindow then return end
  
  local focusedScreen = focusedWindow:screen()
  local visibleWindows = hs.window.visibleWindows()
  
  local firstVisibleWindows = nil
  local currentVisibleWindows = nil
  local previousVisibleWindows = nil
  local isWindowFocused = false

  for i, window in ipairs(visibleWindows) do
    if window:screen():id() == focusedScreen:id() and window:title() ~= "" then
      if firstVisibleWindows == nil then
        firstVisibleWindows = window
      end
      currentVisibleWindows = window
      
      if direction == "forward" and previousVisibleWindows == focusedWindow then
        window:focus()
        isWindowFocused = true
        break
      elseif direction == "backward" and window == focusedWindow and previousVisibleWindows ~= nil then
        previousVisibleWindows:focus()
        isWindowFocused = true
        break
      end
      previousVisibleWindows = window
    end
  end
  if not isWindowFocused then
    if direction == "forward" then
      firstVisibleWindows:focus()
    elseif direction == "backward" then
      currentVisibleWindows:focus()
    end
  end
end

-- Hotkeys to switch mouse focus to the first or second screen
hs.hotkey.bind({"alt", "shift"}, "i", function() moveMouseToScreen(1) end)
hs.hotkey.bind({"alt", "shift"}, "u", function() moveMouseToScreen(2) end)

-- Hotkeys to switch window to the first or second screen
hs.hotkey.bind({"ctrl", "alt", "shift"}, "i", function() moveWindowToScreen(1) end)
hs.hotkey.bind({"ctrl", "alt", "shift"}, "u", function() moveWindowToScreen(2) end)

-- Hotkey to cycle window focus
hs.hotkey.bind({"alt", "shift"}, "j", function() rotateWindowFocus("backward") end)
hs.hotkey.bind({"alt", "shift"}, "k", function() rotateWindowFocus("forward") end)
