local application = require "hs.application"

-- Function to move the mouse to a specific screen
function moveMouseToScreen(screenIndex)
  local screens = hs.screen.allScreens()
  if #screens >= screenIndex then
      local targetScreen = screens[screenIndex]
      local pt = hs.geometry.rectMidPoint(targetScreen:fullFrame())
      hs.mouse.absolutePosition(pt)
      
      local space = hs.spaces.activeSpaceOnScreen(targetScreen)
      if not space then
          print("⚠️ No active space found for screen " .. screenIndex)
          return
      end

      local visibleWindows = hs.window.filter.new()
        :setOverrideFilter({visible = true, allowScreens = {targetScreen:id()}})
        :getWindows()

      if #visibleWindows > 0 then
          visibleWindows[1]:focus()
      else
          print("⚠️ No visible windows found in active space.")
          return
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

-- Hotkeys to switch mouse focus to the first or second screen
hs.hotkey.bind({"alt", "shift"}, "i", function() moveMouseToScreen(1) end)
hs.hotkey.bind({"alt", "shift"}, "u", function() moveMouseToScreen(2) end)

-- Hotkeys to switch window to the first or second screen
hs.hotkey.bind({"ctrl", "alt", "shift"}, "i", function() moveWindowToScreen(1) end)
hs.hotkey.bind({"ctrl", "alt", "shift"}, "u", function() moveWindowToScreen(2) end)
