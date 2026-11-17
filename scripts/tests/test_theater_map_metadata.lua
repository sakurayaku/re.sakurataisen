local codec = dofile(LUDARED.SCRIPTS .. "/theater_map_metadata.lua")
local constants = dofile(LUDARED.SCRIPTS .. "/shared/constants.lua")
local graphics = dofile(LUDARED.SCRIPTS .. "/theater_map_gfx.lua")

local TMP = "/tmp/ludared_theater_map_metadata_test"
local SOURCE = TMP .. "/SakTaiCD1_Track1.bin/SAKURA1"
os.execute("mkdir -p '" .. SOURCE .. "/TMAPSP.BIN' '" .. SOURCE .. "/FUKAGAWA.BIN'")

local function write_bmp(path, width, height)
  local header = string.pack("<c2I4I2I2I4I4i4i4I2I2I4I4I4I4I4I4",
    "BM", 54, 0, 0, 54, 40, width, height, 1, 4, 0, 0, 0, 0, 0, 0)
  local file = assert(io.open(path, "wb"))
  file:write(header)
  file:close()
end

local function put(data, offset, value)
  return data:sub(1, offset) .. value .. data:sub(offset + #value + 1)
end

local function record(width_tiles, height)
  return string.pack(">I2BBBBBB", 0x1234, 0xAA, 0xBB,
    width_tiles, height, 0xCC, 0xDD)
end

local function dimensions(data, offset)
  return data:byte(offset + 5), data:byte(offset + 6)
end

local function address(data, offset)
  return string.unpack(">I2", data, offset + 1)
end

local function packed_offset(layout, index, resized_index, resized_tiles, resized_height)
  local bytes = 0
  for i = 1, index do
    local record = layout[i]
    local tiles, height = record[2], record[3]
    if i - 1 == resized_index then tiles, height = resized_tiles, resized_height end
    bytes = bytes + tiles * 8 * height // 2
  end
  return bytes // 8
end

write_bmp(SOURCE .. "/TMAPSP.BIN/50.bmp", 88, 24)
write_bmp(SOURCE .. "/FUKAGAWA.BIN/50.bmp", 40, 24)

local old_workspace = LUDARED.WORKSPACE
local old_sha256 = LUDARED.sha256
LUDARED.WORKSPACE = TMP
LUDARED.sha256 = function(data)
  if #data == constants.CD1_SAKURA_BYTES then return constants.CD1_SAKURA_SHA256 end
  if #data == constants.CD2_SAKURA_BYTES then return constants.CD2_SAKURA_SHA256 end
  return old_sha256(data)
end

local tmap_cd1 = 0x1EBF4 + 50 * 8
local unchanged_tmap = 0x1EBF4 + 49 * 8
local fukagawa_cd1 = 0x20760 + 50 * 8
local tmap_cd2 = 0x1EC0C + 50 * 8
local original = string.rep("\0", constants.CD1_SAKURA_BYTES)
original = put(original, unchanged_tmap,
  record(graphics.image_layouts.TMAPSP[50][2], graphics.image_layouts.TMAPSP[50][3]))
original = put(original, tmap_cd1, record(7, 24))
original = put(original, fukagawa_cd1, record(7, 24))
local output = codec.encode(original, {})

assert(#output == #original)
local width, height = dimensions(output, tmap_cd1)
assert(width == 11 and height == 24)
assert(address(output, tmap_cd1) == graphics.image_layouts.TMAPSP[51][1])
assert(output:sub(tmap_cd1 + 7, tmap_cd1 + 8) == original:sub(tmap_cd1 + 7, tmap_cd1 + 8))
local missing_tmap = 0x1EBF4 + 49 * 8
assert(output:sub(missing_tmap + 1, missing_tmap + 8)
  == original:sub(missing_tmap + 1, missing_tmap + 8))
width, height = dimensions(output, fukagawa_cd1)
assert(width == 5 and height == 24)
assert(address(output, fukagawa_cd1) == packed_offset(
  graphics.image_layouts.FUKAGAWA, 50, 50, 5, 24))
assert(address(output, fukagawa_cd1 + 8) == packed_offset(
  graphics.image_layouts.FUKAGAWA, 51, 50, 5, 24))

local cd2 = string.rep("\0", constants.CD2_SAKURA_BYTES)
cd2 = put(cd2, tmap_cd2, record(7, 24))
cd2 = put(cd2, tmap_cd2 - 0x18,
  record(graphics.image_layouts.TMAPSP[51][2], graphics.image_layouts.TMAPSP[51][3]))
local cd2_output = codec.encode(cd2, {})
width, height = dimensions(cd2_output, tmap_cd2)
assert(width == 11 and height == 24)
assert(address(cd2_output, tmap_cd2) == graphics.image_layouts.TMAPSP[51][1])
width, height = dimensions(cd2_output, tmap_cd2 - 0x18)
assert(width == 9 and height == 24)

LUDARED.WORKSPACE = old_workspace
LUDARED.sha256 = old_sha256
print("theater_map_metadata.lua checks passed")
