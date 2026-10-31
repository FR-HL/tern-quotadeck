-- Status line segments and the command that opens the one detail block.
-- This half only reads the host's shared state; it never touches credentials.

local i18n = require("./i18n")

local POLL_MS = 2_000
local KIND = "quota.detail"
local WINDOW_LABEL = {
	rolling = "5h",
	five_hour = "5h",
	weekly = "7d",
	seven_day = "7d",
	monthly = "mo",
	premium_interactions = "premium",
	chat = "chat",
	completions = "code",
}

local function window_label(key: any, label: any): string
	local known = WINDOW_LABEL[key]
	if known then
		return known
	end
	local text = type(label) == "string" and label:lower() or ""
	if text:find("5", 1, true) and (text:find("hour", 1, true) or text:find("小时", 1, true)) then
		return "5h"
	end
	if (text:find("7", 1, true) or text:find("week", 1, true))
		and (text:find("day", 1, true) or text:find("week", 1, true) or text:find("天", 1, true)) then
		return "7d"
	end
	if text:find("month", 1, true) or text:find("月", 1, true) then
		return "mo"
	end
	if text:find("premium", 1, true) then
		return "premium"
	end
	if text:find("chat", 1, true) then
		return "chat"
	end
	if text:find("completion", 1, true) then
		return "code"
	end
	return type(label) == "string" and label or "window"
end

local segments: { { [string]: any } } = {}

local function minutes_until(iso: any): number?
	if type(iso) ~= "string" then
		return nil
	end
	local y, mo, d, h, mi = iso:match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+)")
	if not y then
		return nil
	end
	local now = os.date("!*t")
	local target = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(mi), sec = 0 })
	local current = os.time({ year = now.year, month = now.month, day = now.day, hour = now.hour, min = now.min, sec = now.sec })
	return math.floor((target - current) / 60)
end

