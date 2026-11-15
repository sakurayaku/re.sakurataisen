--[[
  Minimal BMP reader/writer for the Sakura Taisen codecs.

  The game's images are paletted 4bpp or 8bpp.  Every codec needs the same
  three things: build a top-down BMP from raw pixel bytes, parse a user-edited
  BMP back to raw pixel bytes (ignoring row padding and row order), and expand
  Saturn's big-endian 5:5:5 palette words to BMP BGRA entries.

  Pixel arguments are always raw, top-down, packed rows without BMP padding:
      width * height * bpp / 8 bytes
  Palette arguments are BMP BGRA bytes (blue, green, red, 0), four per entry.
]]

local M = {}

local FILE_HEADER = 14
local INFO_HEADER = 40

local function palette_entries(bpp)
  if bpp == 4 then return 16 end
  if bpp == 8 then return 256 end
  error("bmp: unsupported bits per pixel: " .. tostring(bpp), 0)
end

local function row_layout(width, bpp)
  local row_bits = width * bpp
  return (row_bits + 7) // 8, ((row_bits + 31) // 32) * 4
end

-- A neutral index ramp.  This is not game data: it is a display palette for
-- resources whose real palette is stored outside the decoded file.  Codecs
-- document when they use it instead of a real palette.
function M.ramp(bpp)
  local n = palette_entries(bpp)
  local out = {}
  for i = 0, n - 1 do
    local v = n == 1 and 0 or (i * 255) // (n - 1)
    out[#out + 1] = string.char(v, v, v, 255)
  end
  return table.concat(out)
end

-- Saturn palettes are big-endian 16-bit 0BBBBBGGGGGRRRRR values.  The high bit
-- is unused and masked, as PaletteData::CreateFrom15BitData does.
function M.from_bgr555(data, count)
  if type(data) ~= "string" or #data < count * 2 then
    error(string.format("bmp: palette needs %d bytes, got %d", count * 2, #data or -1), 0)
  end
  local out = {}
  for i = 0, count - 1 do
    local c = string.unpack(">I2", data, i * 2 + 1) & 0x7FFF
    local b = (c >> 10) & 0x1F
    local g = (c >> 5) & 0x1F
    local r = c & 0x1F
    out[#out + 1] = string.char(
      (b * 255 + 15) // 31,
      (g * 255 + 15) // 31,
      (r * 255 + 15) // 31,
      0)
  end
  return table.concat(out)
end

function M.build(pixels, width, height, bpp, palette)
  local entries = palette_entries(bpp)
  local row_bytes, stride = row_layout(width, bpp)
  local expected = row_bytes * height
  if type(pixels) ~= "string" or #pixels ~= expected then
    error(string.format("bmp: expected %d pixel bytes for %dx%d %dbpp, got %d",
      expected, width, height, bpp, type(pixels) == "string" and #pixels or -1), 0)
  end

  palette = palette or M.ramp(bpp)
  if #palette ~= entries * 4 then
    error(string.format("bmp: expected a %d-byte palette, got %d", entries * 4, #palette), 0)
  end

  local pixel_offset = FILE_HEADER + INFO_HEADER + entries * 4
  local image_size = stride * height
  local header = string.pack("<c2I4I2I2I4I4i4i4I2I2I4I4I4I4I4I4",
    "BM", pixel_offset + image_size, 0, 0, pixel_offset,
    INFO_HEADER, width, -height, 1, bpp, 0, image_size, 0, 0, entries, 0)

  local rows = {}
  for y = 0, height - 1 do
    local row = pixels:sub(y * row_bytes + 1, (y + 1) * row_bytes)
    rows[#rows + 1] = row .. string.rep("\0", stride - row_bytes)
  end
  return header .. palette .. table.concat(rows)
end

function M.parse(bmp, width, height, bpp)
  if type(bmp) ~= "string" or #bmp < FILE_HEADER + INFO_HEADER then
    error("bmp: file too short", 0)
  end
  if bmp:sub(1, 2) ~= "BM" then
    error("bmp: not a BMP file", 0)
  end

  local pixel_offset = string.unpack("<I4", bmp, 11)
  local info_size, w, h, planes, bits, compression =
    string.unpack("<I4i4i4I2I2I4", bmp, 15)

  if info_size < INFO_HEADER then
    error("bmp: unsupported info header", 0)
  end
  if w ~= width or math.abs(h) ~= height then
    error(string.format("bmp: image is %dx%d, expected %dx%d", w, h, width, height), 0)
  end
  if planes ~= 1 then error("bmp: invalid plane count", 0) end
  if bits ~= bpp then
    error(string.format("bmp: image is %d bpp, expected %d", bits, bpp), 0)
  end
  if compression ~= 0 then error("bmp: compressed BMPs are not supported", 0) end

  local entries = palette_entries(bpp)
  local palette_start = pixel_offset - entries * 4
  if palette_start < FILE_HEADER + INFO_HEADER then
    error("bmp: palette does not fit before the pixel data", 0)
  end

  local row_bytes, stride = row_layout(width, bpp)
  if pixel_offset + stride * height > #bmp then
    error("bmp: truncated pixel data", 0)
  end

  local rows = {}
  for y = 0, height - 1 do
    local source_row = h > 0 and (height - 1 - y) or y
    local start = pixel_offset + source_row * stride
    rows[#rows + 1] = bmp:sub(start + 1, start + row_bytes)
  end

  return table.concat(rows), bmp:sub(palette_start + 1, pixel_offset)
end

return M
