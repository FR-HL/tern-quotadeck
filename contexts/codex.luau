-- Codex records token_count events with the prompt size and context window.

local util = require("./util")

local adapter = {
	api = 1,
	id = "codex",
	name = "Codex",
	icon = "app-codex",
}

function adapter.fetch(done: (any) -> ())
	util.latest(util.home() .. "/.codex/sessions", function(path, tail, head)
		if not path or not tail then
			done({})
			return
		end
		local used, window, model, at
		for line in tail:gmatch("[^\r\n]+") do
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
		if not used then
			done({})
			return
		end
		local cwd = util.cwd_of(head) or util.cwd_of(tail)
		model = model or (head and head:match('"model"%s*:%s*"([^"]+)"'))
			or (tail and tail:match('"model"%s*:%s*"([^"]+)"'))
		done({
			{
				agent = adapter.name,
				icon = adapter.icon,
				project = util.project_of(cwd) or util.project_from_path(path),
				model = model,
				used = used,
				window = window,
				at = at,
			},
		})
	end)
end

return adapter
