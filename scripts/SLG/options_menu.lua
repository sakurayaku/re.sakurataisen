local shared = assert(loadfile(LUDARED.SCRIPTS .. "/shared/options_menu.lua"))
local codec = shared("slg")
local can_handle = dofile(LUDARED.SCRIPTS .. "/shared/can_handle.lua")
local constants = dofile(LUDARED.SCRIPTS .. "/shared/constants.lua")
local decode_options, encode_options = codec.decode, codec.encode

codec.name = "Sakura Taisen Options Menu Graphics (SLG)"
codec.description = "Patches both SLG options menus from the SAKURA workspace art"
codec.version = 1

function codec.can_handle(data)
  if type(data) ~= "string" or #data ~= constants.CD1_SLG_BYTES then return "no" end
  if can_handle.can_handle_slg(data) == "certain" then return "certain" end
  return pcall(decode_options, data, {}) and "possible" or "no"
end

function codec.decode()
  return {}
end

function codec.encode(original, _, args)
  local artifacts = decode_options(original, args)
  local root = assert(LUDARED.WORKSPACE, "options menu (SLG): LUDARED.WORKSPACE is required")
    .. "/SakTaiCD1_Track1.bin/SAKURA/"

  for _, artifact in ipairs(artifacts) do
    local path = root .. artifact.name
    local file = assert(io.open(path, "rb"), "options menu (SLG): missing " .. path)
    artifact.data = file:read("*a")
    file:close()
  end

  return encode_options(original, artifacts, args)
end

return codec
