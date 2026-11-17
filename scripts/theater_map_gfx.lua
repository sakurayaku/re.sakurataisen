--[[
  Sakura Taisen (Saturn) — theater map graphics

  REBUILD codec for TMAPSP and FUKAGAWA.

  The archives have no headers or image boundaries. IMAGE_LAYOUTS hardcodes
  each image's start in 8-byte units, width in 8-pixel tiles, and height in
  pixels. TMAPSP includes internal gaps; FUKAGAWA is contiguous.

  Same-sized edits patch existing pixel ranges. If an image changes dimensions,
  the codec preserves the archive through the first resized image and rebuilds
  the suffix compactly in index order; the companion SAKURA metadata codec
  updates addresses from that image onward.

  BMPs use the game palette copied into shared/constants.lua. The palette
  affects display only; pixel indices are authoritative.

  Width is stored in 8-pixel tiles and each image start in 8-byte units, so
  widths must be divisible by 8 and packed image sizes by 8. The input hash
  identifies the archive during decode; its byte size identifies it during
  encode.
]]

local bmp = dofile(LUDARED.SCRIPTS .. "/shared/bmp.lua")
local can_handle = dofile(LUDARED.SCRIPTS .. "/shared/can_handle.lua")
local constants = dofile(LUDARED.SCRIPTS .. "/shared/constants.lua")

local codec = {}

codec.name        = "Sakura Taisen Theater Map Graphics"
codec.description = "Rebuilds the 4bpp TMAPSP and FUKAGAWA image archives"
codec.version     = 7
codec.kind        = "rebuild"

-- Per-archive limits used by the game's graphics patcher.
local GFX_LIMITS = { TMAPSP = 0xD000, FUKAGAWA = 0x6D3F }
codec.gfx_limits = GFX_LIMITS