local function short_delta(iso: any): string
	local mins = minutes_until(iso)
	if not mins then
		return ""
	end
	if mins <= 0 then
		return "now"
	end
	if mins < 60 then
		return string.format("%dm", mins)
	end
	return string.format("%dh%02dm", mins // 60, mins % 60)
end

local function remaining(used: number): number
	local value = 100 - used
	if value < 0 then
		return 0
	elseif value > 100 then
		return 100
	end
	return value
end

local function status_format(settings: any): { [string]: any }
	local sf = type(settings) == "table" and type(settings.status_format) == "table" and settings.status_format or {}
	local tones = { success = true, error = true, warning = true, info = true, accent = true, muted = true, neutral = true }
	return {
		mode = sf.mode == "used" and "used" or "remaining",
		names = sf.names == "full" and "full" or "short",
		window = sf.window ~= false,
		reset = sf.reset ~= false,
		percent = sf.percent ~= false,
		net = sf.net ~= false,
		net_down = tones[sf.net_down] and sf.net_down or "success",
		net_up = tones[sf.net_up] and sf.net_up or "error",
	}
end

local function speed_text(bytes: number): string
	if bytes >= 1024 * 1024 then
		return string.format("%.1f MB/s", bytes / (1024 * 1024))
	elseif bytes >= 1024 then
		return string.format("%.0f KB/s", bytes / 1024)
	end
	return string.format("%.0f B/s", bytes)
end

local function segment(item: any): { [string]: any }?
	if type(item) ~= "table" then
		return nil
	end
	local settings = tern.kv.get("settings")
	local l = i18n.resolve(type(settings) == "table" and settings.lang or "auto")
	local sf = status_format(settings)
	local status = item.status
	if status == "signed_out" then
		return nil
	end
	local name = sf.names == "full"
		and (item.name or item.short or "quota")
		or (item.short or item.name or "quota")
	local window = type(item.windows) == "table" and item.windows[1] or nil
	if status == "ok" and type(window) == "table" then
		local left = remaining(window.used)
		local label = window_label(window.key, window.label)
		local delta = short_delta(window.resets_at)
		local used = math.max(0, math.min(100, math.floor(window.used + 0.5)))
		local pct = sf.mode == "used" and used or math.floor(left + 0.5)
		local text = name
		local first = {}
		if sf.window then
			first[#first + 1] = label
		end
		if sf.reset and delta ~= "" then
			first[#first + 1] = delta
		end
		if #first > 0 then
			text = text .. " " .. table.concat(first, " ")
		end
		if sf.percent then
			text = #first > 0 and (text .. " " .. pct .. "%") or (text .. " " .. pct .. "%")
		end
		return {
			text = text,
			icon = item.icon or "puzzle",
			tone = left < 20 and "error" or nil,
			command = "plugin.quota.detail",
		}
	end
	if status == "ok" and type(window) ~= "table" and type(item.balance) == "string" then
		return {
			text = string.format("%s %s", name, item.balance),
			icon = item.icon or "puzzle",
			tone = nil,
			command = "plugin.quota.detail",
		}
	end
	if status == "auth" then
		return { text = name .. " " .. i18n.t(l, "auth"), icon = item.icon or "puzzle", tone = "error", command = "plugin.quota.detail" }
	end
	if status == "error" then
		return { text = name .. " " .. i18n.t(l, "unavailable"), icon = item.icon or "puzzle", tone = "error", command = "plugin.quota.detail" }
	end
	return nil
end

local signature: string? = nil

local function visibility_signature(settings: any): string
	if type(settings) ~= "table" then
		return ""
	end
	local keys = {}
	if type(settings.hidden) == "table" then
		for id, hidden in pairs(settings.hidden) do
			if hidden then
				keys[#keys + 1] = "v:" .. id
			end
		end
	end
	if type(settings.hidden_status) == "table" then
		for id, hidden in pairs(settings.hidden_status) do
			if hidden then
				keys[#keys + 1] = "s:" .. id
			end
		end
	end
	table.sort(keys)
	return table.concat(keys, ",")
end

local function format_signature(settings: any): string
	local sf = status_format(settings)
	return table.concat({
		sf.mode,
		sf.names,
		tostring(sf.window),
		tostring(sf.reset),
		tostring(sf.percent),
		tostring(sf.net),
		sf.net_down,
		sf.net_up,
	}, ",")
end

local function rebuild()
	local stored = tern.kv.get("state")
	if type(stored) ~= "table" then
		return
	end
	local settings = tern.kv.get("settings")
	local net = tern.kv.get("net")
	local sig = tostring(stored.updated) .. "|" .. visibility_signature(settings)
		.. "|" .. format_signature(settings) .. "|" .. tostring(type(net) == "table" and net.at or nil)
	if sig == signature then
		return
	end
	signature = sig
	local hidden = type(settings) == "table" and type(settings.hidden_status) == "table" and settings.hidden_status or {}
	local l = i18n.resolve(type(settings) == "table" and settings.lang or "auto")
	local out = {}
	local function push(value: any)
		if #out > 0 then
			out[#out + 1] = { text = "|" }
		end
		out[#out + 1] = value
	end
	for _, id in ipairs(stored.order or {}) do
		local item = stored.providers and stored.providers[id]
		if hidden[id] ~= true then
			local value = segment(item)
			if value then
				push(value)
			end
		end
	end
	local sf = status_format(settings)
	if sf.net and type(net) == "table" and type(net.down) == "number" and type(net.up) == "number"
		and os.time() - (tonumber(net.at) or 0) <= 12 then
		local down_text = "↓ " .. speed_text(net.down)
		local up_text = "↑ " .. speed_text(net.up)
		push({
			text = down_text,
			tone = sf.net_down,
			command = "plugin.quota.settings",
		})
		out[#out + 1] = {
			text = up_text,
			tone = sf.net_up,
			command = "plugin.quota.settings",
		}
	end
	segments = out
	tern.chrome.refresh()
end

local LOGIN = {
	opencode = "opencode",
	claude = "claude",
	codex = "codex login",
	copilot = "gh auth login",
	cursor = "cursor-agent login",
	gemini = "gemini",
}

local function set_deepseek_key(cx)
	cx:prompt({ placeholder = "DeepSeek API key", icon = "key" }):next(function(value, _err, next_cx)
		if type(value) ~= "string" or value == "" then
			return
		end
		local settings = tern.kv.get("settings")
		if type(settings) ~= "table" then
			settings = {}
		end
		if type(settings.keys) ~= "table" then
			settings.keys = {}
		end
		settings.keys.deepseek = value
		tern.kv.set("settings", settings)
		tern.kv.set("request", 1)
		if next_cx then
			next_cx:toast("success", "DeepSeek key saved")
		end
	end)
end

local function add_relay(kind: string, cx)
	local base_hint
	if kind == "newapi" then
		base_hint = "New API root (https://relay.example.com)"
	elseif kind == "openai" then
		base_hint = "OpenAI API root (https://api.example.com/v1)"
	else
		base_hint = "Base URL (https://relay.example.com or https://host/v1)"
	end
	cx:prompt({ placeholder = "Name", icon = "globe" }):next(function(name, _err, cx1)
		if type(name) ~= "string" or name == "" then
			return
		end
		cx1:prompt({ placeholder = base_hint, icon = "globe" }):next(function(base, _err2, cx2)
			if type(base) ~= "string" or base == "" then
				return
			end
			cx2:prompt({ placeholder = "API key", icon = "key" }):next(function(key, _err3, cx3)
				if type(key) ~= "string" or key == "" then
					return
				end
				local settings = tern.kv.get("settings")
				if type(settings) ~= "table" then
					settings = {}
				end
				if type(settings.relays) ~= "table" then
					settings.relays = {}
				end
				table.insert(settings.relays, {
					name = name,
					base = base,
					key = key,
					kind = kind,
				})
				tern.kv.set("settings", settings)
				tern.kv.set("request", 1)
				if cx3 then
					local current = tern.kv.get("settings")
					local l = i18n.resolve(type(current) == "table" and current.lang or "auto")
					cx3:toast("success", i18n.t(l, "relay_added"), name)
				end
			end)
		end)
	end)
end

local function setup_provider(id: string, cx)
	if id == "deepseek" then
		set_deepseek_key(cx)
		return
	end
	local command = LOGIN[id]
	if command then
		cx.layout:new_tab({ command = command }, { focus = true })
		cx:toast("info", "Sign in in the new tab, then refresh")
	end
end

local function handle_ui_action(cx)
	local action = tern.kv.get("ui_action")
	if type(action) ~= "string" then
		return
	end
	tern.kv.set("ui_action", nil)
	if action:sub(1, 6) == "setup:" then
		setup_provider(action:sub(7), cx)
	elseif action:match("^add_relay=%w+$") then
		add_relay(action:match("^add_relay=(%w+)$"), cx)
	end
end

local function poll(cx)
	rebuild()
	if cx then
		handle_ui_action(cx)
	end
	tern.timer(POLL_MS, poll)
end

local function open_detail(cx)
	local stored = tonumber(tern.kv.get("detail_pane"))
	if stored then
		local pane = cx.session:pane(stored)
		if pane then
			if pane.parked then
				cx.layout:unpark(pane.pane, { focus = true })
			elseif pane.floating then
				cx.layout:focus(pane.pane)
			else
				cx.layout:float(pane.pane, nil, "br", { size = { 120, 45 }, focus = true })
				cx.layout:focus(pane.pane)
			end
			return
		end
	end
	local settings = tern.kv.get("settings")
	local mode = type(settings) == "table" and settings.open or "tab"
	local target = cx.session:focused()
	local pane
	if mode == "float" then
		pane = cx:new_block(KIND, nil, "tab", { focus = true })
	elseif mode == "dock" then
		pane = cx:new_block(KIND, nil, "beside", { focus = true, ratio = 0.45 })
	else
		pane = cx:new_block(KIND, nil, "tab", { focus = true })
	end
	if not pane then
		cx:toast("error", "Quota", "block unavailable")
		return
	end
	tern.kv.set("detail_pane", pane)
	if mode == "float" then
		cx.layout:float(pane, target, "br", { size = { 120, 45 }, focus = true })
		cx.layout:focus(pane)
	end
end

tern.command({
	id = "detail",
	title = "Quota: Show details",
	icon = "gauge",
	group = "Quota",
	run = open_detail,
})

tern.command({
	id = "providers",
	title = "Quota: Choose providers",
	icon = "sliders",
	group = "Quota",
	run = function(cx)
		tern.kv.set("navigate", "providers")
		open_detail(cx)
	end,
})

tern.command({
	id = "settings",
	title = "Quota: Settings",
	icon = "gear",
	group = "Quota",
	run = function(cx)
		tern.kv.set("navigate", "settings")
		open_detail(cx)
	end,
})

tern.command({
	id = "deepseek_key",
	title = "Quota: Set DeepSeek API key",
	icon = "key",
	group = "Quota",
	run = function(cx)
		set_deepseek_key(cx)
	end,
})

tern.command({
	id = "refresh",
	title = "Quota: Refresh now",
	icon = "swap",
	group = "Quota",
	run = function(cx)
		tern.kv.set("request", 1)
		cx:toast("info", "Refreshing quota…")
	end,
})

tern.chrome.status(function(_pane)
	if #segments == 0 then
		return nil
	end
	return segments
end)

rebuild()
tern.timer(POLL_MS, poll)
