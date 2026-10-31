-- Magpie's own quota endpoint. It already knows the accounts and plugin
-- providers magpie manages, so the window needs no copy of their credentials.

local util = require("../providers/util")

local source = {
	api = 1,
	id = "magpie",
	url = "http://127.0.0.1:3425/v1/magpie/quotas",
}

local function icon_for(id: string): string
	local known = {
		["opencode-go"] = "provider-opencode",
		["opencode-zen"] = "provider-opencode",
		opendesign = "puzzle",
		claude = "provider-claude",
		codex = "provider-openai",
		gemini = "provider-gemini",
		cursor = "provider-cursor",
		deepseek = "provider-deepseek",
	}
	return known[id] or "globe"
end

local function item_from(entry: any): any?
	if type(entry) ~= "table" or type(entry.provider) ~= "string" or entry.provider == "" then
		return nil
	end
	local windows = {}
	for index, window in ipairs(type(entry.windows) == "table" and entry.windows or {}) do
		if type(window) == "table" and type(window.used) == "number" then
			windows[#windows + 1] = {
				key = "w" .. index,
				label = type(window.name) == "string" and window.name or ("Window " .. index),
				used = window.used,
				resets_at = window.resetsAt,
			}
		end
	end
	return {
		id = entry.provider,
		name = type(entry.name) == "string" and entry.name or entry.provider,
		short = type(entry.name) == "string" and entry.name or entry.provider,
		icon = icon_for(entry.provider),
		status = "ok",
		source = "magpie",
		plan = type(entry.plan) == "string" and entry.plan or nil,
		balance = type(entry.balance) == "string" and entry.balance or nil,
		windows = windows,
	}
end

function source.fetch(done: (any) -> ())
	util.fetch_json(source.url, {
		headers = { ["Accept"] = "application/json" },
		timeout_ms = 4_000,
	}, function(value, err)
		if err or type(value) ~= "table" or type(value.data) ~= "table" then
			-- Keep the last good list across a Magpie restart or a brief
			-- gateway hiccup, so a reload doesn't drop its cards.
			local cached = tern.kv.get("magpie_cache")
			done(type(cached) == "table" and cached or {})
			return
		end
		local items = {}
		for _, entry in ipairs(value.data) do
			local item = item_from(entry)
			if item then
				items[#items + 1] = item
			end
		end
		if #items > 0 then
			tern.kv.set("magpie_cache", items)
		end
		done(items)
	end)
end

return source
