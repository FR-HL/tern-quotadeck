-- Codex records token_count events with the prompt size and context window.

local util = require("./util")

local adapter = {
	api = 1,
	id = "codex",
	name = "Codex",
	icon = "app-codex",
}

function adapter.fetch(done: (any) -> ())
	util.recent(util.home() .. "/.codex/sessions", 8, function(files)
		local out = {}
		for _, file in ipairs(files) do
			local used, window, model, at
			for line in file.tail:gmatch("[^\r\n]+") do
				local value = util.decode(line)
				local payload = type(value) == "table" and value.payload or nil
				if type(payload) == "table" and payload.type == "turn_context" and type(payload.model) == "string" then
					model = payload.model
				end
				if type(payload) == "table" and payload.type == "token_count" then
					local info = payload.info
					local last = type(info) == "table" and info.last_token_usage or nil
					if type(last) == "table" and type(last.input_tokens) == "number" then
						used = last.input_tokens
						window = tonumber(info.model_context_window)
						at = value.timestamp
					end
				end
			end
			if used then
				local cwd = util.cwd_of(file.head) or util.cwd_of(file.tail)
				model = model or (file.head and file.head:match('"model"%s*:%s*"([^"]+)"'))
					or (file.tail and file.tail:match('"model"%s*:%s*"([^"]+)"'))
				out[#out + 1] = {
					agent = adapter.name,
					icon = adapter.icon,
					provider = "codex",
					project = util.project_of(cwd) or util.project_from_path(file.path),
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
