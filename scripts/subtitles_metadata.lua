--[[
  Sakura Taisen (Saturn) — Subtitle Metadata Patch Plugin

  PATCH plugin that handles the subtitle tables in the SAKURA binary.  Two
  tables of 17 x 8 bytes matter, and both are written here:

      0x000a20c   image  {u16 offset/8, u16 ?, u8 width/8, u8 height, u16 ?}
      0x000a294   place  {u16 index, u16 0, s16 x, s16 y}

  The placement table is what puts a subtitle on screen: the renderer draws
  sprite i with its top-left at (x, y) from this record, and the original disc
  has y = 176 and x = 160 - width/2 for all 17.  A third table at 0x000a31c
  (17 x {u32 0x01000000, u32 -> placement record}) is left alone; it only
  points at the records, which do not move.

  Entry layout, as read by PatchSubtitles in SakuraTaisen.cpp and confirmed
  against the original disc:

      u16 BE  offset    start of the image in the decompressed LOGO.SH2 block,
                        counted in 8-byte units (original entry 1 is 0x00a0,
                        i.e. 160 * 8 = 1280 = 160x16 / 2 bytes)
      u16     unknown1  preserved verbatim
      u8      width     image width in 8-pixel tiles
      u8      height    image height in pixels
      u16     unknown2  preserved verbatim

  decode() is a NOP: the tables have no useful editable text form, and the
  source of truth for the sizes is the BMP folder.  encode() reads every
  SUBTITLES_NN.bmp in the LOGO.SH2 workspace directory and rewrites both
  tables, so a subtitle can be resized just by dropping in a differently sized
  BMP: the image entry takes the new size and block offset, and the placement
  record moves to x = (320 - width) / 2 so the sprite still lands centred.
]]

local codec = {}

codec.name        = "Sakura Taisen Subtitle Metadata"
codec.description = "PATCH plugin for subtitle metadata table at offset 0x000a20c in SAKURA"
codec.version     = 3
codec.kind        = "patch"

local SAKURA_SUBTITLE_TABLE_OFFSET     = 0x000a20c
local SAKURA_SUBTITLE_PLACEMENT_OFFSET = 0x000a294
local NUM_SUBTITLES = 17
local ENTRY_SIZE = 8
local TABLE_SIZE = NUM_SUBTITLES * ENTRY_SIZE

local SCREEN_WIDTH = 320

local MAX_WIDTH_TILES = 0xFF
local MAX_HEIGHT_PX   = 0xFF
local MAX_BLOCK_UNITS = 0xFFFF   -- the offset field is a u16 of 8-byte units

function codec.can_handle(data)
  if type(data) ~= "string" then
    return "no"
  end
  if #data < SAKURA_SUBTITLE_PLACEMENT_OFFSET + TABLE_SIZE then
    return "no"
  end
  return "possible"
end

function codec.decode_name(args)
  return "subtitles_metadata.bin"
end

function codec.decode(data, args)
  -- NOP as specified
  return {}
end