-- {start in 8-byte units, width in 8-pixel tiles, height in pixels}.
local IMAGE_LAYOUTS = {
  TMAPSP = {
    {0x0000, 3, 16}, {0x0018, 3, 16}, {0x0030, 3, 16}, {0x0048, 3, 16},
    {0x0060, 3, 16}, {0x0078, 3, 16}, {0x0090, 3, 16}, {0x00A8, 3, 16},
    {0x00C0, 3, 32}, {0x00F0, 3, 32}, {0x0120, 3, 32}, {0x0150, 3, 32},
    {0x0180, 3, 32}, {0x01B0, 3, 32}, {0x01E0, 3, 32}, {0x0210, 3, 16},
    {0x0228, 3, 16}, {0x0240, 3, 16}, {0x0258, 3, 16}, {0x0270, 3, 16},
    {0x0288, 3, 16}, {0x02A0, 3, 16}, {0x02B8, 3, 16}, {0x02D0, 3, 32},
    {0x0300, 3, 32}, {0x0330, 3, 32}, {0x0360, 3, 32}, {0x0390, 3, 32},
    {0x03C0, 3, 32}, {0x03F0, 3, 32}, {0x0420, 3, 32}, {0x0450, 3, 32},
    {0x0480, 1, 8}, {0x0484, 1, 16}, {0x048C, 2, 16}, {0x049C, 1, 16},
    {0x04A4, 1, 8}, {0x04A8, 1, 16}, {0x04B0, 1, 24}, {0x04BC, 3, 16},
    {0x04D4, 2, 16}, {0x04E4, 3, 32}, {0x0514, 3, 32}, {0x0544, 3, 32},
    {0x0574, 3, 32}, {0x05A4, 3, 32}, {0x05D4, 3, 16}, {0x05EC, 9, 24},
    {0x06C4, 9, 24}, {0x079C, 7, 40}, {0x08B4, 7, 40}, {0x09CC, 11, 24},
    {0x0A50, 11, 24}, {0x0AD4, 11, 24}, {0x0B58, 11, 24}, {0x0BDC, 11, 24},
    {0x0C60, 11, 24}, {0x0CE4, 7, 24}, {0x0D38, 11, 24}, {0x0DBC, 7, 24},
    {0x0E10, 7, 24}, {0x0E64, 7, 24}, {0x0EB8, 9, 24}, {0x0F24, 7, 24},
    {0x0F78, 7, 24}, {0x0FCC, 7, 24}, {0x1020, 9, 24}, {0x108C, 7, 24},
    {0x10E0, 7, 24}, {0x1134, 8, 24}, {0x1194, 7, 24}, {0x11E8, 7, 24},
    {0x123C, 8, 24}, {0x129C, 7, 24}, {0x12F0, 11, 24}, {0x1374, 7, 24},
    {0x13C8, 8, 24}, {0x1428, 7, 24}, {0x147C, 7, 24}, {0x14D0, 7, 24},
    {0x1524, 7, 24}, {0x1578, 7, 24}, {0x15CC, 7, 24}, {0x1620, 7, 24},
    {0x1674, 7, 24}, {0x16C8, 7, 24}, {0x171C, 7, 24}, {0x1770, 10, 24},
    {0x17E8, 7, 24}, {0x183C, 7, 24}, {0x1890, 11, 24}, {0x1914, 11, 24},
    {0x1998, 7, 24},
  },
  FUKAGAWA = {
    {0x0000, 3, 16}, {0x0018, 3, 16}, {0x0030, 3, 16}, {0x0048, 3, 16},
    {0x0060, 3, 16}, {0x0078, 3, 16}, {0x0090, 3, 16}, {0x00A8, 3, 16},
    {0x00C0, 3, 32}, {0x00F0, 3, 32}, {0x0120, 3, 32}, {0x0150, 3, 32},
    {0x0180, 3, 32}, {0x01B0, 3, 32}, {0x01E0, 3, 32}, {0x0210, 3, 16},
    {0x0228, 3, 16}, {0x0240, 3, 16}, {0x0258, 3, 16}, {0x0270, 3, 16},
    {0x0288, 3, 16}, {0x02A0, 3, 16}, {0x02B8, 3, 16}, {0x02D0, 3, 32},
    {0x0300, 3, 32}, {0x0330, 3, 32}, {0x0360, 3, 32}, {0x0390, 3, 32},
    {0x03C0, 3, 32}, {0x03F0, 3, 32}, {0x0420, 3, 32}, {0x0450, 3, 32},
    {0x0480, 1, 8}, {0x0484, 1, 16}, {0x048C, 2, 16}, {0x049C, 1, 16},
    {0x04A4, 1, 8}, {0x04A8, 1, 16}, {0x04B0, 1, 24}, {0x04BC, 3, 16},
    {0x04D4, 2, 16}, {0x04E4, 3, 32}, {0x0514, 3, 32}, {0x0544, 3, 32},
    {0x0574, 3, 32}, {0x05A4, 3, 32}, {0x05D4, 3, 16}, {0x05EC, 11, 24},
    {0x0670, 11, 24}, {0x06F4, 8, 24}, {0x0754, 7, 24}, {0x07A8, 7, 24},
    {0x07FC, 7, 24}, {0x0850, 7, 24}, {0x08A4, 7, 24}, {0x08F8, 8, 24},
    {0x0958, 11, 24}, {0x09DC, 11, 24}, {0x0A60, 8, 24}, {0x0AC0, 7, 24},
    {0x0B14, 7, 24}, {0x0B68, 7, 24}, {0x0BBC, 11, 24}, {0x0C40, 7, 24},
    {0x0C94, 7, 24}, {0x0CE8, 7, 24}, {0x0D3C, 9, 24},
  },
}

