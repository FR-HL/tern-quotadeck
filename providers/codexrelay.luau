-- Active custom Codex provider from ~/.codex/config.toml. This is the same
-- file CC Switch/CC GUI write when they activate a relay, so no CC Switch
-- database parsing is needed.

local util = require("./util")

local provider = {
	api = 1,
	id = "codex-relay",
	name = "Codex relay",
	short = "CR",
	icon = "globe",
	windows = {
		{ key = "quota", label = "Quota" },
	},
}

local function ua()
	return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
end

local function short_code(name: string): string
	local initials = name:gsub("[^%w%s]", ""):gsub("(%a)%S*%s*", "%1"):upper()
	if #initials >= 2 then
		return initials
	end
	return name:sub(1, 3):upper()
end

local CREDIT_USD = 0.000002

local function money(value: number): string
	return string.format("$%.2f", value * CREDIT_USD)
end

local function config(): any?
	local path = util.home() .. "/.codex/config.toml"
	local ok, text = pcall(tern.fs.read, path, 1_000_000)
	if not ok or type(text) ~= "string" then
		return nil
	end
	local active = text:match("model_provider%s*=%s*\"([^\"]+)\"")
	if not active then
		return nil
	end
	local escaped = active:gsub("([^%w])", "%%%1")
	local block = text:match("%[model_providers%." .. escaped .. "%]([^%[]*)")
	if not block then
		return nil
	end
	local base = block:match("base_url%s*=%s*\"([^\"]+)\"")
	local key = block:match("experimental_bearer_token%s*=%s*\"([^\"]+)\"")
	local name = block:match("name%s*=%s*\"([^\"]+)\"")
	if not base or not key then
		return nil
	end
	return {
		base = base:gsub("/+$", ""),
		key = key,
		name = name or "Codex relay",
	}
end

function provider.detect(): boolean
	return config() ~= nil
end

function provider.fetch(done: (any?) -> ())
	local cfg = config()
	if not cfg then
		done({ status = "signed_out" })
		return
	end
	local root = cfg.base:gsub("/v1$", "")
	local headers = {
		["Accept"] = "application/json",
		["User-Agent"] = ua(),
		["Authorization"] = "Bearer " .. cfg.key,
	}
	util.fetch_json(root .. "/api/usage/token/", { headers = headers, timeout_ms = 15_000 }, function(value, err, status)
		if err then
			done({
				status = (status == 401 or status == 403) and "auth" or "error",
				error = err,
				name = cfg.name,
				short = short_code(cfg.name),
			})
			return
		end
		local data = type(value) == "table" and value.data or nil
		if type(value) ~= "table" or (value.code ~= true and value.code ~= 0) or type(data) ~= "table" then
			done({
				status = "error",
				error = type(value) == "table" and tostring(value.message or "invalid response") or "invalid response",
				name = cfg.name,
				short = short_code(cfg.name),
			})
			return
		end
		local available = tonumber(data.account_total_available)
			or tonumber(data.total_available)
			or tonumber(type(data.user_quota) == "table" and data.user_quota.total_available)
		local used = tonumber(data.account_total_used)
			or tonumber(data.total_used)
			or tonumber(type(data.user_quota) == "table" and data.user_quota.total_used)
		local granted = tonumber(data.account_total_granted) or tonumber(data.total_granted)
		if used == nil then
			done({ status = "error", error = "no usage total", name = cfg.name, short = short_code(cfg.name) })
			return
		end
		if data.unlimited_quota == true or (granted ~= nil and granted <= 0) then
			local left = available ~= nil and money(available) or nil
			done({
				status = "ok",
				balance = left and (left .. " left · " .. money(used) .. " used") or (money(used) .. " used"),
				balance_left = left,
				balance_used = money(used),
				status_balance = left,
				name = cfg.name,
				short = short_code(cfg.name),
				plan = "Relay",
			})
			return
		end
		if granted == nil or granted <= 0 then
			done({ status = "error", error = "no quota total", name = cfg.name, short = short_code(cfg.name) })
			return
		end
		done({
			status = "ok",
			windows = { quota = { used = math.max(0, math.min(100, used / granted * 100)) } },
			balance = available ~= nil and (money(available) .. " left") or nil,
			balance_left = available ~= nil and money(available) or nil,
			status_balance = available ~= nil and money(available) or nil,
			name = cfg.name,
			short = short_code(cfg.name),
			plan = "Relay",
		})
	end)
end

return provider
