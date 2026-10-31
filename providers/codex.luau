-- Codex: the CLI's ChatGPT OAuth login, then the (undocumented) WHAM usage
-- endpoint. Its schema has changed before, so every field is optional and a
-- parse failure surfaces as an ordinary error instead of a wrong bar.

local util = require("./util")

local provider = {
	id = "codex",
	name = "Codex",
	short = "CX",
	icon = "provider-openai-codex",
	windows = {
		{ key = "five_hour", label = "5 hours" },
		{ key = "weekly", label = "7 days" },
	},
}

local function auth_path(): string
	return util.home() .. "/.codex/auth.json"
end

local function tokens(): any?
	local auth = util.read_json(auth_path())
	return type(auth) == "table" and auth.tokens or nil
end

function provider.detect(): boolean
	local t = tokens()
	return type(t) == "table" and type(t.access_token) == "string" and t.access_token ~= ""
end

local function window_key(field: string, window: any): string
	local seconds = type(window) == "table" and window.limit_window_seconds or nil
	if type(seconds) == "number" then
		return seconds >= 172_800 and "weekly" or "five_hour"
	end
	if field == "weekly" or field == "secondary_window" then
		return "weekly"
	end
	return "five_hour"
end

function provider.fetch(done: (any?) -> ())
	local t = tokens()
	if type(t) ~= "table" then
		done({ status = "signed_out" })
		return
	end
	local account = type(t.account_id) == "string" and t.account_id or nil
	local headers = {
		["Authorization"] = "Bearer " .. t.access_token,
		["Accept"] = "application/json",
		["Origin"] = "https://chatgpt.com",
		["Referer"] = "https://chatgpt.com/",
		["User-Agent"] = "Mozilla/5.0",
	}
	if account then
		headers["ChatGPT-Account-Id"] = account
	end
	util.fetch_json("https://chatgpt.com/backend-api/wham/usage", {
		headers = headers,
		timeout_ms = 15_000,
	}, function(value, err, status)
		if err then
			done({ status = (status == 401 or status == 403) and "auth" or "error", error = err })
			return
		end
		local limit = type(value) == "table" and (value.rate_limit or value.rate_limits) or nil
		if type(limit) ~= "table" then
			done({ status = "error", error = "no rate-limit windows" })
			return
		end
		local windows = {}
		for _, field in ipairs({ "five_hour", "weekly", "primary_window", "secondary_window" }) do
			local window = limit[field]
			if type(window) == "table" then
				local used = window.used_percent or window.percent_used
				if type(used) ~= "number" and type(window.percent_left) == "number" then
					used = 100 - window.percent_left
				end
				if type(used) == "number" then
					local key = window_key(field, window)
					windows[key] = {
						used = used,
						resets_at = util.from_epoch_ms(window.reset_time_ms) or window.reset_at,
					}
				end
			end
		end
		if next(windows) == nil then
			done({ status = "error", error = "no usable windows" })
		else
			done({ status = "ok", windows = windows, plan = value.plan_type })
		end
	end)
end

return provider
