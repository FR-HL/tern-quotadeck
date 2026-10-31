-- Shared helpers for context adapters. Each adapter reads its agent's own
-- session log; nothing here depends on a proxy or a vendor quota endpoint.

local util = {}

function util.home(): string
	return tern.getenv("USERPROFILE") or tern.getenv("HOME") or ""
end

-- Returns the newest *.jsonl under root and its last lines.
function util.latest(root: string, done: (string?, string?, string?) -> ())
	local command
	if tern.runtime.os == "windows" then
		local quoted = root:gsub("'", "''")
		command = {
			"powershell",
			"-NoProfile",
			"-Command",
			"$f = Get-ChildItem -LiteralPath '" .. quoted .. "' -Recurse -Filter *.jsonl -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1; if ($f) { Write-Output ('__FILE__' + $f.FullName); Write-Output ('__HEAD__' + (Get-Content -LiteralPath $f.FullName -TotalCount 1)); Get-Content -LiteralPath $f.FullName -Tail 80 }",
		}
	else
		command = {
			"sh",
			"-c",
			'f=$(find "$1" -type f -name "*.jsonl" -exec ls -t {} + 2>/dev/null | head -1); [ -n "$f" ] && { echo "__FILE__$f"; echo "__HEAD__$(head -n 1 "$f")"; tail -n 80 "$f"; }',
			"sh",
			root,
		}
	end
	tern.process.run(command, { timeout_ms = 10_000 }, function(result)
		if not result or result.status ~= 0 or type(result.stdout) ~= "string" then
			done(nil, nil)
			return
		end
		local path, head
		local lines = {}
		for line in result.stdout:gmatch("[^\r\n]+") do
			if not path and line:sub(1, 8) == "__FILE__" then
				path = line:sub(9)
			elseif path and not head and line:sub(1, 8) == "__HEAD__" then
				head = line:sub(9)
			elseif path then
				lines[#lines + 1] = line
			end
		end
		if not path then
			done(nil, nil)
			return
		end
		done(path, table.concat(lines, "\n"), head)
	end)
end

function util.first(path: string): string?
	local ok, text = pcall(tern.fs.read, path, 65_536)
	if ok and type(text) == "string" then
		return text
	end
	return nil
end

function util.cwd_of(text: string?): string?
	if type(text) ~= "string" then
		return nil
	end
	for line in text:gmatch("[^\r\n]+") do
		local ok, value = pcall(tern.json.decode, line)
		if ok and type(value) == "table" and type(value.cwd) == "string" then
			return value.cwd
		end
	end
	local cwd = text:match('"cwd"%s*:%s*"([^"]+)"')
	if cwd then
		return (cwd:gsub("\\\\", "\\"):gsub("\\/", "/"))
	end
	return nil
end

function util.project_of(cwd: string?): string?
	if type(cwd) ~= "string" or cwd == "" then
		return nil
	end
	local name = cwd:match("([^/\\]+)[/\\]*$")
	return name or cwd
end

function util.project_from_path(path: string?): string?
	if type(path) ~= "string" then
		return nil
	end
	local dir = path:match("([^/\\]+)[/\\][^/\\]+$")
	if not dir then
		return nil
	end
	dir = dir:gsub("^%-%-", ""):gsub("%-%-$", "")
	dir = dir:gsub("^(%a)%-%-", "%1:\\"):gsub("%-", "\\")
	return dir:match("([^/\\]+)$") or dir
end

function util.decode(line: string): any?
	local ok, value = pcall(tern.json.decode, line)
	if ok and type(value) == "table" then
		return value
	end
	return nil
end

function util.compact(value: number): string
	if value >= 1_000_000 then
		return string.format("%.1fM", value / 1_000_000)
	elseif value >= 1_000 then
		return string.format("%.0fK", value / 1_000)
	end
	return string.format("%.0f", value)
end

return util
