-- Single fetcher for every window. Provider adapters live in providers/*.luau;
-- this half reads their results into tern.kv, opens the detail block and keeps
-- a short history. Windows never read credentials or call a vendor.

local util = require("./providers/util")
local i18n = require("./i18n")

-- Every *.luau file in providers/ or sources/ is an adapter. A broken or
-- incomplete file is ignored, so users can add one without editing this file.
local function load_adapters(dirname: string): { any }
	local dir = tern.plugin.dir .. "/" .. dirname
	local ok, names = pcall(tern.fs.list, dir)
	if not ok or type(names) ~= "table" then
		return {}
	end
	local out = {}
	for _, name in ipairs(names) do
		local base = name:match("^(.-)%.luau$")
		if base and base ~= "util" then
			local loaded, adapter = pcall(require, "./" .. dirname .. "/" .. base)
			if loaded and type(adapter) == "table" and type(adapter.fetch) == "function" then
				out[#out + 1] = adapter
			end
		end
	end
	return out
end

local PROVIDERS = load_adapters("providers")
-- Sources return several providers at once; they are merged into the same list.
local SOURCES = load_adapters("sources")
-- Context adapters read each agent's own session log.
local CONTEXTS = load_adapters("contexts")

local STATE_SCHEMA = 2
local TICK_MS = 5_000

-- Magpie's provider ids that a direct adapter already covers.
local ID_ALIASES = {
	["opencode-go"] = "opencode",
}

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
	if type(stored.hidden_status) ~= "table" then
		stored.hidden_status = {}
		for id, hidden in pairs(stored.hidden) do
			stored.hidden_status[id] = hidden
		end
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
	if sf.names ~= "full" and sf.names ~= "none" then
		sf.names = "short"
	end
	if type(sf.icon) ~= "boolean" then
		sf.icon = true
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
	local tones = { success = true, error = true, warning = true, info = true, accent = true, muted = true, neutral = true }
	if not tones[sf.net_down] then
		sf.net_down = "success"
	end
	if not tones[sf.net_up] then
		sf.net_up = "error"
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
		source = provider.source,
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
	for _, id in ipairs(state.order or {}) do
		local item = state.providers[id]
		local first = item and item.windows and item.windows[1]
		if type(first) == "table" and type(first.used) == "number" then
			point[id] = util.remaining(first.used)
		end
	end
	history[#history + 1] = point
	while #history > 10_080 do
		table.remove(history, 1)
	end
	state.history = history
	state.schema = STATE_SCHEMA
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

local BROWSER_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"

local function headers_for(relay: any, browser_ua: boolean): { [string]: string }
	local headers = {
		["Accept"] = "application/json",
		["User-Agent"] = browser_ua and BROWSER_UA or "tern-quota",
	}
	if type(relay.key) == "string" and relay.key ~= "" then
		headers["Authorization"] = "Bearer " .. relay.key
	end
	return headers
end

local function short_code(name: string): string
	local initials = name:gsub("[^%w%s]", ""):gsub("(%a)%S*%s*", "%1"):upper()
	if #initials >= 2 then
		return initials
	end
	return name:sub(1, 3):upper()
end

local function grouped(value: number): string
	local text = string.format("%.0f", value)
	local result = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if result:sub(1, 1) == "," then
		result = result:sub(2)
	end
	return result
end

local function relay_status(status: number?): string
	return (status == 401 or status == 403) and "auth" or "error"
end

local function fetch_newapi(relay: any, meta: any, base: string, done: (any) -> ())
	-- New API exposes the token balance under the relay root, not under /v1.
	local root = base:gsub("/+$", ""):gsub("/v1$", "")
	local url = root .. "/api/usage/token/"
	util.fetch_json(url, { headers = headers_for(relay, true), timeout_ms = 15_000 }, function(value, err, status)
		if err then
			done(item_from(meta, { status = relay_status(status), error = err }))
			return
		end
		local data = type(value) == "table" and value.data or nil
		local valid = type(value) == "table" and (value.code == true or value.code == 0)
		if not valid or type(data) ~= "table" then
			local message = type(value) == "table" and value.message or "invalid response"
			done(item_from(meta, { status = relay_status(status), error = tostring(message) }))
			return
		end
		local available = tonumber(data.account_total_available)
			or tonumber(data.total_available)
			or tonumber(type(data.user_quota) == "table" and data.user_quota.total_available)
		local used = tonumber(data.account_total_used)
			or tonumber(data.total_used)
			or tonumber(type(data.user_quota) == "table" and data.user_quota.total_used)
		local granted = tonumber(data.account_total_granted)
			or tonumber(data.total_granted)
		if used == nil then
			done(item_from(meta, { status = "error", error = "no usage total" }))
			return
		end
		if data.unlimited_quota == true or (granted ~= nil and granted <= 0) then
			done(item_from(meta, {
				status = "ok",
				balance = "Unlimited · " .. grouped(used) .. " used",
			}))
			return
		end
		if granted == nil or granted <= 0 then
			done(item_from(meta, { status = "error", error = "no quota total" }))
			return
		end
		local percent = math.max(0, math.min(100, used / granted * 100))
		local balance = available ~= nil and (grouped(available) .. " left") or nil
		done(item_from(meta, {
			status = "ok",
			windows = { quota = { used = percent } },
			balance = balance,
		}))
	end)
end

local function fetch_openai_billing(relay: any, meta: any, base: string, done: (any) -> ())
	local root = base:match("/v1$") and base or (base .. "/v1")
	local headers = headers_for(relay, false)
	util.fetch_json(root .. "/dashboard/billing/subscription", { headers = headers, timeout_ms = 15_000 }, function(subscription, sub_err, sub_status)
		if sub_err then
			done(item_from(meta, { status = relay_status(sub_status), error = sub_err }))
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
				done(item_from(meta, { status = relay_status(usage_status), error = usage_err }))
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

local function fetch_relay(relay: any, index: number, done: (any) -> ())
	local kind = relay.kind
	if kind ~= "newapi" and kind ~= "openai" then
		kind = "auto"
	end
	local name = type(relay.name) == "string" and relay.name ~= "" and relay.name or ("Relay " .. index)
	local meta = {
		id = "relay-" .. index,
		name = name,
		short = short_code(name),
		icon = "globe",
		source = "custom",
		windows = { { key = "quota", label = "Quota" } },
	}
	local base = type(relay.base) == "string" and relay.base:gsub("/+$", "") or ""
	if base == "" then
		done(item_from(meta, { status = "error", error = "missing base URL" }))
		return
	end
	if kind == "newapi" then
		fetch_newapi(relay, meta, base, done)
	elseif kind == "openai" then
		meta.windows = { { key = "included", label = "Included" } }
		fetch_openai_billing(relay, meta, base, done)
	else
		-- One custom entry: try the relay's token endpoint first, then the
		-- OpenAI billing endpoints. Auth errors mean the endpoint exists.
		fetch_newapi(relay, meta, base, function(item)
			if type(item) == "table" and (item.status == "ok" or item.status == "auth") then
				done(item)
				return
			end
			meta.windows = { { key = "included", label = "Included" } }
			fetch_openai_billing(relay, meta, base, done)
		end)
	end
end

local running = false

local function merge_item(state: any, priorities: any, item: any, priority: number)
	if type(item) ~= "table" or type(item.id) ~= "string" or item.id == "" then
		return
	end
	local id = ID_ALIASES[item.id] or item.id
	item.id = id
	local existing = state.providers[id]
	local rank = priorities[id] or 0
	local replace = false
	if not existing then
		replace = true
	elseif item.status == "ok" and existing.status ~= "ok" then
		replace = true
	elseif item.status == existing.status and priority > rank then
		replace = true
	elseif item.status ~= "ok" and existing.status ~= "ok" and priority > rank then
		replace = true
	end
	if replace then
		if not existing then
			state.order[#state.order + 1] = id
		end
		state.providers[id] = item
		priorities[id] = priority
	end
end

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
	local priorities = {}
	local relays = settings().relays
	if type(relays) ~= "table" then
		relays = {}
	end
	local pending = #PROVIDERS + #relays + #SOURCES
	local function done()
		pending -= 1
		if pending > 0 then
			return
		end
		running = false
		publish(state)
	end
	for _, provider in ipairs(PROVIDERS) do
		fetch_provider(provider, function(item)
			merge_item(state, priorities, item, 2)
			done()
		end)
	end
	for index, relay in ipairs(relays) do
		fetch_relay(relay, index, function(item)
			merge_item(state, priorities, item, 3)
			done()
		end)
	end
	for _, source in ipairs(SOURCES) do
		local ok = pcall(source.fetch, function(items)
			if type(items) == "table" then
				for _, item in ipairs(items) do
					merge_item(state, priorities, item, 1)
				end
			end
			done()
		end)
		if not ok then
			done()
		end
	end
end

local context_running = false

local function refresh_contexts()
	if context_running then
		return
	end
	context_running = true
	local sessions = {}
	local pending = #CONTEXTS
	local function finish()
		pending -= 1
		if pending > 0 then
			return
		end
		context_running = false
		table.sort(sessions, function(a, b)
			return tostring(a.at or "") > tostring(b.at or "")
		end)
		tern.kv.set("context_state", { updated = os.time(), sessions = sessions })
	end
	if pending == 0 then
		context_running = false
		tern.kv.set("context_state", { updated = os.time(), sessions = sessions })
		return
	end
	for _, adapter in ipairs(CONTEXTS) do
		local ok = pcall(adapter.fetch, function(items)
			if type(items) == "table" then
				for _, item in ipairs(items) do
					sessions[#sessions + 1] = item
				end
			end
			finish()
		end)
		if not ok then
			finish()
		end
	end
end

local function check_request()
	local request = tonumber(tern.kv.get("request")) or 0
	if request > 0 then
		tern.kv.set("request", 0)
		refresh_all()
		refresh_contexts()
	end
end

local function state_is_stale(): boolean
	local stored = tern.kv.get("state")
	if type(stored) ~= "table" or type(stored.providers) ~= "table" then
		return true
	end
	if stored.schema ~= STATE_SCHEMA then
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
	local context_last = tonumber(tern.kv.get("context_last")) or 0
	if type(tern.kv.get("context_state")) ~= "table" or os.time() - context_last >= current.interval then
		tern.kv.set("context_last", os.time())
		refresh_contexts()
	end
	check_request()
	tern.timer(TICK_MS, tick)
end

-- ---------------------------------------------------------------------------
-- Detail block

local block_pane: number? = nil
local block_cx: any = nil
local block_seen: number? = nil
local context_seen: number? = nil

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

local STATE_ICON = {
	ok = "check",
	auth = "key",
	signed_out = "lock",
}

local function status_icon(status: string): any
	local label = select(1, status_label(status))
	local icon = STATE_ICON[status] or "warn"
	return tern.ui.el("span", {
		class = "q-state q-state--" .. status,
		title = label,
		attrs = { role = "img", ["aria-label"] = label },
	}, {
		tern.ui.node("icon", { name = icon }),
	})
end

local function icon_button(icon: string, label: string, action: string, class: string): any
	return tern.ui.el("button", {
		class = class,
		title = label,
		attrs = { ["aria-label"] = label },
		actions = { click = action },
	}, {
		tern.ui.node("icon", { name = icon }),
	})
end

local function add_visibility_buttons(actions: { any }, l: string, id: string, view_hidden: boolean, status_hidden: boolean)
	actions[#actions + 1] = icon_button(
		"grid",
		i18n.t(l, view_hidden and "show_overview" or "hide_overview"),
		(view_hidden and "show_view=" or "hide_view=") .. id,
		"q-choice q-icon-choice" .. (view_hidden and " q-icon-choice--quiet" or " q-icon-choice--primary")
	)
	actions[#actions + 1] = icon_button(
		"gauge",
		i18n.t(l, status_hidden and "show_status" or "hide_status"),
		(status_hidden and "show_status=" or "hide_status=") .. id,
		"q-choice q-icon-choice" .. (status_hidden and " q-icon-choice--quiet" or " q-icon-choice--primary")
	)
end

local function provider_control(item: any, id: string, l: string, auto: boolean): any
	if not auto and item.status ~= "ok" then
		local setup_label = id == "deepseek" and i18n.t(l, "set_key") or i18n.t(l, "sign_in")
		local setup_icon = id == "deepseek" and "key" or "log-in"
		local tone = item.status == "signed_out" and "q-icon-choice--primary" or "q-icon-choice--danger"
		local label = setup_label
		if item.status == "auth" then
			label = i18n.t(l, "auth") .. " · " .. setup_label
		elseif item.status ~= "signed_out" then
			label = i18n.t(l, "unavailable") .. " · " .. setup_label
		end
		return icon_button(setup_icon, label, "setup=" .. id, "q-choice q-icon-choice " .. tone)
	end
	return status_icon(item.status)
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

local function history_series(state: any, id: string, limit: number): { any }
	local values = {}
	for _, point in ipairs(type(state) == "table" and state.history or {}) do
		local value = tonumber(point[id])
		if value then
			values[#values + 1] = {
				value = value,
				label = os.date("%H:%M", tonumber(point.t) or 0),
			}
		end
	end
	while #values > limit do
		table.remove(values, 1)
	end
	return values
end

local function provider_card(item: any, collapsed: boolean): any
	local header = tern.ui.el("button", { class = "q-head", actions = { click = "fold=" .. item.id } }, {
		tern.ui.node("icon", { name = item.icon or "puzzle" }),
		tern.ui.text({ tern.ui.span(item.name or item.id or "Provider", "strong") }),
		tern.ui.node("icon", { name = collapsed and "chev-r" or "chev-up" }),
	})
	local children = { header }
	if not collapsed then
		children[#children + 1] = provider_windows(item)
		if type(item.balance) == "string" and item.balance ~= "" then
			children[#children + 1] = tern.ui.text({ tern.ui.span(item.balance, "dim") })
		end
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

local context_section

local function context_provider(session: any): string?
	local provider = type(session) == "table" and session.provider or nil
	if type(provider) ~= "string" and type(session) == "table" and type(session.model) == "string" then
		provider = session.model:match("^([^/]+)/")
	end
	if provider == "opencode-go" then
		provider = "opencode"
	end
	return type(provider) == "string" and provider or nil
end

local function context_icon(session: any): string
	local provider = context_provider(session)
	local state = tern.kv.get("state")
	local item = provider and type(state) == "table" and state.providers and state.providers[provider] or nil
	if type(item) == "table" and type(item.icon) == "string" then
		return item.icon
	end
	return type(session) == "table" and session.icon or "activity"
end

local function filter_entries(state: any, settings_value: { [string]: any }): { any }
	local out, seen = {}, {}
	local function add(id: any, name: any, icon: any)
		if type(id) ~= "string" or id == "" or seen[id] then
			return
		end
		seen[id] = true
		out[#out + 1] = { id = id, name = name or id, icon = icon or "puzzle" }
	end
	for _, id in ipairs(state.order or {}) do
		local item = state.providers and state.providers[id]
		if type(item) == "table" and item.status == "ok" and settings_value.hidden[id] ~= true then
			add(id, item.name, item.icon)
		end
	end
	local context = tern.kv.get("context_state")
	if type(context) == "table" and type(context.sessions) == "table" then
		for _, session in ipairs(context.sessions) do
			local provider = context_provider(session)
			local item = provider and state.providers and state.providers[provider] or nil
			add(
				provider,
				type(item) == "table" and item.name or session.agent or session.provider,
				type(item) == "table" and item.icon or session.icon
			)
		end
	end
	return out
end

local function filter_strip(entries: { any }, selected: string): any
	local l = lang()
	local tiles: { any } = {
		icon_button(
			"grid",
			i18n.t(l, "all"),
			"filter=all",
			"q-choice q-icon-choice" .. (selected == "all" and " q-icon-choice--primary" or "")
		),
	}
	for _, entry in ipairs(entries) do
		tiles[#tiles + 1] = icon_button(
			entry.icon,
			entry.name,
			"filter=" .. entry.id,
			"q-choice q-icon-choice" .. (selected == entry.id and " q-icon-choice--primary" or "")
		)
	end
	return tern.ui.el("div", { class = "q-filter-row" }, tiles)
end

local function main_view(state: any, settings_value: { [string]: any }, block_state: any): any
	local l = lang()
	local entries = filter_entries(state, settings_value)
	local selected = type(block_state) == "table" and block_state.filter or "all"
	if selected ~= "all" then
		local found = false
		for _, entry in ipairs(entries) do
			if entry.id == selected then
				found = true
				break
			end
		end
		if not found then
			selected = "all"
		end
	end
	local nodes: { any } = {}
	if #entries > 0 then
		nodes[#nodes + 1] = filter_strip(entries, selected)
	end
	for _, id in ipairs(state.order or {}) do
		local item = state.providers and state.providers[id]
		if type(item) == "table" and settings_value.hidden[id] ~= true and item.status == "ok"
			and (selected == "all" or id == selected) then
			nodes[#nodes + 1] = provider_card(item, settings_value.collapsed[id] == true)
		end
	end
	local context = context_section(selected, block_state)
	if #nodes == 0 and not context then
		nodes[1] = tern.ui.text({ tern.ui.span(i18n.t(l, "no_providers"), "muted") })
	end
	if context then
		nodes[#nodes + 1] = context
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
			local status_hidden = settings_value.hidden_status[id] == true
			local actions: { any } = {}
			local auto = item.source == "magpie"
			add_visibility_buttons(actions, l, id, hidden, status_hidden)
			local name_spans = { tern.ui.span(item.name or id, "strong") }
			if auto then
				name_spans[#name_spans + 1] = tern.ui.span("  " .. i18n.t(l, "auto"), "dim")
			end
			rows[#rows + 1] = tern.ui.el("div", { class = "q-row" }, {
				tern.ui.node("icon", { name = item.icon or "puzzle" }),
				tern.ui.node("text", {
					spans = name_spans,
					basis = 0.30,
					min = { w = 0 },
				}),
				provider_control(item, id, l, auto),
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
		local item = state.providers and state.providers["relay-" .. index]
		local kind_label
		if relay.kind == "newapi" then
			kind_label = i18n.t(l, "new_api")
		elseif relay.kind == "openai" then
			kind_label = i18n.t(l, "openai_billing")
		else
			kind_label = i18n.t(l, "auto")
		end
		local relay_id = "relay-" .. index
		local actions: { any } = {}
		add_visibility_buttons(
			actions,
			l,
			relay_id,
			settings_value.hidden[relay_id] == true,
			settings_value.hidden_status[relay_id] == true
		)
		actions[#actions + 1] = icon_button(
			"trash",
			i18n.t(l, "remove"),
			"remove_relay=" .. index,
			"q-choice q-icon-choice q-icon-choice--danger"
		)
		local children: { any } = {
			tern.ui.el("div", { class = "q-row q-status-row" }, {
				tern.ui.node("icon", { name = "globe" }),
				tern.ui.node("text", {
					spans = { tern.ui.span(relay.name or ("Relay " .. index), "strong") },
					basis = 0.24,
					min = { w = 0 },
				}),
				tern.ui.badge(kind_label, "muted"),
				tern.ui.node("text", {
					spans = { tern.ui.span(relay.base or "", "dim") },
					grow = 1,
					min = { w = 0 },
				}),
				status_icon(type(item) == "table" and item.status or "error"),
				tern.ui.el("div", { class = "q-choices" }, actions),
			}),
		}
		if type(item) == "table" and item.status ~= "ok" and item.error then
			children[#children + 1] = tern.ui.text({ tern.ui.span(item.error, "dim") })
		end
		custom_rows[#custom_rows + 1] = tern.ui.node("col", { gap = "xs" }, children)
	end
	if #custom_rows == 0 then
		custom_rows[1] = tern.ui.text({ tern.ui.span(i18n.t(l, "no_relays"), "dim") })
	end
	return tern.ui.col({ tern.ui.node("col", { gap = "md", role = "quota-page" }, {
		tern.ui.text({ tern.ui.span(i18n.t(l, "providers"), "strong") }),
		tern.ui.text({ tern.ui.span(i18n.t(l, "hide_hint"), "dim") }),
		tern.ui.node("col", { gap = "xs" }, rows),
		tern.ui.rule(""),
		tern.ui.text({ tern.ui.span(i18n.t(l, "custom"), "strong") }),
		tern.ui.text({ tern.ui.span(i18n.t(l, "custom_hint"), "dim") }),
		tern.ui.el("div", { class = "q-choices" }, {
			icon_button(
				"plus",
				i18n.t(l, "add_custom"),
				"add_relay=auto",
				"q-choice q-icon-choice q-icon-choice--primary"
			),
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
	local name_options: { any } = {}
	for _, option in ipairs({
		{ "short", i18n.t(l, "short_names") },
		{ "full", i18n.t(l, "full_names") },
		{ "none", i18n.t(l, "hidden_names") },
	}) do
		local value, label = option[1], option[2]
		name_options[#name_options + 1] = tern.ui.el("button", {
			class = "q-choice" .. (sf.names == value and " q-choice--on" or ""),
			text = label,
			actions = { click = "status_names=" .. value },
		})
	end
	local toggles: { any } = {}
	for _, option in ipairs({
		{ "window", i18n.t(l, "window") },
		{ "reset", i18n.t(l, "reset") },
		{ "percent", i18n.t(l, "percent") },
		{ "icon", i18n.t(l, "icon") },
		{ "net", i18n.t(l, "speed") },
	}) do
		local key, label = option[1], option[2]
		toggles[#toggles + 1] = tern.ui.el("button", {
			class = "q-choice" .. (sf[key] and " q-choice--on" or ""),
			text = label,
			actions = { click = "status_toggle=" .. key },
		})
	end
	local COLOR_OPTIONS = {
		{ "success", i18n.t(l, "green") },
		{ "error", i18n.t(l, "red") },
		{ "warning", i18n.t(l, "yellow") },
		{ "info", i18n.t(l, "blue") },
		{ "accent", i18n.t(l, "orange") },
		{ "muted", i18n.t(l, "gray") },
		{ "neutral", i18n.t(l, "white") },
	}
	local down_colors: { any } = {}
	local up_colors: { any } = {}
	for _, option in ipairs(COLOR_OPTIONS) do
		local tone, label = option[1], option[2]
		down_colors[#down_colors + 1] = tern.ui.el("button", {
			class = "q-choice" .. (sf.net_down == tone and " q-choice--on" or ""),
			text = label,
			actions = { click = "status_net_down=" .. tone },
		})
		up_colors[#up_colors + 1] = tern.ui.el("button", {
			class = "q-choice" .. (sf.net_up == tone and " q-choice--on" or ""),
			text = label,
			actions = { click = "status_net_up=" .. tone },
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
			tern.ui.text({ tern.ui.span(i18n.t(l, "status_names"), "muted") }),
			tern.ui.el("div", { class = "q-choices" }, name_options),
		}),
		tern.ui.el("div", { class = "q-setting" }, {
			tern.ui.text({ tern.ui.span(i18n.t(l, "status_show"), "muted") }),
			tern.ui.el("div", { class = "q-choices" }, toggles),
		}),
		tern.ui.el("div", { class = "q-setting" }, {
			tern.ui.text({ tern.ui.span(i18n.t(l, "down_color"), "muted") }),
			tern.ui.el("div", { class = "q-choices" }, down_colors),
		}),
		tern.ui.el("div", { class = "q-setting" }, {
			tern.ui.text({ tern.ui.span(i18n.t(l, "up_color"), "muted") }),
			tern.ui.el("div", { class = "q-choices" }, up_colors),
		}),
	}) })
end

local function compact_tokens(value: number): string
	if value >= 1_000_000 then
		return string.format("%.1fM", value / 1_000_000)
	elseif value >= 1_000 then
		return string.format("%.0fK", value / 1_000)
	end
	return string.format("%.0f", value)
end

local function context_ago(iso: any): string
	local target
	if type(iso) == "number" then
		target = iso > 1_000_000_000_000 and iso / 1000 or iso
	elseif type(iso) == "string" then
		local y, mo, d, h, mi, s = iso:match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):?(%d*)")
		if not y then
			return ""
		end
		local utc = os.date("!*t")
		local now_utc = os.time({
			year = utc.year, month = utc.month, day = utc.day,
			hour = utc.hour, min = utc.min, sec = utc.sec,
		})
		local then_utc = os.time({
			year = tonumber(y), month = tonumber(mo), day = tonumber(d),
			hour = tonumber(h), min = tonumber(mi), sec = tonumber(s) or 0,
		})
		target = os.time() - (now_utc - then_utc)
	else
		return ""
	end
	local secs = math.max(0, os.time() - target)
	if secs < 60 then
		return "now"
	elseif secs < 3600 then
		return string.format("%dm", secs // 60)
	elseif secs < 86400 then
		return string.format("%dh", secs // 3600)
	end
	return string.format("%dd", secs // 86400)
end

local function model_label(model: any): string?
	if type(model) ~= "string" or model == "" then
		return nil
	end
	local name = model:gsub("^.*/", ""):gsub("%s+@.*$", "")
	return name ~= "" and name or model
