-- SakuraYaku dialogue sync (Lua 5.5, curl, no Lua dependencies).
-- Run from Ludared with LUDARED.PROJECT_ROOT and LUDARED.WORKSPACE defined.

local BASE = "https://sakurayaku.dreamleaves.org"
local root = assert(LUDARED and LUDARED.PROJECT_ROOT, "LUDARED.PROJECT_ROOT missing")
local workspace = assert(LUDARED.WORKSPACE, "LUDARED.WORKSPACE missing")
local function join(a, b) return a:gsub("/$", "") .. "/" .. b end
local config_path = join(root, ".sakurayaku.json")

local FILES = {
  ['0100TBL.TXT'] = {
    'SakTaiCD1_Track1.bin/SAKURA1/0100TBL.BIN',
  },
  -- ['M01MES.TXT'] = {
  --   'SakTaiCD1_Track1.bin/SAKURA2/M01MES.BIN',
  -- },
}

local function quote(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function write_atomic(path, content)
  local tmp = path .. ".tmp"
  local f, err = io.open(tmp, "wb")
  assert(f, err)
  local ok, why = f:write(content)
  f:close()
  assert(ok, why)
  assert(os.rename(tmp, path), "Cannot replace " .. path)
  return true
end

local function mkdir(path)
  local ok = os.execute("mkdir -p " .. quote(path))
  assert(ok == true or ok == 0, "Cannot create directory: " .. path)
end
local function json_string(s)
  return '"' .. s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t') .. '"'
end
local function parse_manifest(raw)
  -- Deliberately narrow JSON reader for the API's {"files":{"NAME":[count,ms|null]}} schema.
  -- It is not a general-purpose JSON parser.
  assert(raw:match('^%s*{') and raw:match('"files"%s*:%s*{'), "Unexpected manifest JSON")
  local files = {}
  local n = 0
  for name, count, timestamp in raw:gmatch('"([%w_.%-]+)"%s*:%s*%[%s*(%d+)%s*,%s*(%d+)%s*%]') do
    files[name] = { tonumber(count), tonumber(timestamp) }
    n = n + 1
  end
  for name, count in raw:gmatch('"([%w_.%-]+)"%s*:%s*%[%s*(%d+)%s*,%s*null%s*%]') do
    files[name] = { tonumber(count), false }
    n = n + 1
  end
  -- Reject unexpected file entries rather than silently declaring them synced.
  local body = raw:match('"files"%s*:%s*{(.-)}')
  assert(body, "Missing files object")
  local entries = 0
  for _ in body:gmatch('"[^\"]+"%s*:') do entries = entries + 1 end
  assert(entries == n, "Unsupported or malformed manifest entry")
  return files
end
local function load_config(raw)
  local token = raw:match('"token"%s*:%s*"([%x%-]+)"')
  assert(token and token:match('^[%x]+%-[%x]+%-4[%x]+%-[89aAbB][%x]+%-[%x]+$'), "Invalid local token")
  return { token = token, files = parse_manifest(raw) }
end
local function save_config(cfg)
  local names = {}
  for name in pairs(cfg.files) do names[#names + 1] = name end
  table.sort(names)
  local out = { '{\n  "token": ' .. json_string(cfg.token) .. ',\n  "files": {' }
  for i, name in ipairs(names) do
    local v = cfg.files[name]
    out[#out + 1] = '\n    ' .. json_string(name) .. ': [' .. v[1] .. ', ' .. (v[2] or 'null') .. ']' .. (i < #names and ',' or '')
  end
  out[#out + 1] = '\n  }\n}\n'
  write_atomic(config_path, table.concat(out))
end
local function uuid_v4()
  local f = assert(io.open('/dev/urandom', 'rb'), 'Cannot access /dev/urandom')
  local bytes = assert(f:read(16), 'Cannot read random bytes')
  f:close()
  local b = { bytes:byte(1, 16) }
  b[7] = (b[7] % 16) + 0x40
  b[9] = (b[9] % 64) + 0x80
  local hex = {}
  for i = 1, 16 do hex[i] = string.format('%02x', b[i]) end
  return table.concat(hex, '', 1, 4) .. '-' .. table.concat(hex, '', 5, 6) .. '-' ..
         table.concat(hex, '', 7, 8) .. '-' .. table.concat(hex, '', 9, 10) .. '-' ..
         table.concat(hex, '', 11, 16)
end
local function curl_get(url, token)
  -- Put the secret in a temporary curl config file rather than process arguments.
  local cfg_path = os.tmpname()
  local output_path = os.tmpname()
  local cfg = assert(io.open(cfg_path, 'wb'))
  cfg:write('header = "Authorization: Bearer ', token, '"\n')
  cfg:close()
  os.execute('chmod 600 ' .. quote(cfg_path))
  local command = 'curl --silent --show-error --fail --location --config ' .. quote(cfg_path) ..
                  ' --output ' .. quote(output_path) .. ' ' .. quote(url)
  local ok = os.execute(command)
  os.remove(cfg_path)
  local content = (ok == true or ok == 0) and read(output_path) or nil
  os.remove(output_path)
  return content
end

local raw = read(config_path)
if not raw then
  local cfg = { token = uuid_v4(), files = {} }
  save_config(cfg)
  print('Authorize SakuraYaku in your browser:')
  print(BASE .. '/app/download/authorize/' .. cfg.token)
  print('Then run this script again.')
  return
end
local cfg = load_config(raw)
local remote_raw = curl_get(BASE .. '/api/download/files', cfg.token)
assert(remote_raw, 'Manifest download failed. Check that the token is authorized and curl is installed.')
local remote = parse_manifest(remote_raw)
local changed, failed = 0, 0
local names = {}
for name in pairs(remote) do names[#names + 1] = name end
table.sort(names)
for _, name in ipairs(names) do
  local folders = FILES[name]

  if folders then
    local current, previous = remote[name], cfg.files[name]

    local outdated = not previous
      or previous[1] ~= current[1]
      or previous[2] ~= current[2]

    local targets = {}

    for _, folder in ipairs(folders) do
      local dir = join(workspace, folder)
      local target = join(dir, name)

      targets[#targets + 1] = { dir = dir, path = target }

      if not read(target) then
        outdated = true
      end
    end

    if outdated then
      print('Downloading ' .. name .. '...')

      local content = curl_get(BASE .. '/api/download/files/' .. name, cfg.token)

      if not content then
        io.stderr:write('Failed: ' .. name .. '\n')
        failed = failed + 1
      else
        local success = true

        for _, target in ipairs(targets) do
          mkdir(target.dir)

          if not write_atomic(target.path, content) then
            print('Write atomic failed' .. '\n')
            success = false
            break
          end
        end

        if success then
          cfg.files[name] = current
          save_config(cfg)
          changed = changed + 1
        else
          failed = failed + 1
        end
      end
    end
  end
end
print(string.format('SakuraYaku: %d updated, %d failed.', changed, failed))
assert(failed == 0, 'Some downloads failed')
