-- Patches theater-map image dimensions in the SAKURA LUTs from workspace BMPs.

local can_handle = dofile(LUDARED.SCRIPTS .. "/shared/can_handle.lua")
local constants = dofile(LUDARED.SCRIPTS .. "/shared/constants.lua")
local theater_map = dofile(LUDARED.SCRIPTS .. "/theater_map_gfx.lua")

local codec = {}

codec.name        = "Sakura Taisen Theater Map Metadata"
codec.description = "Patches TMAPSP and FUKAGAWA image dimensions in SAKURA"
codec.version     = 3
codec.kind        = "patch"

local ARCHIVES = {
  { name = "TMAPSP", cd1_offset = 0x1EBF4, cd2_offset = 0x1EC0C },
  { name = "FUKAGAWA", cd1_offset = 0x20760, cd2_offset = 0x20778 },
}
local ENTRY_SIZE = 8

function codec.can_handle(data)
  return can_handle.can_handle_sakura1(data)
end

function codec.decode_name()
  return "theater_map_metadata.bin"
end

function codec.decode()
  return {}
end

local function read_dimensions(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local data = file:read("a")
  file:close()

  if not data or #data < 54 or data:sub(1, 2) ~= "BM" then
    error("theater_map_metadata: unreadable BMP " .. path, 0)
  end
  local dib_size = string.unpack("<I4", data, 15)
  local width, height = string.unpack("<i4i4", data, 19)
  if dib_size < 40 or dib_size > #data - 14 or width <= 0 or height == 0 then
    error("theater_map_metadata: invalid BMP dimensions in " .. path, 0)
  end

  height = math.abs(height)
  if width % 8 ~= 0 or width // 8 > 0xFF or height > 0xFF then
    error(string.format(
      "theater_map_metadata: %s is %dx%d; LUT dimensions require width in 8-pixel tiles and byte-sized fields",
      path, width, height), 0)
  end
  return width // 8, height
end

function codec.encode(original, artifacts)
  if type(original) ~= "string" then
    error("theater_map_metadata: expected binary string for original", 0)
  end
  -- Earlier SAKURA patch codecs may already have changed bytes, so encode
  -- selects the disc by its unchanged retail file length.
  local disc = #original == constants.CD1_SAKURA_BYTES and 1
    or #original == constants.CD2_SAKURA_BYTES and 2
  if not disc then
    error("theater_map_metadata: original is not a supported SAKURA file", 0)
  end
  local workspace = LUDARED and LUDARED.WORKSPACE
  if not workspace then return original end

  local replacements = {}
  for _, archive in ipairs(ARCHIVES) do
    local layout = theater_map.image_layouts[archive.name]
    local table_offset = disc == 1 and archive.cd1_offset or archive.cd2_offset
    local table_end = table_offset + #layout * ENTRY_SIZE
    if table_end > #original then
      error("theater_map_metadata: SAKURA is too short for " .. archive.name .. " LUT", 0)
    end

    local images, resized_from = {}, nil
    for index, record in ipairs(layout) do
      local path = string.format(
        "%s/SakTaiCD1_Track1.bin/SAKURA1/%s.BIN/%02d.bmp",
        workspace, archive.name, index - 1)
      local width_tiles, height = read_dimensions(path)
      width_tiles, height = width_tiles or record[2], height or record[3]
      local image_size = width_tiles * 8 * height // 2
      if image_size % 8 ~= 0 then
        error(string.format(
          "theater_map_metadata: %s image %d packs to %d bytes, not an 8-byte multiple",
          archive.name, index - 1, image_size), 0)
      end
      if width_tiles ~= record[2] or height ~= record[3] then
        resized_from = resized_from or index
      end
      images[index] = { width_tiles = width_tiles, height = height, size = image_size }
    end

    local archive_size = 0
    if resized_from then
      archive_size = layout[resized_from][1] * 8
      for index = resized_from, #images do
        archive_size = archive_size + images[index].size
      end
    end
    if resized_from and archive_size > theater_map.gfx_limits[archive.name] then
      error(string.format(
        "theater_map_metadata: rebuilt %s is %d bytes; per-file limit is %d",
        archive.name, archive_size, theater_map.gfx_limits[archive.name]), 0)
    end

    local cursor = resized_from and layout[resized_from][1] * 8 or 0
    for index, image in ipairs(images) do
      local record_offset = table_offset + (index - 1) * ENTRY_SIZE
      local old = original:sub(record_offset + 1, record_offset + ENTRY_SIZE)
      local address = string.unpack(">I2", old)
      if resized_from and index >= resized_from then address = cursor // 8 end
      if address > 0xFFFF then
        error("theater_map_metadata: image offset exceeds the LUT's 16-bit field", 0)
      end
      local new = string.pack(">I2", address) .. old:sub(3, 4)
        .. string.char(image.width_tiles, image.height) .. old:sub(7, 8)
      if new ~= old then
        replacements[#replacements + 1] = { offset = record_offset, data = new }
      end
      if resized_from and index >= resized_from then cursor = cursor + image.size end
    end
  end

  if #replacements == 0 then return original end
  local parts, cursor = {}, 0
  for _, replacement in ipairs(replacements) do
    parts[#parts + 1] = original:sub(cursor + 1, replacement.offset)
    parts[#parts + 1] = replacement.data
    cursor = replacement.offset + #replacement.data
  end
  parts[#parts + 1] = original:sub(cursor + 1)
  return table.concat(parts)
end

return codec