end

context_section = function(selected: string?, block_state: any): any?
	local l = lang()
	local stored = tern.kv.get("context_state")
	local sessions = type(stored) == "table" and stored.sessions or nil
	if type(sessions) ~= "table" or #sessions == 0 then
		return nil
	end
	local open_map = type(block_state) == "table" and type(block_state.context_open) == "table"
		and block_state.context_open or {}
	local cards: { any } = {}
	for index, session in ipairs(sessions) do
		if selected and selected ~= "all" and context_provider(session) ~= selected then
			continue
		end
		local used = tonumber(session.used) or 0
		local window = tonumber(session.window)
		local percent = window and window > 0 and math.max(0, math.min(100, used / window * 100)) or nil
		local label = session.agent or "Agent"
		if type(session.project) == "string" and session.project ~= "" then
			label = label .. " · " .. session.project
		end
		local open = open_map[index] == true
		local children: { any } = {
			tern.ui.el("div", { class = "q-row" }, {
				tern.ui.node("icon", { name = context_icon(session) }),
				tern.ui.node("text", {
					spans = { tern.ui.span(label, "strong") },
					grow = 1,
					min = { w = 0 },
				}),
				tern.ui.badge(model_label(session.model) or i18n.t(l, "context_unknown_model"), "muted"),
				tern.ui.node("icon", { name = open and "chev-up" or "chev-r" }),
			}),
		}
		local values: { any } = {
			tern.ui.node("text", {
				spans = { tern.ui.span(i18n.t(l, "context"), "muted") },
				basis = 0.20,
				min = { w = 0 },
			}),
			tern.ui.node("text", {
				spans = {
					tern.ui.span(
						window and (compact_tokens(used) .. " / " .. compact_tokens(window))
							or (compact_tokens(used) .. " " .. i18n.t(l, "context_tokens")),
						"num"
					),
				},
				basis = 0.30,
				min = { w = 0 },
			}),
		}
		if percent then
			values[#values + 1] = tern.ui.node("progress", {
				value = percent / 100,
				tone = percent >= 80 and "error" or (percent >= 60 and "warn" or nil),
				grow = 1,
			})
			values[#values + 1] = tern.ui.node("text", {
				spans = { tern.ui.span(string.format("%.0f%%", percent), "num") },
				basis = 0.10,
				min = { w = 0 },
			})
		end
		values[#values + 1] = tern.ui.node("text", {
			spans = { tern.ui.span(context_ago(session.at), "dim") },
			basis = 0.12,
			min = { w = 0 },
		})
		children[#children + 1] = tern.ui.el("div", { class = "q-row" }, values)
		if open then
			local details = {
				{ i18n.t(l, "context_provider"), context_provider(session) or "—" },
				{ i18n.t(l, "context_model"), tostring(session.model or "—") },
				{ i18n.t(l, "context_used"), compact_tokens(used) .. " " .. i18n.t(l, "context_tokens") },
				{ i18n.t(l, "context_window"), window and compact_tokens(window) or "—" },
				{ i18n.t(l, "context_remaining"), percent and string.format("%.0f%%", 100 - percent) or "—" },
				{ i18n.t(l, "context_updated"), tostring(session.at or "—") },
				{ i18n.t(l, "context_session"), tostring(session.path or "—") },
			}
			for _, row in ipairs(details) do
				children[#children + 1] = tern.ui.el("div", { class = "q-row" }, {
					tern.ui.node("text", {
						spans = { tern.ui.span(row[1], "muted") },
						basis = 0.24,
						min = { w = 0 },
					}),
					tern.ui.node("text", {
						spans = { tern.ui.span(row[2], "dim") },
						grow = 1,
						min = { w = 0 },
					}),
				})
			end
			local context_series = {}
			for _, point in ipairs(session.history or {}) do
				if type(point.used) == "number" then
					context_series[#context_series + 1] = {
						value = point.used,
						label = context_ago(point.at),
					}
				end
			end
			if #context_series > 1 then
				children[#children + 1] = tern.ui.node("chart", {
					kind = "spark",
					token = "accent",
					series = context_series,
					summary = i18n.t(l, "context_history") .. " · " .. #context_series,
				})
			end
			local provider = context_provider(session)
			local remaining = provider and history_series(tern.kv.get("state"), provider, 48) or {}
			if #remaining > 1 then
				children[#children + 1] = tern.ui.node("chart", {
					kind = "spark",
					token = "success",
					series = remaining,
					summary = i18n.t(l, "history_remaining") .. " · " .. #remaining,
				})
			end
		end
		cards[#cards + 1] = tern.ui.el("div", {
			class = "q-card q-card--clickable",
			actions = { click = "context_toggle=" .. index },
		}, children)
	end
	if #cards == 0 then
		return nil
	end
	local body = {
		tern.ui.text({ tern.ui.span(i18n.t(l, "context"), "strong") }),
		tern.ui.text({ tern.ui.span(i18n.t(l, "context_hint"), "dim") }),
	}
	for _, card in ipairs(cards) do
		body[#body + 1] = card
	end
	return tern.ui.node("col", { gap = "md" }, body)
end

local function block_view(block_state: any): any
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
	local page
	if type(state_value) ~= "table" then
		page = tern.ui.col({ tern.ui.progress(nil, "Loading quota…") })
	elseif block_view_name == "providers" then
		page = providers_view(state_value, settings_value)
	elseif block_view_name == "settings" then
		page = settings_view(state_value, settings_value)
	else
		page = main_view(state_value, settings_value, block_state)
	end
	return { main = page, dock = dock }
end

tern.block.define("detail", {
	init = function(cx: any, _args: { string }, _saved: any): any
		block_pane = cx.pane
		block_cx = cx
		local nav = tern.kv.get("navigate")
		block_view_name = (nav == "providers" and "providers")
			or (nav == "settings" and "settings")
			or "main"
		if nav ~= nil then
			tern.kv.set("navigate", nil)
		end
		return { seen = 0, filter = "all", context_open = {} }
	end,
	view = function(state: any, _cx: any): any
		return block_view(state)
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
	event = function(state: any, ev: any, cx: any)
		if ev.ev ~= "action" or type(ev.act) ~= "string" then
			return
		end
		local current = settings()
		if ev.act == "fold" then
			local id = ev.value
			current.collapsed[id] = not current.collapsed[id]
			tern.kv.set("settings", current)
			cx:render()
		elseif ev.act == "filter" then
			state.filter = ev.value or "all"
			cx:render()
		elseif ev.act == "context_toggle" then
			local index = tonumber(ev.value)
			if index then
				state.context_open = type(state.context_open) == "table" and state.context_open or {}
				state.context_open[index] = not state.context_open[index]
				cx:render()
			end
		elseif ev.act == "view" then
			block_view_name = (ev.value == "providers" and "providers")
				or (ev.value == "settings" and "settings")
				or "main"
			cx:render()
		elseif ev.act == "interval" then
			current.interval = tonumber(ev.value) or 60
			tern.kv.set("settings", current)
			tern.kv.set("request", 1)
			cx:render()
		elseif ev.act == "hide_view" then
			current.hidden[ev.value] = true
			tern.kv.set("settings", current)
			cx:render()
		elseif ev.act == "show_view" then
			current.hidden[ev.value] = nil
			tern.kv.set("settings", current)
			cx:render()
		elseif ev.act == "hide_status" then
			current.hidden_status[ev.value] = true
			tern.kv.set("settings", current)
			cx:render()
		elseif ev.act == "show_status" then
			current.hidden_status[ev.value] = nil
			tern.kv.set("settings", current)
			cx:render()
		elseif ev.act == "lang" then
			current.lang = ev.value
			tern.kv.set("settings", current)
			cx:render()
		elseif ev.act == "setup" then
			tern.kv.set("ui_action", "setup:" .. ev.value)
		elseif ev.act == "add_relay" then
			tern.kv.set("ui_action", "add_relay=" .. (ev.value or "auto"))
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
		elseif ev.act == "status_names" then
			current.status_format.names = ev.value == "full" and "full"
				or (ev.value == "none" and "none" or "short")
			tern.kv.set("settings", current)
			cx:render()
		elseif ev.act == "status_toggle" then
			local key = ev.value
			if key == "window" or key == "reset" or key == "percent" or key == "net" or key == "icon" then
				current.status_format[key] = not current.status_format[key]
				tern.kv.set("settings", current)
				cx:render()
			end
		elseif ev.act == "status_net_down" or ev.act == "status_net_up" then
			local key = ev.act == "status_net_up" and "net_up" or "net_down"
			local tones = { success = true, error = true, warning = true, info = true, accent = true, muted = true, neutral = true }
			if tones[ev.value] then
				current.status_format[key] = ev.value
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
				block_view_name = (nav == "providers" and "providers")
					or (nav == "settings" and "settings")
					or "main"
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
			local context_state = tern.kv.get("context_state")
			local context_updated = type(context_state) == "table" and context_state.updated or 0
			if context_updated ~= context_seen then
				context_seen = context_updated
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
