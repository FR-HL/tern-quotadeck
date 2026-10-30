-- OpenCode Go: the CLI's own login file, then its usage endpoint.

local util = require("./util")

local provider = {
	id = "opencode",
	name = "OpenCode Go",
	short = "OC",
	icon = "provider-opencode",
	windows = {
		{ key = "rolling", label = "5 hours" },
		{ key = "weekly", label = "7 days" },
		{ key = "monthly", label = "Monthly" },
	},
}

function provider.detect(): boolean
	local auth = util.read_json(util.data_dir() .. "/opencode/auth.json")
	local entry = type(auth) == "table" and auth["opencode-go"] or nil
	return type(entry) == "table" and type(entry.key) == "string" and entry.key ~= ""
end

function provider.fetch(done: (any?) -> ())
	local auth = util.read_json(util.data_dir() .. "/opencode/auth.json")
	local entry = type(auth) == "table" and auth["opencode-go"] or nil
	local key = type(entry) == "table" and entry.key or nil
	util.fetch_json("https://opencode.ai/zen/go/v1/usage", {
		headers = { ["Authorization"] = "Bearer " .. key, ["Accept"] = "application/json" },
		timeout_ms = 15_000,
	}, function(value, err, status)
		if err then
			done({ status = (status == 401 or status == 403) and "auth" or "error", error = err })
			return
		end
		local usage = value and value.usage
		if type(usage) ~= "table" then
			done({ status = "error", error = "invalid response" })
			return
		end
		local windows = {}
		for _, spec in ipairs(provider.windows) do
			local window = usage[spec.key]
			if type(window) == "table" and type(window.percent) == "number" then
				windows[spec.key] = { used = window.percent, resets_at = window.resetsAt }
			end
		end
		done({ status = "ok", windows = windows })
	end)
end

return provider
