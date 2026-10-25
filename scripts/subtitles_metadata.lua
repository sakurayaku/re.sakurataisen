--[[
  Sakura Taisen (Saturn) — Subtitle Metadata Patch Plugin

  PATCH plugin that handles the subtitle tables in the SAKURA binary.  Two
  tables of 17 x 8 bytes matter, and both are written here:

      0x000a20c   image  {u16 offset/8, u16 ?, u8 width/8, u8 height, u16 ?}
      0x000a294   place  {u16 index, u16 0, s16 x, s16 y}

  The placement table is what puts a subtitle on screen: the renderer draws
  sprite i with its top-left at (x, y) from this record, and the original disc
  has y = 176 and x = 160 - width/2 for all 17. A third table at 0x000a31c
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
  SUBTITLES/NN.bmp in the LOGO.SH2 workspace directory and rewrites both
  tables, so a subtitle can be resized just by dropping in a differently sized
  BMP: the image entry takes the new size and block offset, and the placement
  record moves to x = (320 - width) / 2 so the sprite still lands centred.

  Blank canvases are aliases.  A BMP whose every pixel is the transparent
  palette index draws nothing, and the sequence player asks for subtitle ids,
  not for textures -- so entry i takes the offset, width and height of the
  previous *visible* subtitle and placement i takes its x and y, while the
  record keeps index i and the descriptors in the third table stay untouched.
  `displaySubtitle(10)` then draws whatever canvas 9 draws.  Consecutive blank
  canvases all borrow from that same last visible subtitle, and the first one
  cannot borrow anything, so it keeps its own metadata.
  The placeholder still owns its bytes in the image block -- subtitles_gfx.lua
  encodes all 17 canvases -- so nothing moves for anybody else: aliasing only
  rewrites this slot's two records.  A build with no blank canvas is byte for
  byte what it was before aliasing existed.

  The placeholder still owns its bytes in the image block -- subtitles_gfx.lua
  encodes all 17 canvases -- so nothing moves for anybody else: aliasing only
  rewrites this slot's two records.  A build with no blank canvas is byte for
  byte what it was before aliasing existed.

  Blankness is a question about the pixel's index, never about its RGB value.
  Palette entry 0 is 0x03FF, a bright yellow that appears nowhere in the shipped
  art, so "every pixel yellow" would be a trap and "looks empty in the editor" is
  not the test. A canvas that cannot be read -- header only, a deeper bit depth,
  a truncated image -- is not treated as blank; it keeps the metadata it always had
  and subtitles_gfx.lua is the codec that rejects it.

  Arguments: none; any passed are ignored.

  Not supported, and refused rather than written wrongly:

  * a canvas whose width is not a multiple of 8, whose height is odd, that is
    wider than 320 pixels, or taller than 255: the table stores width/8 and
    height in single bytes and the block offset in 8-byte units, and rounding
    any of them would move the artwork's centre
  * canvases whose offsets pass the 0xFFFF 8-byte units the image table can
    address
  * a SAKURA too short to hold both tables
]]

local codec = {}

