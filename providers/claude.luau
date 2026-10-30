-- Claude Code: the CLI's OAuth login, then Anthropic's usage endpoint.

local util = require("./util")

local provider = {
	id = "claude",
	name = "Claude",
	short = "Claude",
	icon = "provider-anthropic",
	windows = {
		{ key = "five_hour", label = "5 hours" },
		{ key = "seven_day", label = "7 days" },
	},
}

local function credential_path(): string
	return util.home() .. "/.claude/.credentials.json"
end

function provider.detect(): boolean
	local cred = util.read_json(credential_path())
	local oauth = type(cred) == "table" and cred.claudeAiOauth or nil
	return type(oauth) == "table" and type(oauth.accessToken) == "string" and oauth.accessToken ~= ""
end

function provider.fetch(done: (any?) -> ())
	local cred = util.read_json(credential_path())
	local oauth = type(cred) == "table" and cred.claudeAiOauth or nil
	local token = type(oauth) == "table" and oauth.accessToken or nil
	util.fetch_json("https://api.anthropic.com/api/oauth/usage", {
		headers = {
			["Authorization"] = "Bearer " .. token,
			["anthropic-beta"] = "oauth-2025-04-20",
			["User-Agent"] = "claude-code/2.1.0",
		},
		timeout_ms = 15_000,
	}, function(value, err, status)
		if err then
			done({ status = (status == 401 or status == 403) and "auth" or "error", error = err })
			return
		end
		local windows = {}
		for _, spec in ipairs(provider.windows) do
			local window = value and value[spec.key]
			if type(window) == "table" then
				local used = window.utilization
				if type(used) ~= "number" then
					used = window.used_percentage
				end
				if type(used) == "number" then
					windows[spec.key] = { used = used, resets_at = window.resets_at }
				end
			end
		end
		if next(windows) == nil then
			done({ status = "error", error = "invalid response" })
		else
			done({ status = "ok", windows = windows })
		end
	end)
end

return provider
