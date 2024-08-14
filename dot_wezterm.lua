-- Pull in the wezterm API
local wezterm = require 'wezterm'


-- https://wezfurlong.org/wezterm/config/lua/wezterm.gui/get_appearance.html
-- 
-- wezterm.gui is not available to the mux server, so take care to
-- do something reasonable when this config is evaluated by the mux
function get_appearance()
  if wezterm.gui then
    return wezterm.gui.get_appearance()
  end
  return 'Dark'
end

function scheme_for_appearance(appearance)
  if appearance:find "Light" then
    return "Catppuccin Latte"
  else
    return "Catppuccin Mocha"
  end
end

-- This will hold the configuration.
local config = wezterm.config_builder()

-- inactive pane dimming
config.inactive_pane_hsb = {
  saturation = 0.90,
  brightness = 0.66,
}

-- https://www.reddit.com/r/wezterm/comments/10jda7o/is_there_a_way_not_to_open_urls_on_simple_click/
config.mouse_bindings = {
    -- Disable the default click behavior
    {
      event = { Up = { streak = 1, button = "Left"} },
      mods = "NONE",
      action = wezterm.action.DisableDefaultAssignment,
    },
    -- Ctrl-click will open the link under the mouse cursor
    {
        event = { Up = { streak = 1, button = "Left" } },
        mods = "CTRL",
        action = wezterm.action.OpenLinkAtMouseCursor,
    },
    -- Disable the Ctrl-click down event to stop programs from seeing it when a URL is clicked
    {
        event = { Down = { streak = 1, button = "Left" } },
        mods = "CTRL",
        action = wezterm.action.Nop,
    },
}

-- This is where you actually apply your config choices
config.color_scheme = scheme_for_appearance(wezterm.gui.get_appearance())
config.font_size = 16.0
config.enable_tab_bar = false

-- and finally, return the configuration to wezterm
return config
