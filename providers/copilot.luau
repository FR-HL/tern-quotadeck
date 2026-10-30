-- GitHub Copilot: a GitHub token from the Copilot CLI's hosts.json, or the
-- GitHub CLI's own login, then Copilot's internal user endpoint.

local util = require("./util")

local provider = {
	id = "copilot",
	name = "GitHub Copilot",
	short = "Copilot",
	icon = "provider-github-copilot",
	windows = {
		{ key = "premium_interactions", label = "Premium requests" },
		{ key = "chat", label = "Chat" },
		{ key = "completions", label = "Completions" },
	},
}

local function hosts_token(): string?
	for _, path in ipairs({
		(tern.getenv("APPDATA") or "") .. "/github-copilot/hosts.json",
		util.home() .. "/.config/github-copilot/hosts.json",
	}) do
		local data = util.read_json(path)
		if type(data) == "table" then
			for _, entry in pairs(data) do
				if type(entry) == "table" and type(entry.oauth_token) == "string" and entry.oauth_token ~= "" then
					return entry.oauth_token
				end
			end
		end
	end
	return nil
end

local HEADERS = {
	["Accept"] = "application/json",
	["Editor-Version"] = "vscode/1.96.2",
	["Editor-Plugin-Version"] = "copilot-chat/0.26.7",
	["User-Agent"] = "GitHubCopilotChat/0.26.7",
	["X-Github-Api-Version"] = "2025-04-01",
}

local function as_number(value: any): number?
	if type(value) == "number" then
		return value
	elseif type(value) == "string" then
		return tonumber(value)
	end
	return nil
end

local function parse(value: any): any
	local snapshots = type(value) == "table" and (value.quota_snapshots or value.quotaSnapshots) or nil
	if type(snapshots) ~= "table" then
		return { status = "error", error = "no quota snapshots" }
	end
	local reset = value.quota_reset_date_utc or value.quota_reset_date
	local windows = {}
	for _, spec in ipairs(provider.windows) do
		local snapshot = snapshots[spec.key]
		if type(snapshot) == "table" and snapshot.unlimited ~= true then
			local remaining = as_number(snapshot.percent_remaining)
			if remaining ~= nil then
				if remaining <= 1 then
					remaining = remaining * 100
				end
				windows[spec.key] = { used = 100 - remaining, resets_at = reset }
			end
		end
	end
	if next(windows) == nil then
		return { status = "error", error = "no usable windows" }
	end
	return { status = "ok", windows = windows, plan = value.copilot_plan }
end

local function fetch_with(token: string, done: (any?) -> ())
	local headers = {}
	for key, value in pairs(HEADERS) do
		headers[key] = value
	end
	headers["Authorization"] = "token " .. token
	util.fetch_json("https://api.github.com/copilot_internal/user", {
		headers = headers,
		timeout_ms = 15_000,
	}, function(value, err, status)
		if err then
			done({ status = (status == 401 or status == 403) and "auth" or "error", error = err })
			return
		end
		done(parse(value))
	end)
end

function provider.fetch(done: (any?) -> ())
	local token = hosts_token()
	if token then
		fetch_with(token, done)
		return
	end
	tern.process.run({ "gh", "auth", "token" }, { timeout_ms = 5_000 }, function(result)
		local fallback = result and result.stdout and result.stdout:gsub("%s+$", "") or ""
		if result and result.status == 0 and fallback ~= "" then
			fetch_with(fallback, done)
		else
			done({ status = "signed_out" })
		end
	end)
end

return provider
