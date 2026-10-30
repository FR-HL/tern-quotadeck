-- Cursor: the desktop/CLI login token, then Cursor's dashboard usage call.

local util = require("./util")

local provider = {
	id = "cursor",
	name = "Cursor",
	short = "Cursor",
	icon = "provider-cursor",
	windows = {
		{ key = "included", label = "Included" },
		{ key = "api", label = "API" },
	},
}

local function token(): string?
	for _, path in ipairs({
		(tern.getenv("APPDATA") or "") .. "/Cursor/auth.json",
		util.home() .. "/.cursor/auth.json",
	}) do
		local data = util.read_json(path)
		if type(data) == "table" and type(data.accessToken) == "string" and data.accessToken ~= "" then
			return data.accessToken
		end
	end
	return nil
end

function provider.detect(): boolean
	return token() ~= nil
end

local function post(path: string, access: string, done: (any?, string?, number?) -> ())
	util.fetch_json("https://api2.cursor.sh/aiserver.v1.DashboardService/" .. path, {
		method = "POST",
		headers = {
			["Authorization"] = "Bearer " .. access,
			["Content-Type"] = "application/json",
			["Connect-Protocol-Version"] = "1",
			["Accept"] = "application/json",
			["User-Agent"] = "tern-quota",
		},
		body = "{}",
		timeout_ms = 15_000,
	}, done)
end

function provider.fetch(done: (any?) -> ())
	local access = token()
	post("GetCurrentPeriodUsage", access, function(value, err, status)
		if err then
			done({ status = (status == 401 or status == 403) and "auth" or "error", error = err })
			return
		end
		local plan = type(value) == "table" and value.planUsage or nil
		if type(plan) ~= "table" then
			done({ status = "error", error = "invalid response" })
			return
		end
		local reset = util.from_epoch_ms(value.billingCycleEnd)
		local windows = {}
		local included = tonumber(plan.totalPercentUsed)
		local api = tonumber(plan.apiPercentUsed)
		if included then
			windows.included = { used = included, resets_at = reset }
		end
		if api then
			windows.api = { used = api, resets_at = reset }
		end
		if next(windows) == nil then
			done({ status = "error", error = "no usage windows" })
			return
		end
		done({ status = "ok", windows = windows })
	end)
end

return provider
