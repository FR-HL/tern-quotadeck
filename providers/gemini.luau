-- Gemini CLI: its OAuth login, then Google Code Assist's quota call.
-- Read-only: the plugin never refreshes or writes the login; if the access
-- token expired, run Gemini CLI once and try again.

local util = require("./util")

local provider = {
	id = "gemini",
	name = "Gemini CLI",
	short = "GM",
	icon = "provider-google-gemini-cli",
	windows = {
		{ key = "quota", label = "Quota" },
	},
}

local function credentials(): any?
	local creds = util.read_json(util.home() .. "/.gemini/oauth_creds.json")
	if type(creds) ~= "table" or type(creds.access_token) ~= "string" or creds.access_token == "" then
		return nil
	end
	local expiry = tonumber(creds.expiry_date)
	if expiry and expiry < os.time() * 1000 then
		return nil
	end
	return creds
end

function provider.detect(): boolean
	return credentials() ~= nil
end

local function post(url: string, body: any, token: string, done: (any?, string?, number?) -> ())
	util.fetch_json(url, {
		method = "POST",
		headers = {
			["Authorization"] = "Bearer " .. token,
			["Content-Type"] = "application/json",
		},
		body = tern.json.encode(body),
		timeout_ms = 15_000,
	}, done)
end

function provider.fetch(done: (any?) -> ())
	local creds = credentials()
	local token = creds.access_token
	post("https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist", {
		metadata = { ideType = "GEMINI_CLI", pluginType = "GEMINI" },
	}, token, function(assist, err, status)
		if err then
			done({ status = (status == 401 or status == 403) and "auth" or "error", error = err })
			return
		end
		local project = type(assist) == "table" and assist.cloudaicompanionProject or creds.quota_project or ""
		post("https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota", { project = project }, token, function(value, quota_err, quota_status)
			if quota_err then
				done({ status = (quota_status == 401 or quota_status == 403) and "auth" or "error", error = quota_err })
				return
			end
			local buckets = type(value) == "table" and value.buckets or nil
			if type(buckets) ~= "table" then
				done({ status = "error", error = "no quota buckets" })
				return
			end
			local best = nil
			for _, bucket in ipairs(buckets) do
				local fraction = type(bucket) == "table" and tonumber(bucket.remainingFraction) or nil
				if fraction and fraction >= 0 and fraction <= 1 then
					if best == nil or fraction < best.fraction then
						best = { fraction = fraction, bucket = bucket }
					end
				end
			end
			if best == nil then
				done({ status = "error", error = "no usable quota bucket" })
				return
			end
			done({
				status = "ok",
				plan = type(assist) == "table" and assist.currentTier and assist.currentTier.name or nil,
				windows = {
					quota = {
						used = 100 - best.fraction * 100,
						resets_at = best.bucket.resetTime,
						label = best.bucket.modelId or "Quota",
					},
				},
			})
		end)
	end)
end

return provider