local function list_bmp_files_in_dir(dir)
  local files = {}
  if lfs then
    for file in lfs.dir(dir) do
      if file ~= "." and file ~= ".." then
        local attr = lfs.attributes(dir .. "/" .. file)
        if attr and attr.mode == "file" and file:lower():match("%.bmp$") then
          files[#files + 1] = file
        end
      end
    end
  else
    local cmd = "ls -1 '" .. dir .. "' 2>/dev/null"
    local handle = io.popen(cmd)
    if handle then
      for l in handle:lines() do
        local fname = l:gsub("[\r\n]", "")
        if fname ~= "" and fname:lower():match("%.bmp$") then
          files[#files + 1] = fname
        end
      end
      handle:close()
    end
  end
  table.sort(files)
  return files
end

-- Width and height straight from the BMP's DIB header.  The plugins agree on
-- which bits of the header matter (subtitles_gfx.lua validates the rest), so a
-- negative height (top-down rows) is just a size here.
local function read_bmp_size(path)
  local fh = io.open(path, "rb")
  if not fh then return nil end
  local head = fh:read(26)
  fh:close()
  if not head or #head < 26 or head:sub(1, 2) ~= "BM" then
    return nil
  end
  local width, height = string.unpack("<i4i4", head, 19)
  return math.abs(width), math.abs(height)
end

function codec.encode(original, artifacts, args)
  if type(original) ~= "string" then
    error("encode: expected binary string for `original`", 0)
  end

  if #original < SAKURA_SUBTITLE_PLACEMENT_OFFSET + TABLE_SIZE then
    error("encode: original file too small for the subtitle tables", 0)
  end

  local workspace = nil
  if LUDARED and LUDARED.WORKSPACE then
    workspace = LUDARED.WORKSPACE
  elseif PROJECT_ROOT then
    workspace = PROJECT_ROOT .. "/workspace"
  else
    workspace = "./workspace"
  end

  local candidates = {
    workspace .. "/SakTaiCD1_Track1.bin/data.bin/SAKURA1/LOGO.SH2",
    workspace .. "/SakTaiCD1_Track1.bin/SAKURA1/LOGO.SH2",
    workspace .. "/SAKURA1/LOGO.SH2",
  }

  local subtitle_dir, bmp_files
  for _, dir in ipairs(candidates) do
    bmp_files = list_bmp_files_in_dir(dir)
    if #bmp_files > 0 then
      subtitle_dir = dir
      break
    end
  end

  -- No BMPs extracted (or this file was built without them): leave the table
  -- untouched rather than inventing sizes.
  if not subtitle_dir then
    return original
  end

  local by_index = {}
  for _, file in ipairs(bmp_files) do
    local index = file:lower():match("^subtitles_(%d+)%.bmp$")
    if index then
      index = tonumber(index)
      if index >= 0 and index < NUM_SUBTITLES then
        by_index[index + 1] = subtitle_dir .. "/" .. file
      end
    end
  end

  local entries    = {}
  local placements = {}
  local cursor = 0            -- in 8-byte units, matching the original table
  local changed = false

  for i = 1, NUM_SUBTITLES do
    local pos = SAKURA_SUBTITLE_TABLE_OFFSET + (i - 1) * ENTRY_SIZE
    local prefix = original:sub(pos + 1, pos + ENTRY_SIZE)
    local unknown1 = prefix:sub(3, 4)
    local unknown2 = prefix:sub(7, 8)
    local width_tiles, height_px = prefix:byte(5), prefix:byte(6)
    local width_px = width_tiles * 8

    local path = by_index[i]
    if path then
      local w, h = read_bmp_size(path)
      if not w or h == 0 then
        error(string.format("encode: %s is not a readable BMP", path), 0)
      end
      if w % 8 ~= 0 then
        error(string.format(
          "encode: %s is %dx%d, but the table stores width/8 in one byte so the "
          .. "width must be a multiple of 8", path, w, h), 0)
      end
      if w // 8 > MAX_WIDTH_TILES then
        error(string.format("encode: %s is %d wide, over the %d-pixel limit",
          path, w, MAX_WIDTH_TILES * 8), 0)
      end
      if h > MAX_HEIGHT_PX then
        error(string.format("encode: %s is %d tall, over the table's %d-pixel limit",
          path, h, MAX_HEIGHT_PX), 0)
      end
      if h % 2 ~= 0 then
        error(string.format(
          "encode: %s is %d tall; the block offset is counted in 8-byte units, "
          .. "so the height must be even", path, h), 0)
      end
      width_tiles, height_px, width_px = w // 8, h, w
    end

    local size_bytes = (width_tiles * 8 * height_px) // 2
    local entry = string.pack(">I2", cursor)
      .. unknown1
      .. string.char(width_tiles, height_px)
      .. unknown2
    if entry ~= prefix then changed = true end
    entries[i] = entry

    cursor = cursor + size_bytes // 8
    if cursor > MAX_BLOCK_UNITS then
      error(string.format(
        "encode: the subtitle images end %d bytes in, past the %d bytes the "
        .. "u16 offsets can address", cursor * 8, MAX_BLOCK_UNITS * 8), 0)
    end

    -- Placement record: keep the index, the reserved word and y, and centre
    -- the canvas on screen.  With x = (320 - width) / 2 the whole sprite sits
    -- centred, which is also where the renderer would put it if it derived the
    -- position from the width itself -- so both models agree.
    local ppos = SAKURA_SUBTITLE_PLACEMENT_OFFSET + (i - 1) * ENTRY_SIZE
    local record = original:sub(ppos + 1, ppos + ENTRY_SIZE)
    local placed = record
    if path then
      if width_px > SCREEN_WIDTH then
        error(string.format(
          "encode: %s is %d wide, more than the %d-pixel screen; it cannot be "
          .. "centred", path, width_px, SCREEN_WIDTH), 0)
      end
      placed = record:sub(1, 4)
        .. string.pack(">I2", (SCREEN_WIDTH - width_px) // 2)
        .. record:sub(7, 8)
    end
    if placed ~= record then changed = true end
    placements[i] = placed
  end

  if not changed then
    return original
  end

  return original:sub(1, SAKURA_SUBTITLE_TABLE_OFFSET)
    .. table.concat(entries)
    .. original:sub(SAKURA_SUBTITLE_TABLE_OFFSET + TABLE_SIZE + 1,
                    SAKURA_SUBTITLE_PLACEMENT_OFFSET)
    .. table.concat(placements)
    .. original:sub(SAKURA_SUBTITLE_PLACEMENT_OFFSET + TABLE_SIZE + 1)
end

return codec
