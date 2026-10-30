-- DeepSeek: API-key balance (no percentage windows).

local util = require("./util")

local provider = {
	id = "deepseek",
	name = "DeepSeek",
	short = "DeepSeek",
	icon = "provider-deepseek",
	windows = {},
}

local function key(): string?
	local env = tern.getenv("DEEPSEEK_API_KEY")
	if env and env ~= "" then
		return env
	end
	local settings = tern.kv.get("settings")
	local keys = type(settings) == "table" and settings.keys or nil
	local stored = type(keys) == "table" and keys.deepseek or nil
	if type(stored) == "string" and stored ~= "" then
		return stored
	end
	return nil
end

function provider.detect(): boolean
	return key() ~= nil
end

function provider.fetch(done: (any?) -> ())
	local access = key()
	util.fetch_json("https://api.deepseek.com/user/balance", {
		headers = {
			["Authorization"] = "Bearer " .. access,
			["Accept"] = "application/json",
		},
		timeout_ms = 15_000,
	}, function(value, err, status)
		if err then
			done({ status = (status == 401 or status == 403) and "auth" or "error", error = err })
			return
		end
		local infos = type(value) == "table" and value.balance_infos or nil
		if type(infos) ~= "table" then
			done({ status = "error", error = "invalid response" })
			return
		end
		local first = infos[1]
		if type(first) ~= "table" or first.total_balance == nil then
			done({ status = "error", error = "no balance" })
			return
		end
		local symbol = first.currency == "CNY" and "¥" or (first.currency == "USD" and "$" or (first.currency .. " "))
		done({ status = "ok", balance = symbol .. tostring(first.total_balance) })
	end)
end

return provider
