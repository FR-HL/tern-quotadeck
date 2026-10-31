-- omp writes contextSnapshot.promptTokens in its own session log.

local util = require("./util")
local models = require("./models")

local adapter = {
	api = 1,
	id = "omp",
	name = "omp",
	icon = "app-omp",
}

local function windows(): { [string]: number }
	local out = {}
	local ok, text = pcall(tern.fs.read, util.home() .. "/.omp/agent/models.yml", 4_000_000)
	if not ok or type(text) ~= "string" then
		return out
	end
	for window, id in text:gmatch("contextWindow:%s*(%d+)[^\r\n]*[\r\n]+%s*id:%s*([^\r\n]+)") do
		out[id:gsub("%s+$", "")] = tonumber(window)
	end
	for id, window in text:gmatch("id:%s*([^\r\n]+)[^\r\n]*[\r\n]+%s*contextWindow:%s*(%d+)") do
		out[id:gsub("%s+$", "")] = tonumber(window)
	end
	return out
end

function adapter.fetch(done: (any) -> ())
	local known = windows()
	util.recent(util.home() .. "/.omp/agent/sessions", 8, function(files)
		local out = {}
		for _, file in ipairs(files) do
			local used, model, at
			for line in file.tail:gmatch("[^\r\n]+") do
				local value = util.decode(line)
				local message = type(value) == "table" and value.message or nil
				local snapshot = type(message) == "table" and message.contextSnapshot or nil
				if type(snapshot) == "table" and type(snapshot.promptTokens) == "number" then
					used = snapshot.promptTokens
					model = message.model
					at = message.timestamp or value.timestamp
				end
			end
			if used then
				local cwd = util.cwd_of(file.head or file.tail)
				local window = model and (known[model] or models.window(model)) or nil
				local provider = type(model) == "string" and model:match("^([^/]+)/") or "opencode"
				if provider == "opencode-go" then
					provider = "opencode"
				end
				out[#out + 1] = {
					agent = adapter.name,
					icon = adapter.icon,
					provider = provider,
					project = util.project_of(cwd) or util.project_from_path(file.path),
					path = file.path,
					model = model,
					used = used,
					window = window,
					at = at,
				}
			end
		end
		done(out)
	end)
end

return adapter