codec.name        = "Sakura Taisen Subtitle Metadata"
codec.description = [[Sakura Taisen (Saturn) subtitle metadata: the tables in SAKURA

Patches the two 17 x 8-byte tables that size and place the images the subtitle
block in LOGO.SH2 holds, and returns the file untouched when nothing changed:

  0x000a20c  image      {u16 offset/8, u16 ?, u8 width/8, u8 height, u16 ?}
  0x000a294  placement  {u16 index, u16 0, s16 x, s16 y}

The placement record is what puts a subtitle on screen: sprite i is drawn with
its top-left at that record's x and y, and the original disc has y = 176 with
x = 160 - width/2 for all 17. The third table at 0x000a31c is 17 descriptors of
{u32 0x01000000, u32 -> placement record}; it only points at records that do not
move, so this codec leaves it alone.

The canvases are the source of truth. A decode produces no artifacts: the tables
have no editable text form, and an edit made in them by hand would be
overwritten by the next rebuild. Instead a rebuild reads every SUBTITLES/NN.bmp
of the workspace's LOGO.SH2 directory and writes both tables from the canvases.
Entry i takes the offset the canvases before it add up to, and the canvas's own
width and height; record i moves to x = (320 - width) / 2 so the sprite stays
centred. The reserved words in both records are preserved verbatim, and so is y.
Dropping in a differently sized canvas therefore resizes a subtitle with no
other edit -- which is why this codec and subtitles_gfx.lua belong in the
manifest together: one lays the images into the block, the other states where
each one starts and how big it is, and both read the same canvases.

A blank canvas aliases. A canvas whose every pixel is the transparent palette
index 0 draws nothing, and the sequence player asks for subtitle ids rather than
textures: entry i then takes the previous visible subtitle's offset, width and
height, and record i takes that record's x and y, while keeping index i.
Consecutive blank canvases all borrow from that same last visible subtitle, and
the first subtitle has nothing to borrow from, so it keeps its own records. The
placeholder still owns its bytes in the image block, because subtitles_gfx.lua
encodes all 17 canvases, so aliasing moves nothing for anybody else -- it only
rewrites this slot's two records, and a build with no blank canvas is byte for
byte what it was before aliasing existed.

Blankness is a question about the pixel's index, never about its RGB value.
Palette entry 0 is 0x03FF, a bright yellow that appears nowhere in the shipped
art, so "every pixel yellow" would be a trap and "looks empty in the editor" is
not the test. A canvas that cannot be read -- header only, a deeper bit depth,
a truncated image -- is not treated as blank; it keeps the metadata it always had
and subtitles_gfx.lua is the codec that rejects it.
]]
codec.version     = 4
codec.kind        = "patch"

local SAKURA_SUBTITLE_TABLE_OFFSET     = 0x000a20c
local SAKURA_SUBTITLE_PLACEMENT_OFFSET = 0x000a294
local NUM_SUBTITLES = 17
local ENTRY_SIZE = 8
local TABLE_SIZE = NUM_SUBTITLES * ENTRY_SIZE

local SCREEN_WIDTH = 320

-- Palette entry 0 is the sprite's transparent code: the 16 subtitle colours
-- sit at LOGO.SH2 offset 0x19578 (CRAM 0x25f00240) and entry 0 is 0x03FF, a
-- bright yellow that appears nowhere in the shipped art.  Blankness is
-- therefore a question about the pixel's *index*, never about its RGB value --
-- which matters, because that yellow looks nothing like "empty".
local TRANSPARENT_INDEX = 0

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
        local fname = l:gsub("[\\r\\n]", "")
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

