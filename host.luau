-- Single fetcher for every window. Provider adapters live in providers/*.luau;
-- this half reads their results into tern.kv, opens the detail block and keeps
-- a short history. Windows never read credentials or call a vendor.

local util = require("./providers/util")
local i18n = require("./i18n")

local PROVIDERS = {
	require("./providers/opencode"),
	require("./providers/claude"),
	require("./providers/codex"),
	require("./providers/copilot"),
	require("./providers/cursor"),
	require("./providers/gemini"),
	require("./providers/deepseek"),
}

local TICK_MS = 5_000

local function settings(): { [string]: any }
	local stored = tern.kv.get("settings")
	if type(stored) ~= "table" then
		stored = {}
	end
	if type(stored.interval) ~= "number" then
		stored.interval = 60
	end
	if type(stored.collapsed) ~= "table" then
		stored.collapsed = {}
	end
	if type(stored.hidden) ~= "table" then
		stored.hidden = {}
	end
	if type(stored.lang) ~= "string" then
		stored.lang = "auto"
	end
	if type(stored.open) ~= "string" then
		stored.open = "float"
	end
	if type(stored.relays) ~= "table" then
		stored.relays = {}
	end
	if type(stored.status_format) ~= "table" then
		stored.status_format = {}
	end
	local sf = stored.status_format
	if sf.mode ~= "used" then
		sf.mode = "remaining"
	end
	if type(sf.window) ~= "boolean" then
		sf.window = true
	end
	if type(sf.reset) ~= "boolean" then
		sf.reset = true
	end
	if type(sf.percent) ~= "boolean" then
		sf.percent = true
	end
	if type(sf.net) ~= "boolean" then
		sf.net = true
	end
	return stored
end

local function lang(): string
	return i18n.resolve(settings().lang)
end

local function provider_state(provider: any): { [string]: any }
	return {
		id = provider.id,
		name = provider.name,
		short = provider.short or provider.name,
		icon = provider.icon,
		windows = provider.windows,
	}
end

local function item_from(meta: { [string]: any }, result: any): { [string]: any }
	local windows = {}
	for _, spec in ipairs(meta.windows or {}) do
		local window = type(result) == "table" and result.windows and result.windows[spec.key] or nil
		if type(window) == "table" and type(window.used) == "number" then
			windows[#windows + 1] = {
				key = spec.key,
				label = spec.label,
				used = window.used,
				resets_at = window.resets_at,
			}
		end
	end
	return {
		id = meta.id,
		name = meta.name,
		short = meta.short or meta.name,
		icon = meta.icon,
		status = type(result) == "table" and result.status or "error",
		error = type(result) == "table" and result.error or nil,
		plan = type(result) == "table" and result.plan or nil,
		balance = type(result) == "table" and result.balance or nil,
		windows = windows,
	}
end

local function publish(state: { [string]: any })
	local previous = tern.kv.get("state")
	local history = type(previous) == "table" and previous.history or {}
	if type(history) ~= "table" then
		history = {}
	end
	local point = { t = os.time() }
	for _, provider in ipairs(PROVIDERS) do
		local item = state.providers[provider.id]
		local first = item and item.windows and item.windows[1]
		if type(first) == "table" and type(first.used) == "number" then
			point[provider.id] = util.remaining(first.used)
		end
	end
	history[#history + 1] = point
	while #history > 288 do
		table.remove(history, 1)
	end
	state.history = history
	state.updated = os.time()
	tern.kv.set("state", state)
end

local function fetch_provider(provider: any, done: (any) -> ())
	local base = provider_state(provider)
	if provider.detect and not provider.detect() then
		base.status = "signed_out"
		done(base)
		return
	end
	provider.fetch(function(result)
		if type(result) ~= "table" then
			result = { status = "error", error = "invalid result" }
		end
		done(item_from(base, result))
	end)
end

local function headers_for(relay: any): { [string]: string }
	local headers = {
		["Accept"] = "application/json",
		["User-Agent"] = "tern-quota",
	}
	if type(relay.key) == "string" and relay.key ~= "" then
		headers["Authorization"] = "Bearer " .. relay.key
	end
	return headers
end

local function fetch_relay(relay: any, index: number, done: (any) -> ())
	local meta = {
		id = "relay-" .. index,
		name = type(relay.name) == "string" and relay.name ~= "" and relay.name or ("Relay " .. index),
		short = type(relay.name) == "string" and relay.name ~= "" and relay.name or ("Relay " .. index),
		icon = "globe",
		windows = { { key = "included", label = "Included" } },
	}
	local base = type(relay.base) == "string" and relay.base:gsub("/+$", "") or ""
	if base == "" then
		done(item_from(meta, { status = "error", error = "missing base URL" }))
		return
	end
	local root = base:match("/v1$") and base or (base .. "/v1")
	local headers = headers_for(relay)
	util.fetch_json(root .. "/dashboard/billing/subscription", { headers = headers, timeout_ms = 15_000 }, function(subscription, sub_err, sub_status)
		if sub_err then
			done(item_from(meta, { status = (sub_status == 401 or sub_status == 403) and "auth" or "error", error = sub_err }))
			return
		end
		local limit = tonumber(subscription and subscription.hard_limit_usd)
			or tonumber(subscription and subscription.system_hard_limit_usd)
		if limit == nil or limit <= 0 then
			done(item_from(meta, { status = "error", error = "no billing limit" }))
			return
		end
		local now = os.date("*t")
		local start_date = string.format("%04d-%02d-01", now.year, now.month)
		local end_date = os.date("%Y-%m-%d")
		local usage_url = string.format(
			"%s/dashboard/billing/usage?start_date=%s&end_date=%s",
			root, start_date, end_date
		)
		util.fetch_json(usage_url, { headers = headers, timeout_ms = 15_000 }, function(usage, usage_err, usage_status)
			if usage_err then
				done(item_from(meta, { status = (usage_status == 401 or usage_status == 403) and "auth" or "error", error = usage_err }))
				return
			end
			local cents = tonumber(usage and usage.total_usage)
			if cents == nil then
				done(item_from(meta, { status = "error", error = "no usage total" }))
				return
			end
			local used = math.max(0, math.min(100, (cents / 100) / limit * 100))
			done(item_from(meta, { status = "ok", windows = { included = { used = used } } }))
		end)
	end)
end

local running = false

local function refresh_all()
	if running then
		return
	end
	running = true
	local state = {
		providers = {},
		order = {},
		updated = 0,
	}
	local relays = settings().relays
	if type(relays) ~= "table" then
		relays = {}
	end
	local pending = #PROVIDERS + #relays
	local function done()
		pending -= 1
		if pending > 0 then
			return
		end
		running = false
		publish(state)
	end
	for _, provider in ipairs(PROVIDERS) do
		state.order[#state.order + 1] = provider.id
		fetch_provider(provider, function(item)
			state.providers[provider.id] = item
			done()
		end)
	end
	for index, relay in ipairs(relays) do
		local id = "relay-" .. index
		state.order[#state.order + 1] = id
		fetch_relay(relay, index, function(item)
			state.providers[id] = item
			done()
		end)
	end
end

local function check_request()
	local request = tonumber(tern.kv.get("request")) or 0
	if request > 0 then
		tern.kv.set("request", 0)
		refresh_all()
	end
end

local function state_is_stale(): boolean
	local stored = tern.kv.get("state")
	if type(stored) ~= "table" or type(stored.providers) ~= "table" then
		return true
	end
	for _, provider in ipairs(PROVIDERS) do
		local item = stored.providers[provider.id]
		if type(item) ~= "table" or type(item.name) ~= "string" then
			return true
		end
	end
	return false
end

local NET_TICK_MS = 3_000
local net_busy = false
local net_prev: { rx: number, tx: number, t: number }? = nil
local NET_SCRIPT = "$s=Get-NetAdapterStatistics; $r=($s|Measure-Object ReceivedBytes -Sum).Sum; $t=($s|Measure-Object SentBytes -Sum).Sum; Write-Output $r; Write-Output $t"

local function sample_net()
	if net_busy then
		return
	end
	net_busy = true
	tern.process.run({ "powershell", "-NoProfile", "-Command", NET_SCRIPT }, { timeout_ms = 2_500 }, function(result)
		net_busy = false
		if not result or result.status ~= 0 or type(result.stdout) ~= "string" then
			return
		end
		local values = {}
		for value in result.stdout:gmatch("%d+") do
			values[#values + 1] = tonumber(value)
			if #values == 2 then
				break
			end
		end
		if #values < 2 then
			return
		end
		local rx, tx = values[1], values[2]
		local now = os.time()
		if net_prev and now > net_prev.t then
			local seconds = now - net_prev.t
			tern.kv.set("net", {
				down = math.max(0, (rx - net_prev.rx) / seconds),
				up = math.max(0, (tx - net_prev.tx) / seconds),
				at = now,
			})
		end
		net_prev = { rx = rx, tx = tx, t = now }
	end)
end

local function net_tick()
	sample_net()
	tern.timer(NET_TICK_MS, net_tick)
end

local function tick()
	local current = settings()
	local last = tonumber(tern.kv.get("last_fetch")) or 0
	if state_is_stale() or os.time() - last >= current.interval then
		tern.kv.set("last_fetch", os.time())
		refresh_all()
	end
	check_request()
	tern.timer(TICK_MS, tick)
end

-- ---------------------------------------------------------------------------
-- Detail block

local block_pane: number? = nil
local block_cx: any = nil
local block_seen: number? = nil

local KIND = "quota.detail"
local block_view_name = "main"

local function status_label(status: string): (string, string)
	local l = lang()
	if status == "ok" then
		return i18n.t(l, "normal"), "success"
	elseif status == "auth" then
		return i18n.t(l, "auth"), "error"
	elseif status == "signed_out" then
		return i18n.t(l, "signed_out"), "muted"
	end
	return i18n.t(l, "unavailable"), "error"
end

local function reset_text(iso: any): string
	if type(iso) ~= "string" then
		return ""
	end
	local y, mo, d, h, mi = iso:match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+)")
	if not y then
		return ""
	end
	local now = os.date("!*t")
	local target = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(mi), sec = 0 })
	local current = os.time({ year = now.year, month = now.month, day = now.day, hour = now.hour, min = now.min, sec = now.sec })
	local mins = math.floor((target - current) / 60)
	if mins <= 0 then
		return "now"
	end
	if mins < 60 then
		return mins .. "m"
	end
	return string.format("%dh%02dm", mins // 60, mins % 60)
end

local function provider_windows(item: any): any
	local l = lang()
	local rows: { any } = {}
	for _, window in ipairs(type(item) == "table" and item.windows or {}) do
		if type(window.used) == "number" then
			local left = util.remaining(window.used)
			local tone = left < 20 and "error" or (left < 40 and "warn" or nil)
			rows[#rows + 1] = tern.ui.el("div", { class = "q-row q-window" }, {
				tern.ui.node("text", {
					spans = { tern.ui.span(i18n.window_label(l, window.label or window.key) or "window", "muted") },
					role = "quota-label",
					basis = 0.30,
					min = { w = 0 },
				}),
				tern.ui.node("text", {
					spans = { tern.ui.span(string.format("%d%%", math.floor(left + 0.5)), left < 20 and "error" or "num") },
					role = "quota-pct",
					basis = 0.09,
					min = { w = 0 },
				}),
				tern.ui.node("progress", { value = left / 100, tone = tone, grow = 1, basis = 0.38 }),
				tern.ui.node("text", {
					spans = { tern.ui.span(reset_text(window.resets_at), "dim") },
					role = "quota-reset",
					basis = 0.16,
					min = { w = 0 },
				}),
			})
		end
	end
	if #rows == 0 then
		if type(item.balance) == "string" then
			return tern.ui.text({ tern.ui.span(item.balance, "num") })
		end
		return tern.ui.text({ tern.ui.span(i18n.t(l, "no_usage"), "muted") })
	end
	return tern.ui.node("col", { gap = "xs" }, rows)
end

local function provider_card(item: any, collapsed: boolean): any
	local label, tone = status_label(item.status)
	local header = tern.ui.el("button", { class = "q-head", actions = { click = "fold=" .. item.id } }, {
		tern.ui.node("icon", { name = item.icon or "puzzle" }),
		tern.ui.text({ tern.ui.span(item.name or item.id or "Provider", "strong") }),
		tern.ui.badge(label, tone),
		tern.ui.node("icon", { name = collapsed and "chev-r" or "chev-up" }),
	})
	local children = { header }
	if not collapsed then
		children[#children + 1] = provider_windows(item)
		if item.status ~= "ok" and item.error then
			children[#children + 1] = tern.ui.text({ tern.ui.span(item.error, "dim") })
		end
	end
	return tern.ui.el("div", { class = "q-card" .. (collapsed and " q-card--collapsed" or "") }, children)
end

local function tab(label: string, icon: string, action: string, active: boolean): any
	return tern.ui.el("button", { class = "q-tab" .. (active and " q-tab--on" or ""), actions = { click = action } }, {
		tern.ui.node("icon", { name = icon }),
		tern.ui.text({ tern.ui.span(label) }),
	})
end

local function main_view(state: any, settings_value: { [string]: any }): any
	local l = lang()
	local nodes: { any } = {}
	for _, id in ipairs(state.order or {}) do
		local item = state.providers and state.providers[id]
		if type(item) == "table" and settings_value.hidden[id] ~= true and item.status == "ok" then
			nodes[#nodes + 1] = provider_card(item, settings_value.collapsed[id] == true)
		end
	end
	if #nodes == 0 then
		nodes[1] = tern.ui.text({ tern.ui.span(i18n.t(l, "no_providers"), "muted") })
	end
	return tern.ui.col({ tern.ui.node("col", { gap = "lg", role = "quota-page" }, nodes) })
end

local function providers_view(state: any, settings_value: { [string]: any }): any
	local l = lang()
	local rows: { any } = {}
	for _, id in ipairs(state.order or {}) do
		local item = state.providers and state.providers[id]
		if type(item) == "table" then
			local hidden = settings_value.hidden[id] == true
			local label, tone = status_label(item.status)
			local actions: { any } = {}
			local setup_text
			if id == "deepseek" then
				setup_text = i18n.t(l, "set_key")
			else
				setup_text = i18n.t(l, "sign_in")
			end
			actions[#actions + 1] = tern.ui.el("button", {
				class = "q-choice q-choice--primary",
				text = setup_text,
				actions = { click = "setup=" .. id },
			})
			actions[#actions + 1] = tern.ui.el("button", {
				class = "q-choice q-choice--quiet",
				text = i18n.t(l, hidden and "show" or "hide"),
				actions = { click = (hidden and "show=" or "hide=") .. id },
			})
			rows[#rows + 1] = tern.ui.el("div", { class = "q-row" }, {
				tern.ui.node("icon", { name = item.icon or "puzzle" }),
				tern.ui.node("text", {
					spans = { tern.ui.span(item.name or id, "strong") },
					basis = 0.30,
					min = { w = 0 },
				}),
				tern.ui.badge(label, tone),
				tern.ui.el("div", { class = "q-choices" }, actions),
			})
		end
	end
	local relays = settings_value.relays
	if type(relays) ~= "table" then
		relays = {}
	end
	local custom_rows: { any } = {}
	for index, relay in ipairs(relays) do
		custom_rows[#custom_rows + 1] = tern.ui.el("div", { class = "q-row q-status-row" }, {
			tern.ui.node("icon", { name = "globe" }),
			tern.ui.node("text", {
				spans = { tern.ui.span(relay.name or ("Relay " .. index), "strong") },
				basis = 0.30,
				min = { w = 0 },
			}),
			tern.ui.node("text", {
				spans = { tern.ui.span(relay.base or "", "dim") },
				grow = 1,
				min = { w = 0 },
			}),
			tern.ui.el("button", {
				class = "q-choice q-choice--quiet",
				text = i18n.t(l, "remove"),
				actions = { click = "remove_relay=" .. index },
			}),
		})
	end
	if #custom_rows == 0 then
		custom_rows[1] = tern.ui.text({ tern.ui.span(i18n.t(l, "no_relays"), "dim") })
	end
	return tern.ui.col({ tern.ui.node("col", { gap = "md", role = "quota-page" }, {
		tern.ui.text({ tern.ui.span(i18n.t(l, "providers"), "strong") }),
		tern.ui.text({ tern.ui.span(i18n.t(l, "hide_hint"), "dim") }),
		tern.ui.node("col", { gap = "xs" }, rows),
		tern.ui.rule(""),
		tern.ui.el("div", { class = "q-row" }, {
			tern.ui.text({ tern.ui.span(i18n.t(l, "custom"), "strong") }),
			tern.ui.el("button", {
				class = "q-choice q-choice--primary",
				text = i18n.t(l, "add"),
				actions = { click = "add_relay" },
			}),
		}),
		tern.ui.node("col", { gap = "xs" }, custom_rows),
	}) })
end

local function settings_view(state: any, settings_value: { [string]: any }): any
	local l = lang()
	local intervals: { any } = {}
	for _, option in ipairs({
		{ 60, i18n.t(l, "minute1") },
		{ 120, i18n.t(l, "minute2") },
		{ 300, i18n.t(l, "minute5") },
	}) do
		local value, label = option[1], option[2]
		intervals[#intervals + 1] = tern.ui.el("button", {
			class = "q-choice" .. (settings_value.interval == value and " q-choice--on" or ""),
			text = label,
			actions = { click = "interval=" .. value },
		})
	end
	local languages: { any } = {}
	for _, option in ipairs({
		{ "auto", i18n.t(l, "auto") },
		{ "zh", i18n.t(l, "chinese") },
		{ "en", i18n.t(l, "english") },
	}) do
		local value, label = option[1], option[2]
		languages[#languages + 1] = tern.ui.el("button", {
			class = "q-choice" .. (settings_value.lang == value and " q-choice--on" or ""),
			text = label,
			actions = { click = "lang=" .. value },
		})
	end
	local opens: { any } = {}
	for _, option in ipairs({
		{ "tab", i18n.t(l, "open_tab") },
		{ "dock", i18n.t(l, "open_dock") },
		{ "float", i18n.t(l, "open_float") },
	}) do
		local value, label = option[1], option[2]
		opens[#opens + 1] = tern.ui.el("button", {
			class = "q-choice" .. (settings_value.open == value and " q-choice--on" or ""),
			text = label,
			actions = { click = "open=" .. value },
		})
	end
	local sf = settings_value.status_format
	local modes: { any } = {}
	for _, option in ipairs({
		{ "remaining", i18n.t(l, "remaining") },
		{ "used", i18n.t(l, "used") },
	}) do
		local value, label = option[1], option[2]
		modes[#modes + 1] = tern.ui.el("button", {
			class = "q-choice" .. (sf.mode == value and " q-choice--on" or ""),
			text = label,
			actions = { click = "status_mode=" .. value },
		})
	end
	local toggles: { any } = {}
	for _, option in ipairs({
		{ "window", i18n.t(l, "window") },
		{ "reset", i18n.t(l, "reset") },
		{ "percent", i18n.t(l, "percent") },
		{ "net", i18n.t(l, "speed") },
	}) do
		local key, label = option[1], option[2]
		toggles[#toggles + 1] = tern.ui.el("button", {
			class = "q-choice" .. (sf[key] and " q-choice--on" or ""),
			text = label,
			actions = { click = "status_toggle=" .. key },
		})
	end

	return tern.ui.col({ tern.ui.node("col", { gap = "lg", role = "quota-page" }, {
		tern.ui.text({ tern.ui.span(i18n.t(l, "settings"), "strong") }),
		tern.ui.el("div", { class = "q-setting" }, {
			tern.ui.text({ tern.ui.span(i18n.t(l, "refresh"), "muted") }),
			tern.ui.el("div", { class = "q-choices" }, intervals),
		}),
		tern.ui.el("div", { class = "q-setting" }, {
			tern.ui.text({ tern.ui.span(i18n.t(l, "language"), "muted") }),
			tern.ui.el("div", { class = "q-choices" }, languages),
		}),
		tern.ui.el("div", { class = "q-setting" }, {
			tern.ui.text({ tern.ui.span(i18n.t(l, "open_as"), "muted") }),
			tern.ui.el("div", { class = "q-choices" }, opens),
		}),
		tern.ui.rule(""),
		tern.ui.text({ tern.ui.span(i18n.t(l, "status_bar"), "strong") }),
		tern.ui.el("div", { class = "q-setting" }, {
			tern.ui.text({ tern.ui.span(i18n.t(l, "status_quota"), "muted") }),
			tern.ui.el("div", { class = "q-choices" }, modes),
		}),
		tern.ui.el("div", { class = "q-setting" }, {
			tern.ui.text({ tern.ui.span(i18n.t(l, "status_show"), "muted") }),
			tern.ui.el("div", { class = "q-choices" }, toggles),
		}),
	}) })
end

local function block_view(_state: any): any
	local state_value = tern.kv.get("state")
	local settings_value = settings()
	local l = lang()
	local dock = tern.ui.node("col", { gap = "none" }, {
		tern.ui.node("row", { gap = "md" }, {
			tab(i18n.t(l, "overview"), "gauge", "view=main", block_view_name == "main"),
			tab(i18n.t(l, "providers"), "sliders", "view=providers", block_view_name == "providers"),
			tab(i18n.t(l, "settings"), "gear", "view=settings", block_view_name == "settings"),
		}),
	})
	if type(state_value) ~= "table" then
		return { main = tern.ui.col({ tern.ui.progress(nil, "Loading quota…") }), dock = dock }
	end
	local page
	if block_view_name == "providers" then
		page = providers_view(state_value, settings_value)
	elseif block_view_name == "settings" then
		page = settings_view(state_value, settings_value)
	else
		page = main_view(state_value, settings_value)
	end
	return { main = page, dock = dock }
end

tern.block.define("detail", {
	init = function(cx: any, _args: { string }, _saved: any): any
		block_pane = cx.pane
		block_cx = cx
		local nav = tern.kv.get("navigate")
		block_view_name = nav == "providers" and "providers" or nav == "settings" and "settings" or "main"
		if nav ~= nil then
			tern.kv.set("navigate", nil)
		end
		return { seen = 0 }
	end,
	view = function(_state: any, _cx: any): any
		return block_view(_state)
	end,
	title = function(_state: any): string?
		return "Quota"
	end,
	key = function(_state: any, key: any, cx: any): boolean?
		local kname = type(key.name) == "string" and key.name:lower() or ""
		if kname == "r" then
			tern.kv.set("request", 1)
			cx:render()
			return true
		end
		if kname == "q" or kname == "escape" then
			cx:exit(0)
			return true
		end
		return false
	end,
	event = function(_state: any, ev: any, cx: any)
		if ev.ev ~= "action" or type(ev.act) ~= "string" then
			return
		end
		local current = settings()
		if ev.act == "fold" then
			local id = ev.value
			current.collapsed[id] = not current.collapsed[id]
			tern.kv.set("settings", current)
			cx:render()
		elseif ev.act == "view" then
			block_view_name = ev.value == "providers" and "providers" or ev.value == "settings" and "settings" or "main"
			cx:render()
		elseif ev.act == "interval" then
			current.interval = tonumber(ev.value) or 60
			tern.kv.set("settings", current)
			tern.kv.set("request", 1)
			cx:render()
		elseif ev.act == "hide" then
			current.hidden[ev.value] = true
			tern.kv.set("settings", current)
			cx:render()
		elseif ev.act == "show" then
			current.hidden[ev.value] = nil
			tern.kv.set("settings", current)
			cx:render()
		elseif ev.act == "lang" then
			current.lang = ev.value
			tern.kv.set("settings", current)
			cx:render()
		elseif ev.act == "setup" then
			tern.kv.set("ui_action", "setup:" .. ev.value)
		elseif ev.act == "add_relay" then
			tern.kv.set("ui_action", "add_relay")
		elseif ev.act == "remove_relay" then
			local index = tonumber(ev.value)
			if index and current.relays and current.relays[index] then
				table.remove(current.relays, index)
				tern.kv.set("settings", current)
				tern.kv.set("request", 1)
				cx:render()
			end
		elseif ev.act == "open" then
			current.open = ev.value
			tern.kv.set("settings", current)
			cx:render()
		elseif ev.act == "status_mode" then
			current.status_format.mode = ev.value == "used" and "used" or "remaining"
			tern.kv.set("settings", current)
			cx:render()
		elseif ev.act == "status_toggle" then
			local key = ev.value
			if key == "window" or key == "reset" or key == "percent" or key == "net" then
				current.status_format[key] = not current.status_format[key]
				tern.kv.set("settings", current)
				cx:render()
			end
		end
	end,
})

local function block_poll()
	if block_pane ~= nil then
		local alive = false
		for _, pane in ipairs(tern.pane.list()) do
			if pane.pane == block_pane then
				alive = true
				break
			end
		end
		if not alive then
			block_pane = nil
			block_cx = nil
		else
			local nav = tern.kv.get("navigate")
			if type(nav) == "string" then
				tern.kv.set("navigate", nil)
				block_view_name = nav == "providers" and "providers" or nav == "settings" and "settings" or "main"
			end
			if block_cx and type(nav) == "string" then
				block_cx:render()
			end
			local stored = tern.kv.get("state")
			local updated = type(stored) == "table" and stored.updated or 0
			if updated ~= block_seen then
				block_seen = updated
				if block_cx then
					block_cx:render()
				end
			end
		end
	end
	tern.timer(2_000, block_poll)
end

tick()
net_tick()
tern.timer(2_000, block_poll)
