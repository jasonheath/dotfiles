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

-- How many lines of scrollback you want to retain per tab
--config.scrollback_lines = 3500
--config.scrollback_lines = 65536
config.scrollback_lines = 131072
-- 2^17 = 131,072

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

local wezterm = require 'wezterm'
local act = wezterm.action

config.keys = {
    { key = '\"', mods = 'ALT|CTRL', action = act.SplitHorizontal{ domain =  'CurrentPaneDomain' } },
    { key = '\"', mods = 'SHIFT|ALT|CTRL', action = act.SplitHorizontal{ domain =  'CurrentPaneDomain' } },
    { key = '\'', mods = 'SHIFT|ALT|CTRL', action = act.SplitHorizontal{ domain =  'CurrentPaneDomain' } },

    { key = '=', mods = 'ALT|CTRL', action = act.SplitVertical{ domain =  'CurrentPaneDomain' } },
    { key = '=', mods = 'SHIFT|ALT|CTRL', action = act.SplitVertical{ domain =  'CurrentPaneDomain' } },
    { key = '+', mods = 'SHIFT|ALT|CTRL', action = act.SplitVertical{ domain =  'CurrentPaneDomain' } },
}

-- JAH: From here to config.ssh_domains = ssh_domains cleans up the shell menu
-- JAH: Leaving all this extra stuff so that I have clues in the future if I want them
local ssh_domains = {}
--for host, config in pairs(wezterm.enumerate_ssh_hosts()) do
--  if host:match("jah") then
--    table.insert(ssh_domains, {
--      name = host, -- the name can be anything you want; we're just using the hostname
--      remote_address = host, -- remote_address must be set to `host` for the ssh config to apply to it
--
--      -- if you don't have wezterm's mux server installed on the remote
--      -- host, you may wish to set multiplexing = "None" to use a direct
--      -- ssh connection that supports multiple panes/tabs which will close
--      -- when the connection is dropped.
--
--      -- multiplexing = "None",
--
--      -- if you know that the remote host has a posix/unix environment,
--      -- setting assume_shell = "Posix" will result in new panes respecting
--      -- the remote current directory when multiplexing = "None".
--      assume_shell = 'Posix',
--    })
--  end
--end
config.ssh_domains = ssh_domains

if string.find( wezterm.gui.get_appearance(), "Light") then
  config.set_environment_variables = {
    BAT_THEME = 'Catppuccin Latte'
  }
else
  config.set_environment_variables = {
    BAT_THEME = 'Catppuccin Mocha'
  }
end

-- and finally, return the configuration to wezterm
return config