-- Does this canvas draw anything?  Every pixel is one 4-bit palette index, and
-- the canvas is blank when all of them are the transparent one.  Row padding
-- past width/2 bytes is not pixel data and is skipped.
--
-- Returns nil when the pixel data cannot be read -- a header only file, an
-- unexpected bit depth, a truncated image.  Format errors belong to
-- subtitles_gfx.lua, so an unreadable canvas is reported as unreadable here and
-- keeps the metadata it always had instead of being silently aliased.
local function bmp_is_blank(data, width, height)
  if #data < 54 or width <= 0 or height == 0 then
    return nil
  end
  local off, info_len, _, _, planes, bpp, comp =
    string.unpack("<I4I4i4i4I2I2I4", data, 11)
  if planes ~= 1 or bpp ~= 4 or comp ~= 0 or info_len < 40 then
    return nil
  end
  if off < 14 + info_len then
    return nil
  end

  local stride = ((width * 4 + 31) // 32) * 4
  local row_bytes = width // 2
  if #data < off + stride * height then
    return nil
  end

  -- One nibble per pixel: a row of transparent pixels is one repeated byte.
  local empty = string.rep(string.char(TRANSPARENT_INDEX * 0x11), row_bytes)

  for y = 0, height - 1 do
    local base = off + y * stride
    if data:sub(base + 1, base + row_bytes) ~= empty then
      return false
    end
  end
  return true
end

local function read_bmp(path)
  local fh = io.open(path, "rb")
  if not fh then return nil end
  local data = fh:read("a")
  fh:close()
  -- Width and height straight from the DIB header.  The plugins agree on which
  -- bits of the header matter (subtitles_gfx.lua validates the rest), so a
  -- negative height (top-down rows) is just a size here.
  if not data or #data < 26 or data:sub(1, 2) ~= "BM" then
    return nil
  end
  local width, height = string.unpack("<i4i4", data, 19)
  local w, h = math.abs(width), math.abs(height)
  return w, h, bmp_is_blank(data, w, h)
end

function codec.encode(original, artifacts, args)
  if type(original) ~= "string" then
    error("encode: expected binary string for `original`", 0)
  end

  if #original < SAKURA_SUBTITLE_PLACEMENT_OFFSET + TABLE_SIZE then
    error("encode: original file too small for the subtitle tables", 0)
  end

  -- Resolve workspace path: LUDARED first, then fallback to default.
  -- The LUDARED global is provided by the host at runtime; when not available
  -- we use a default relative path.  This keeps the codec working both under
  -- Ludared and as a standalone script.
  local workspace = nil
  if LUDARED and LUDARED.WORKSPACE then
    workspace = LUDARED.WORKSPACE
  else
    workspace = "./workspace"
  end

  local subtitle_dir = workspace .. "/SakTaiCD1_Track1.bin/data.bin/SAKURA1/LOGO.SH2/SUBTITLES"
  local bmp_files = list_bmp_files_in_dir(subtitle_dir)

  -- No BMPs extracted: leave the table untouched.
  if #bmp_files == 0 then
    return original
  end

  local by_index = {}
  for _, file in ipairs(bmp_files) do
    local index = tonumber(file:lower():match("^(%d+)%.bmp$"))
    if index and index >= 0 and index < NUM_SUBTITLES then
      by_index[index + 1] = subtitle_dir .. "/" .. file
    end
  end

  local entries    = {}
  local placements = {}
  local layouts    = {}       -- what each canvas reserves in the image block
  local cursor = 0            -- in 8-byte units, matching the original table
  local changed = false
  local last_visible = nil    -- last slot whose canvas draws something

  for i = 1, NUM_SUBTITLES do
    local pos = SAKURA_SUBTITLE_TABLE_OFFSET + (i - 1) * ENTRY_SIZE
    local prefix = original:sub(pos + 1, pos + ENTRY_SIZE)
    local unknown1 = prefix:sub(3, 4)
    local unknown2 = prefix:sub(7, 8)
    local width_tiles, height_px = prefix:byte(5), prefix:byte(6)
    local width_px = width_tiles * 8
    local blank = false

    local path = by_index[i]
    if path then
      local w, h, is_blank = read_bmp(path)
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
      blank = is_blank == true
    end

    -- The canvas keeps its own place in the block whatever it ends up showing:
    -- subtitles_gfx.lua encodes all 17 BMPs, so the layout cannot depend on one
    -- of them happening to be blank.  That is what keeps every later offset
    -- exactly where it was.
    local size_bytes = (width_tiles * 8 * height_px) // 2
    layouts[i] = { offset = cursor, width_tiles = width_tiles, height_px = height_px }

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

    -- A canvas with no visible pixel draws nothing, but the sequence player
    -- asks for subtitle ids, not for textures: show the last canvas that did
    -- draw instead.  Only the texture (offset, width, height) and the position
    -- (x, y) are borrowed -- entry i keeps its own reserved words and record i
    -- keeps index i -- so the descriptor table needs no change at all.
    local texture = layouts[i]
    if blank and last_visible then
      texture = layouts[last_visible]
      placed = string.pack(">I2", i - 1)
        .. record:sub(3, 4)
        .. placements[last_visible]:sub(5, 8)
    end

    local entry = string.pack(">I2", texture.offset)
      .. unknown1
      .. string.char(texture.width_tiles, texture.height_px)
      .. unknown2

    if entry ~= prefix then changed = true end
    entries[i] = entry
    if placed ~= record then changed = true end
    placements[i] = placed

    cursor = cursor + size_bytes // 8
    if cursor > MAX_BLOCK_UNITS then
      error(string.format(
        "encode: the subtitle images end %d bytes in, past the %d bytes the "
        .. "u16 offsets can address", cursor * 8, MAX_BLOCK_UNITS * 8), 0)
    end

    -- Only a canvas that draws is a usable alias target; a slot without a BMP
    -- is not one either, since its size is not ours to promise.
    if path and not blank then last_visible = i end
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