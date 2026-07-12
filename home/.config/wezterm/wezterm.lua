local wezterm = require("wezterm")

local config = wezterm.config_builder()

config.color_scheme = "tokyonight_moon"
config.font = wezterm.font("Hack Nerd Font")
config.font_size = 20.0
config.window_background_opacity =1
config.macos_window_background_blur = 50
config.hide_tab_bar_if_only_one_tab = true
config.window_decorations = "RESIZE"
config.audible_bell = "Disabled"
config.notification_handling = "NeverShow"

-- Dim unfocused windows so the focused one is obvious at a glance.
local UNFOCUSED_FOREGROUND_TEXT_HSB = { hue = 1.0, saturation = 0.6, brightness = 0.75 }
local UNFOCUSED_WINDOW_BACKGROUND_OPACITY = 0.95

-- get_config_overrides() hands back a copy, so the current value is never the
-- same table we last stored; compare the fields instead of the identity.
local function same_text_hsb(actual, expected)
	if actual == nil or expected == nil then
		return actual == expected
	end
	return actual.hue == expected.hue
		and actual.saturation == expected.saturation
		and actual.brightness == expected.brightness
end

wezterm.on("window-focus-changed", function(window)
	local overrides = window:get_config_overrides() or {}
	local text_hsb, opacity
	if not window:is_focused() then
		text_hsb = UNFOCUSED_FOREGROUND_TEXT_HSB
		opacity = UNFOCUSED_WINDOW_BACKGROUND_OPACITY
	end

	-- Only write when one of the two values we own actually changes; a redundant
	-- set_config_overrides() call would trigger another config reload.
	if same_text_hsb(overrides.foreground_text_hsb, text_hsb) and overrides.window_background_opacity == opacity then
		return
	end

	overrides.foreground_text_hsb = text_hsb
	overrides.window_background_opacity = opacity
	window:set_config_overrides(overrides)
end)

-- With Herdr mouse_capture=false, the Herdr client is a full-screen alt-screen app
-- enabling no mouse reporting, so WezTerm would otherwise synthesize Up/Down arrow
-- keys for wheel scroll (default speed 3) and a pane REPL reads them as history
-- navigation. Set to 0 so wheel input in alternate-screen apps is never turned into
-- arrow keys. Scroll pane scrollback with PageUp/PageDown or copy-mode (prefix+y).
config.alternate_buffer_wheel_scroll_speed = 0

return config