local function from_hex(value)
  local bytes = {}
  for i = 1, #value, 2 do
    bytes[#bytes + 1] = string.char(tonumber(value:sub(i, i + 1), 16))
  end
  return table.concat(bytes)
end

local DISPLAY_PALETTE = from_hex(constants.THEATER_MAP_PALETTE_BGRA)
codec.DISPLAY_PALETTE = DISPLAY_PALETTE

local function get_entries(data, filename)
  local layout = IMAGE_LAYOUTS[filename]
  if not layout then error("theater_map: unsupported archive", 0) end
  local entries = {}
  local previous_end = 0
  for index, record in ipairs(layout) do
    local start = record[1] * 8
    local width_tiles, height = record[2], record[3]
    local size = width_tiles * height * 4
    if start + size > #data then
      error(string.format("theater_map: image %d extends past the input", index - 1), 0)
    end
    if start < previous_end then
      error(string.format("theater_map: image %d overlaps or is out of order", index - 1), 0)
    end

    entries[#entries + 1] = {
      index = index - 1,
      start = start,
      size = size,
      width = width_tiles * 8,
      height = height,
    }
    previous_end = start + size
  end

  if entries[1].start ~= 0 or previous_end ~= #data then
    error(string.format(
      "theater_map: static image layout covers %d of %d input bytes",
      previous_end, #data), 0)
  end

  return entries
end

function codec.can_handle(data)
  return can_handle.can_handle_theater_map(data)
end

codec.image_layouts = IMAGE_LAYOUTS

function codec.decode_name()
  return "THEATER_MAP"
end

function codec.decode(data)
  local filename = can_handle.identify_theater_map(data)
  if not filename then error("theater_map: unsupported input archive", 0) end
  local selected = get_entries(data, filename)
  local palette = DISPLAY_PALETTE
  local artifacts = {}

  for _, entry in ipairs(selected) do
    local pixels = data:sub(entry.start + 1, entry.start + entry.size)
    artifacts[#artifacts + 1] = {
      name = string.format("%02d.bmp", entry.index),
      data = bmp.build(pixels, entry.width, entry.height, 4, palette),
    }
  end

  return artifacts
end

local function parse_image(bmp_data, index)
  if type(bmp_data) ~= "string" or #bmp_data < 54 or bmp_data:sub(1, 2) ~= "BM" then
    error(string.format("theater_map: image %d is not a readable BMP", index), 0)
  end
  local width, signed_height = string.unpack("<i4i4", bmp_data, 19)
  local height = math.abs(signed_height)
  if width <= 0 or height == 0 or width % 8 ~= 0
      or width // 8 > 0xFF or height > 0xFF then
    error(string.format("theater_map: image %d has unsupported dimensions %dx%d",
      index, width, signed_height), 0)
  end

  local pixels = bmp.parse(bmp_data, width, height, 4)
  local size = #pixels
  if size % 8 ~= 0 then
    error(string.format(
      "theater_map: image %d is %dx%d; packed size must be a multiple of 8 bytes",
      index, width, height), 0)
  end
  return { pixels = pixels, width = width, height = height, size = size }
end

local function archive_for_size(data)
  if #data == constants.CD1_TMAPSP_BYTES or #data == constants.CD2_TMAPSP_BYTES then
    return "TMAPSP"
  end
  if #data == constants.CD1_FUKAGAWA_BYTES or #data == constants.CD2_FUKAGAWA_BYTES then
    return "FUKAGAWA"
  end
  error(string.format("theater_map: unsupported archive size %d", #data), 0)
end

function codec.encode(original, artifacts)
  if type(original) ~= "string" then
    error("theater_map: expected binary string for original", 0)
  end
  local filename = archive_for_size(original)
  local selected = get_entries(original, filename)
  local by_name = {}
  for _, artifact in ipairs(artifacts or {}) do
    if type(artifact) == "table" and type(artifact.name) == "string" then
      by_name[artifact.name] = artifact.data
    end
  end

  local images, resized_from = {}, nil
  for i, entry in ipairs(selected) do
    local name = string.format("%02d.bmp", entry.index)
    local bmp_data = by_name[name]
    if bmp_data then
      images[entry.index + 1] = parse_image(bmp_data, entry.index)
      local image = images[entry.index + 1]
      if image.width ~= entry.width or image.height ~= entry.height then
        resized_from = resized_from or i
      end
    end
  end

  if resized_from then
    local first = selected[resized_from]
    local prefix = original:sub(1, first.start)
    for i = 1, resized_from - 1 do
      local entry = selected[i]
      local image = images[i]
      if image then
        local old = original:sub(entry.start + 1, entry.start + entry.size)
        if image.pixels ~= old then
          prefix = prefix:sub(1, entry.start) .. image.pixels
            .. prefix:sub(entry.start + entry.size + 1)
        end
      end
    end

    local parts, size = { prefix }, #prefix
    for i = resized_from, #selected do
      local entry = selected[i]
      local image = images[i]
      local pixels = image and image.pixels
        or original:sub(entry.start + 1, entry.start + entry.size)
      parts[#parts + 1] = pixels
      size = size + #pixels
    end
    if size > GFX_LIMITS[filename] then
      error(string.format(
        "theater_map: rebuilt %s is %d bytes; per-file limit is %d",
        filename, size, GFX_LIMITS[filename]), 0)
    end
    return table.concat(parts)
  end

  local out = original
  for _, entry in ipairs(selected) do
    local image = images[entry.index + 1]
    if image then
      local old = original:sub(entry.start + 1, entry.start + entry.size)
      if image.pixels ~= old then
        out = out:sub(1, entry.start) .. image.pixels
          .. out:sub(entry.start + entry.size + 1)
      end
    end
  end
  return out
end

return codec
