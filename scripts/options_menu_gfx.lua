--[[ Sakura Taisen Options menu graphics (PATCH codec, version 4)

  Covers the whole Options text subsystem, not just the five main rows.  Every
  text list on the screen reads one PRS atlas at file 0x5B320 (73 retail tiles,
  VDP1 0x6C300); see research/SAKTAI_OPTIONS_MENU.md sections 5.3 and 7 for the
  ownership map, the addresses and the model.

  Consumers, all rebuilt by this codec (19 lists):

      5   main rows         descriptor +12 count, +16 list, +20 base 0xd860
      10  action labels     count byte at 0x5ABBC, pointer at 0x5ABC8
      1   action 11         the submenu EXIT, shared with the main exit row
      1   button column     12 records at 0x5A5DE (8 button icons + EXIT)
      1   mini labels       8 records at 0x5ACB0, linked to the button icons

  The main EXIT row and action list 11 originally share one list at 0x5A796.
  Decode exposes both consumers (OPTIONS/04_EXIT.bmp and OPTIONS/SUB_11_EXIT.bmp,
  identical in the retail build); encode keeps the shared list while the two
  images are identical and splits it into its own list as soon as they differ.

  The button column (12 records at 0x5A5DE) is derived, not edited: three icons
  come from OPTIONS/BUTTON_ABC.bmp, five from OPTIONS/BUTTON_XYZLR.bmp, and the
  last four spell EXIT out of the four 16-px cells of OPTIONS/SUB_11_EXIT.bmp.
  The EXIT art is therefore exposed once and edited once; the column and the
  submenu label share its textures instead of storing them twice.

  Model: the translator edits complete rendered labels as BMPs.  Encode cuts
  each image into horizontal bands of at most 16 rows (a 16-px label is one
  band, blank margins included; the two button boards get one band per icon)
  and 16-pixel columns measured from the image origin, skips empty cells, and
  stores each distinct cell once.  Records place those cells back at
  their exact pixel positions, so the composed image is reproduced pixel for
  pixel.  Spacing between words costs neither atlas space nor records: it is
  expressed by the record x.

  There is no fixed 16 x 16 glyph grid and no Japanese glyph indices to keep.
  The atlas holds only the cells the current images use, in first-use order,
  and the lists are re-pointed at it.

  Budgets: decoded sheet <= 11,520 bytes (0x2d00, up to the next texture at
  VDP1 0x6f000) and the PRS stream <= 3,782 bytes (the fixed slot).  A list
  keeps its retail slot while its record count fits (cursor 11, sound 12,
  voice 7, controls 10, exit 4); action lists are packed into the retired pool
  at 0x5A656 (320 bytes) and then into the unused tail of the atlas slot,
  whose bytes follow the PRS end marker and are never written by the
  decompressor at 0x0600A164 (it ends on a zero back-reference word).  That is
  662 bytes of relocated record storage in retail, 280 of which the 84 retail
  records use; a translated screen needs more, and overflow is an error.

  Artifacts:

      OPTIONS/00_CURSOR_SPEED.bmp        4bpp, 16 px high
      OPTIONS/01_SOUND.bmp
      OPTIONS/02_VOICE.bmp
      OPTIONS/03_CONTROLS.bmp
      OPTIONS/04_EXIT.bmp                shared with action list 11
      OPTIONS/SUB_00_NONE.bmp            action list 0
      OPTIONS/SUB_01_CONFIRM.bmp         action list 1 (決定)
      OPTIONS/SUB_02_CANCEL.bmp          action list 2 (取り消し)
      OPTIONS/SUB_04_MAP.bmp             action list 4 (全図)
      OPTIONS/SUB_05_CONSULT.bmp         action list 5 (相談)
      OPTIONS/SUB_06_DEFEND.bmp          action list 6 (防御)
      OPTIONS/SUB_07_WAIT.bmp            action list 7 (ため)
      OPTIONS/SUB_08_ATTACK.bmp          action list 8 (通常攻撃)
      OPTIONS/SUB_09_MOVE.bmp            action list 9 (移動)
      OPTIONS/SUB_10_DEFAULT.bmp         action list 10 (初期設定)
      OPTIONS/SUB_11_EXIT.bmp            action list 11, shared with 04_EXIT;
                                         its four 16-px cells are also the
                                         button column's EXIT
      OPTIONS/BUTTON_ABC.bmp             A, B, C: three 16-px icons, 16 x 48
      OPTIONS/BUTTON_XYZLR.bmp           X, Y, Z, L, R: five icons, 16 x 80
      OPTIONS/TEXT_ORIGINS.json          per-list anchor x/y
      OPTIONS/BACKGROUND.bmp             288 x 144 panel
      OPTIONS/BRACKET_LEFT.bmp           8 x 16 selection mark
      OPTIONS/BRACKET_RIGHT.bmp
      OPTIONS/BRACKET_POSITIONS.json

  Action list 3 has no records in the retail build and has no artifact, so a
  translation that needs it must first give the list a pointer of its own (the
  encoder writes one for every artifact it does get).

  The BMP palette is the parent's own options label bank; encode compares
  pixels only, so a palette edit is not a change.  Encode refuses any write
  outside the atlas slot, the record lists, the text pointers/counts and the
  independently optional background/mark/position data.
]]

local function script_dir()
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then
    return src:sub(2):match("^(.*)[/\\][^/\\]*$") or "."
  end
  return "."
end

-- Codecs run under Ludared (which knows the scripts root) and standalone under
-- the test harness; both cases have to find shared/ helpers.
local function load_shared(name)
  if LUDARED and LUDARED.SCRIPTS then
    return dofile(LUDARED.SCRIPTS .. "/shared/" .. name .. ".lua")
  end
  return dofile(script_dir() .. "/shared/" .. name .. ".lua")
end

local prs         = LUDARED.codec("std/sega/compression/prs")
local args_parser = load_shared("args_parser")
local sha256      = load_shared("sha256")

local codec = {}

codec.name        = "Sakura Taisen Options Menu Graphics"
codec.description = "PATCH plugin for every Options-screen text list, the panel and the selection marks in SAKURA"
codec.kind        = "patch"
codec.version     = 4

local FILE_BYTES  = 391712
local FILE_SHA256 = "1729cd8701fa8da30b203d0bf97e47e2dc9cf06b50ca91589ea760fe0cb8ff87"

local ATLAS_OFFSET  = 0x05b320
local ATLAS_SLOT    = 3782              -- fixed compressed slot
local ATLAS_LIMIT   = 0x2d00            -- 11,520 bytes before the next texture
local TEXTURE_BASE  = 0xd860            -- VDP1 0x6c300 >> 3
local RAM_BASE      = 0x06004000        -- file offset -> RAM address

local PALETTE_OFFSET     = 0x05ad98     -- two 16-colour BGR555 banks
local PALETTE_BANK_BYTES = 32           -- 16 entries x 2 bytes
local PALETTE_TEXT       = PALETTE_OFFSET + PALETTE_BANK_BYTES

local BACKGROUND_OFFSET = 0x05ae38     -- PRS, fixed 1,256-byte slot
local BACKGROUND_SLOT   = 1256
local BACKGROUND_W      = 288
local BACKGROUND_H      = 144
local BACKGROUND_PIXELS = BACKGROUND_W * BACKGROUND_H // 2   -- 20,736
local BACKGROUND_END    = 0xc300        -- 49,920 decoded bytes
local BACKGROUND_CHAIN  = 1024          -- deeper search keeps the slot

-- The two selection marks are the last 128 bytes of the background stream:
-- 8 x 16 4bpp sprites, left then right, texture base 0xd850.
local BRACKET_OFFSET   = 0xc280
local BRACKET_BYTES    = 64
local BRACKET_W        = 8
local BRACKET_H        = 16
local BRACKET_TAIL_AT  = BRACKET_OFFSET - BACKGROUND_PIXELS

local RECORD_BYTES  = 10
local LABEL_H       = 16
local LABEL_ALIGN   = 8
local LABEL_MAX_W   = 255 * 8           -- VDP1 CMDSIZE width field
local MAX_RECORDS   = 64                -- per list
local ATLAS_CHAIN   = 1024              -- PRS match-chain depth
local MAX_CHOICES   = 32

-- Key-config tables (research/SAKTAI_OPTIONS_MENU.md 5.3).
local ACTION_TABLE    = 0x05abbc        -- 12 count bytes
local ACTION_POINTERS = 0x05abc8        -- 12 BE dwords
local ACTION_COUNT    = 12
local ACTION_ARENA    = 0x05a656        -- retired action pool, records 12..43
local ACTION_ARENA_LEN = 0x05a796 - ACTION_ARENA
local BUTTON_REC      = 0x05a5de        -- 12 records read by the drawer
local BUTTON_COUNT    = 12
local MINI_REC        = 0x05acb0        -- 8 records, same icons as the buttons
local MINI_COUNT      = 8

-- The button column (12 records at 0x5A5DE) is not an artifact: encode derives
-- it from two button boards and from the submenu's own EXIT label.  Each board
-- is the bounding box of the icons it carries, so a missing or extra icon is
-- an error rather than a silently shorter column.
local BUTTON_ABC_NAME     = "BUTTON_ABC"       -- A, B, C
local BUTTON_XYZLR_NAME   = "BUTTON_XYZLR"     -- X, Y, Z, L, R
local BUTTON_ABC_ANCHOR   = { x = -48, y = -80 }
local BUTTON_XYZLR_ANCHOR = { x = -48, y = -24 }
local BUTTON_ABC_H        = 48                 -- three 16-px icons
local BUTTON_XYZLR_H      = 80                 -- five 16-px icons
local BUTTON_ABC_COUNT    = 3
local BUTTON_XYZLR_COUNT  = 5
local EXIT_CELLS          = 4                  -- the column's last four records
local EXIT_CELL_WIDTH     = 16                 -- spell EXIT, one cell per letter
local EXIT_COLUMN_X       = -32                -- where those cells sit
local EXIT_COLUMN_Y       = 64                 -- in the column's own geometry

-- The five main rows.  `cap` is the number of records the retail slot holds;
-- a longer list is relocated instead of overwriting its neighbours.
local MAIN = {
  { name = "00_CURSOR_SPEED", desc = 0x05ab68, slot = 0x05aa50, cap = 11,
    anchor = { x = -128, y = -8 } },
  { name = "01_SOUND",        desc = 0x05aa30, slot = 0x05a974, cap = 12,
    anchor = { x = -128, y = -8 } },
  { name = "02_VOICE",        desc = 0x05a954, slot = 0x05a8c8, cap = 7,
    anchor = { x = -128, y = -8 } },
  { name = "03_CONTROLS",     desc = 0x05a8a8, slot = 0x05a800, cap = 10,
    anchor = { x = -128, y = -8 } },
  { name = "04_EXIT",         desc = 0x05a7e0, slot = 0x05a796, cap = 4,
    anchor = { x = -32,  y = -8 },
    -- Four 16-px cells, the same four the button column shows: the EXIT label
    -- is one texture set for both consumers, exactly as in retail.
    cells = true, icons = EXIT_CELLS },
}

-- Action lists 0..11 minus list 3, which has no records in the retail build.
-- List 11 is the shared EXIT and is not an artifact of its own.
local ACTIONS = {
  { index = 0,  name = "SUB_00_NONE" },
  { index = 1,  name = "SUB_01_CONFIRM" },
  { index = 2,  name = "SUB_02_CANCEL" },
  { index = 4,  name = "SUB_04_MAP" },
  { index = 5,  name = "SUB_05_CONSULT" },
  { index = 6,  name = "SUB_06_DEFEND" },
  { index = 7,  name = "SUB_07_WAIT" },
  { index = 8,  name = "SUB_08_ATTACK" },
  { index = 9,  name = "SUB_09_MOVE" },
  { index = 10, name = "SUB_10_DEFAULT" },
}
local ACTION_ANCHOR = { x = -32, y = -8 }

local SPLIT_EXIT_NAME = "SUB_11_EXIT"

local ARTIFACT_PREFIX    = "OPTIONS/"
local BACKGROUND_NAME    = ARTIFACT_PREFIX .. "BACKGROUND.bmp"
local BRACKET_LEFT_NAME  = ARTIFACT_PREFIX .. "BRACKET_LEFT.bmp"
local BRACKET_RIGHT_NAME = ARTIFACT_PREFIX .. "BRACKET_RIGHT.bmp"
local POSITIONS_NAME     = ARTIFACT_PREFIX .. "BRACKET_POSITIONS.json"
local ORIGINS_NAME       = ARTIFACT_PREFIX .. "TEXT_ORIGINS.json"

local BMP_FILE_HEADER = 14
local BMP_INFO_HEADER = 40
local BMP_CLR_USED    = 46              -- 0-based biClrUsed

local function be16(s, off)
  return s:byte(off + 1) * 256 + s:byte(off + 2)
end

local function sbe16(s, off)
  local v = be16(s, off)
  return v >= 0x8000 and v - 0x10000 or v
end

local function be32(s, off)
  return ((s:byte(off + 1) * 256 + s:byte(off + 2)) * 256 + s:byte(off + 3)) * 256
    + s:byte(off + 4)
end

local function ceil8(n)
  return ((n + 7) // 8) * 8
end

-- Pack a 10-byte record; x and y are signed, the rest unsigned.
local function pack_record(x, y, w, h, co)
  return string.pack(">i2i2I2I2I2", x, y, w, h, co)
end

local function parse_record(data, off)
  return {
    x = sbe16(data, off),     y = sbe16(data, off + 2),
    w = be16(data, off + 4),  h = be16(data, off + 6),
    co = be16(data, off + 8),
  }
end

-- Replace #bytes at a 0-based file offset; the length never changes.
local function put(s, offset, bytes)
  return s:sub(1, offset) .. bytes .. s:sub(offset + #bytes + 1)
end

-- True when [pos, pos + len) overlaps one of the five 32-byte descriptors.
local function overlaps_descriptor(pos, len)
  for _, m in ipairs(MAIN) do
    if pos < m.desc + 32 and m.desc < pos + len then
      return m.name
    end
  end
  return nil
end

-- string.char(table.unpack(...)) runs out of stack on a large image, so
-- convert in chunks.
local function bytes_to_string(px)
  local out = {}
  for i = 1, #px, 512 do
    out[#out + 1] = string.char(table.unpack(px, i, math.min(i + 511, #px)))
  end
  return table.concat(out)
end

local function row_stride(width, bpp)
  return ((width * bpp + 31) // 32) * 4
end

-- BGR555 (Saturn, big-endian) -> BGRA (BMP), 8 bits per channel.
local function bgr555_to_bmp(palette, colours)
  local out = {}
  for i = 0, colours - 1 do
    local v = palette:byte(i * 2 + 1) * 256 + palette:byte(i * 2 + 2)
    local b5, g5, r5 = (v >> 10) & 0x1F, (v >> 5) & 0x1F, v & 0x1F
    out[i * 4 + 1] = (b5 * 255 + 15) // 31
    out[i * 4 + 2] = (g5 * 255 + 15) // 31
    out[i * 4 + 3] = (r5 * 255 + 15) // 31
    out[i * 4 + 4] = 0
  end
  return string.char(table.unpack(out))
end

local function build_bmp(pixels, width, height, pal, bpp)
  local stride    = row_stride(width, bpp)
  local row_bytes = width * bpp // 8
  local rows = {}
  for y = 0, height - 1 do
    local row = pixels:sub(y * row_bytes + 1, (y + 1) * row_bytes)
    if #row < row_bytes then row = row .. string.rep("\0", row_bytes - #row) end
    rows[y + 1] = row .. string.rep("\0", stride - row_bytes)
  end
  local body = table.concat(rows)
  local off  = BMP_FILE_HEADER + BMP_INFO_HEADER + #pal
  local hdr = string.pack("<c2I4I2I2I4I4i4i4I2I2I4I4I4I4I4I4",
    "BM", off + #body, 0, 0, off,
    BMP_INFO_HEADER, width, -height, 1, bpp, 0, #body, 0, 0, #pal // 4, 0)
  return hdr .. pal .. body
end

local function parse_bmp(bmp, stage, want_bpp)
  if type(bmp) ~= "string" or #bmp < BMP_FILE_HEADER + BMP_INFO_HEADER then
    error(stage .. ": BMP is too short", 0)
  end
  if bmp:sub(1, 2) ~= "BM" then
    error(stage .. ": not a BMP file", 0)
  end
  local off, info_len, width, height, planes, bpp, comp =
    string.unpack("<I4I4i4i4I2I2I4", bmp, 11)
  if planes ~= 1 then error(stage .. ": biPlanes is not 1", 0) end
  if comp ~= 0 then error(stage .. ": compressed BMP is not supported", 0) end
  if info_len < BMP_INFO_HEADER then error(stage .. ": DIB header is too small", 0) end
  if width <= 0 or height == 0 then error(stage .. ": the image is empty", 0) end
  if want_bpp and bpp ~= want_bpp then
    error(string.format("%s: needs a %dbpp image, this one is %dbpp",
      stage, want_bpp, bpp), 0)
  end
  if bpp ~= 4 and bpp ~= 8 then
    error(string.format("%s: %dbpp is not supported (4 or 8)", stage, bpp), 0)
  end

  height = math.abs(height)
  local bottom_up = string.unpack("<i4", bmp, 23) > 0
  local stride    = row_stride(width, bpp)
  local row_bytes = width * bpp // 8
  if #bmp < off + stride * height then
    error(stage .. ": the pixel data is truncated", 0)
  end

  local rows = {}
  for y = 0, height - 1 do
    local base = off + y * stride
    rows[y + 1] = bmp:sub(base + 1, base + row_bytes)
  end
  if bottom_up then
    local flipped = {}
    for y = 1, height do flipped[y] = rows[height - y + 1] end
    rows = flipped
  end

  -- The palette sits immediately before the pixels; biClrUsed is authoritative
  -- when set, and editors may write a longer DIB header than this codec does.
  local colours = string.unpack("<I4", bmp, BMP_CLR_USED + 1)
  if colours == 0 or colours > (1 << bpp) then colours = 1 << bpp end
  local pal_start = off - colours * 4
  if pal_start < BMP_FILE_HEADER then
    error(string.format("%s: no room for a %d-colour palette before the pixels",
      stage, colours), 0)
  end
  local pal = bmp:sub(pal_start + 1, off)
  return table.concat(rows), width, height, pal, bpp, colours
end

-- Compose records into one linear 4bpp image.  Index 0 is transparent.
-- Returns the packed pixels, width, height and the bounding-box origin.
--
-- `frame` (optional) is the list's canonical cell: the canvas is the union of
-- that cell and the records' own box.  Segments are cropped to their ink, so
-- the records alone would shrink the canvas to the ink height; the union keeps
-- every BMP the size the screen's layout gives it while the ink still lands on
-- its exact row.
local function compose_records(recs, atlas, stage, frame)
  if #recs == 0 then
    error(stage .. ": the list has no records", 0)
  end
  local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
  for _, r in ipairs(recs) do
    x0 = math.min(x0, r.x)
    y0 = math.min(y0, r.y)
    x1 = math.max(x1, r.x + r.w)
    y1 = math.max(y1, r.y + r.h)
  end
  if frame then
    x0 = math.min(x0, frame.x)
    y0 = math.min(y0, frame.y)
    y1 = math.max(y1, frame.y + frame.h)
    x1 = math.max(x1, frame.x + (frame.w or 0))
    -- Cropped ink can end on any column, but a 4bpp row is whole bytes and the
    -- sprite width grid is 8 px, so the canvas keeps that grid from the frame.
    x1 = x0 + ceil8(x1 - x0)
  end

  local w, h = x1 - x0, y1 - y0
  if w <= 0 or h <= 0 then
    error(stage .. ": the records have an empty bounding box", 0)
  end
  if w % 2 ~= 0 then
    error(string.format("%s: composed width is %d, an odd number of pixels; a 4bpp row is whole bytes",
      stage, w), 0)
  end

  local stride = w // 2
  local px = {}
  for i = 1, stride * h do px[i] = 0 end

  for _, r in ipairs(recs) do
    local src_stride = r.w // 2
    local last = r.co * 8 + (r.h - 1) * src_stride + (r.w - 1) // 2
    if last >= #atlas then
      error(string.format(
        "%s: a record at characterOffset %d reads past the %d-byte sheet",
        stage, r.co, #atlas), 0)
    end

    for row = 0, r.h - 1 do
      for col = 0, r.w - 1 do
        local b = atlas:byte(r.co * 8 + row * src_stride + (col >> 1) + 1)
        local v = (col & 1) == 0 and (b >> 4) or (b & 0x0F)
        if v ~= 0 then
          local dx = r.x - x0 + col
          local di = (r.y - y0 + row) * stride + (dx >> 1) + 1
          local db = px[di]
          if (dx & 1) == 0 then
            px[di] = (db & 0x0F) | (v << 4)
          else
            px[di] = (db & 0xF0) | v
          end
        end
      end
    end
  end

  return bytes_to_string(px), w, h, x0, y0
end

-- One pixel of a 4bpp image; 0 outside it so callers may round widths up.
local function nibble(px, w, h, x, y)
  if x < 0 or y < 0 or x >= w or y >= h then return 0 end
  local b = px:byte(y * (w // 2) + (x // 2) + 1)
  return (x & 1) == 0 and (b >> 4) or (b & 0x0F)
end

-- A rectangle as 4bpp bytes, copied pixel by pixel so it may start on any
-- column (the sprite pixels do not have to share the image's byte grid).
--
-- `cw` columns are read and `pw` (>= cw) are stored: the extra columns are
-- transparent.  They must be, because the segment's identity is its bytes.
-- Copying the neighbouring pixels into the padding would make two instances of
-- the same glyph compare unequal whenever their neighbours differ, and the
-- shared atlas would store the glyph twice.
local function cut_rect(px, w, h, x, y, cw, ch, pw)
  pw = pw or cw
  local out = {}
  for r = 0, ch - 1 do
    for c = 0, pw - 1, 2 do
      local hi = c < cw and nibble(px, w, h, x + c, y + r) or 0
      local lo = (c + 1) < cw and nibble(px, w, h, x + c + 1, y + r) or 0
      out[#out + 1] = string.char((hi << 4) | lo)
    end
  end
  return table.concat(out)
end

--[[ Horizontal bands the segmentation may cut between.

  A 16-px label is one band, so its ink keeps one vertical run and a record may
  be as tall as the label.  Taller images (the button column) get one band per
  icon: the first starts at row 0 so the composed image keeps its full frame,
  the rest start at their first inked row and end before the next icon's ink,
  so a band can never swallow the icon below it.
]]
local function bands_of(px, w, h)
  local iw = w // 2
  local blank = string.rep("\0", iw)
  local row_ink = {}
  for y = 0, h - 1 do row_ink[y] = px:sub(y * iw + 1, (y + 1) * iw) ~= blank end

  local bands, y, first = {}, 0, true
  while y < h do
    local top, bottom
    if h == LABEL_H then
      top, bottom = 0, LABEL_H
    else
      if first then
        top = 0
      else
        while y < h and not row_ink[y] do y = y + 1 end
        top = y
        if top >= h then break end
      end
      local limit = math.min(h, top + LABEL_H)
      local last = top - 1
      for r = top, limit - 1 do if row_ink[r] then last = r end end
      if last < top then
        bottom = limit
      else
        local nexty = last + 1
        while nexty < h and not row_ink[nexty] do nexty = nexty + 1 end
        bottom = math.min(limit, nexty)
        if bottom <= last then bottom = last + 1 end
      end
    end
    bands[#bands + 1] = { top = top, bottom = bottom }
    y = bottom
    first = false
  end
  return bands
end

-- Maximal runs of columns that hold ink, bridging blank gaps of at most
-- `gap` columns: a gap narrower than a sprite's padding costs atlas space but
-- saves a record, which is the scarcer resource.
local function ink_runs(px, w, h, top, bottom, gap)
  local function ink(x)
    for r = top, bottom - 1 do
      if nibble(px, w, h, x, r) ~= 0 then return true end
    end
    return false
  end

  local runs, x = {}, 0
  while x < w do
    while x < w and not ink(x) do x = x + 1 end
    if x >= w then break end
    local s, e = x, x
    while true do
      while x < w and ink(x) do e = x; x = x + 1 end
      local blank = x
      while blank < w and not ink(blank) do blank = blank + 1 end
      if blank < w and (blank - x) <= gap then
        e = blank
        x = blank
      else
        break
      end
    end
    runs[#runs + 1] = { s = s, e = e }
  end
  return runs
end

-- The ink box of [x0, x1] x [top, bottom - 1], or nil when it is empty.
local function ink_box(px, w, h, x0, x1, top, bottom)
  local left, right, first, last
  for x = x0, x1 do
    for r = top, bottom - 1 do
      if nibble(px, w, h, x, r) ~= 0 then
        left = left or x
        right = x
        break
      end
    end
  end
  if not left then return nil end
  for r = top, bottom - 1 do
    for x = left, right do
      if nibble(px, w, h, x, r) ~= 0 then
        first = first or r
        last = r
        break
      end
    end
  end
  return left, first, right - left + 1, last - first + 1
end

-- Split [s, e] into pieces no wider than `maxw`; every piece but the last is
-- a multiple of 8 px, the sprite width grid.
local function split_run(s, e, maxw)
  local pieces, at = {}, s
  while at <= e do
    local remaining = e - at + 1
    local take = math.min(maxw, remaining)
    if at + take - 1 < e then take = math.max(LABEL_ALIGN, (take // LABEL_ALIGN) * LABEL_ALIGN) end
    pieces[#pieces + 1] = { s = at, e = at + take - 1 }
    at = at + take
  end
  return pieces
end

--[[ Split one image into reusable rectangles.

  `opts` picks the strategy:

    cells = true      16-px columns from the image origin, one record per cell
                      that holds ink (the button column, whose 12 records the
                      drawer reads unconditionally)
    gap, maxw         ink runs, split no wider than `maxw`

  Both crop every rectangle to its own ink box: rows that hold nothing are
  dropped and the record's y moves down to compensate, and the same happens on
  the columns.  Cropping never changes which pixel lands where, so the rendered
  image is exact; it only stops transparent margins from being stored.

  All widths round up to 8 px, the smallest sprite width a 4bpp VDP1 record can
  address, and the extra columns are transparent.
]]
local function segments_of(px, w, h, stage, opts)
  if w % LABEL_ALIGN ~= 0 then
    error(string.format("%s: width %d is not a multiple of %d",
      stage, w, LABEL_ALIGN), 0)
  end
  opts = opts or {}
  local segs = {}

  for _, band in ipairs(bands_of(px, w, h)) do
    local spans = {}
    if opts.cells then
      for x = 0, w - 1, LABEL_H do
        spans[#spans + 1] = { s = x, e = math.min(x + LABEL_H, w) - 1 }
      end
    else
      for _, run in ipairs(ink_runs(px, w, h, band.top, band.bottom, opts.gap or 0)) do
        for _, piece in ipairs(split_run(run.s, run.e, opts.maxw or LABEL_H)) do
          spans[#spans + 1] = piece
        end
      end
    end

    local band_segs = {}
    for _, span in ipairs(spans) do
      local x, y, cw, ch = ink_box(px, w, h, span.s, span.e, band.top, band.bottom)
      if x then
        band_segs[#band_segs + 1] = { x = x, y = y, cw = cw, w = ceil8(cw), h = ch }
      end
    end

    -- The last sprite has to reach the artboard's right edge, or decode would
    -- compose a narrower canvas than the image the translator saved: the rows
    -- are cropped to their ink, and a list whose last glyph ends two columns
    -- short would lose those two columns on every round trip.  So the final
    -- sprite is shifted left until its padded width lands exactly on the edge
    -- and re-read from there; the columns it gains are transparent, which costs
    -- a padded block of zeroes and nothing else.
    --
    -- The button column is no exception: its last inked cell lands on column
    -- 64 of an 80-px artboard, so the widened cell is exactly a 16-px cell and
    -- the twelve icons keep their one-record-each mapping.
    if #band_segs > 0 then
      local last = band_segs[#band_segs]
      last.w = ceil8(w - last.x)
      last.x = w - last.w
      last.cw = last.w
    end

    for _, s in ipairs(band_segs) do
      s.data = cut_rect(px, w, h, s.x, s.y, s.cw, s.h, s.w)
      segs[#segs + 1] = s
    end
  end

  return segs
end

-- Total order for the atlas: same height first (a PRS match can then span a
-- segment boundary), then width, then the pixels themselves.  The comparator
-- is total, so the layout is identical on every run.
local function segment_before(a, b)
  if a.h ~= b.h then return a.h < b.h end
  if a.w ~= b.w then return a.w < b.w end
  if a.data ~= b.data then return a.data < b.data end
  return a.first < b.first
end

--[[ Store each distinct rectangle once and turn every segment into a record.

  Deduplication is exact: the key is the pixel bytes plus the size, so two
  letters share a rectangle only when they are identical.  The sheet is laid
  out in `segment_before` order, not first-use order: identical and similar
  shapes end up next to each other, which is what the PRS encoder can match.

  Every rectangle is padded to 8 bytes, the granularity of a VDP1
  characterOffset, so the padding is transparent and never stored as ink.

  Returns the sheet and the unique rectangles, or nil plus a message when the
  decoded budget is exceeded (the caller may try another segmentation).
]]
local function build_atlas(entries)
  local index, list = {}, {}

  for _, e in ipairs(entries) do
    for _, s in ipairs(e.segs) do
      local key = s.w .. "x" .. s.h .. ":" .. s.data
      if not index[key] then
        index[key] = { w = s.w, h = s.h, data = s.data, first = #list + 1 }
        list[#list + 1] = index[key]
      end
    end
  end

  table.sort(list, segment_before)

  local parts, at = {}, 0
  for i, s in ipairs(list) do
    s.offset = at
    parts[i] = s.data .. string.rep("\0", ceil8(#s.data) - #s.data)
    at = at + ceil8(#s.data)
  end
  local sheet = table.concat(parts)

  if at > ATLAS_LIMIT then
    return nil, string.format(
      "the shared atlas needs %d decoded bytes, over the %d-byte limit (0x2d00, the next texture at VDP1 0x6f000)",
      at, ATLAS_LIMIT)
  end
  if at == 0 then
    return nil, "no text pixels at all; every label is blank"
  end

  for _, e in ipairs(entries) do
    e.records = {}
    for _, s in ipairs(e.segs) do
      local hit = index[s.w .. "x" .. s.h .. ":" .. s.data]
      e.records[#e.records + 1] = {
        x = e.anchor.x + s.x,
        y = e.anchor.y + s.y,
        w = s.w,
        h = s.h,
        co = hit.offset // 8,
      }
    end
  end

  return sheet, list
end

-- One list's records, read from the parent (decode) or built from an image.
local function records_for(recs, name, stage)
  local out = {}
  for k, r in ipairs(recs) do
    if r.w == 0 or r.h == 0 then
      error(string.format("%s: %s record %d is an empty sprite", stage, name, k), 0)
    end
    if r.w % 2 ~= 0 then
      error(string.format("%s: %s record %d has an odd width %d; a 4bpp row is whole bytes",
        stage, name, k, r.w), 0)
    end
    out[k] = r
  end
  return out
end

-- Read every text list in the parent.  All pointers are 0x06004000-relative in
-- the shipped file; a raw file offset is accepted too.
local function read_text(data, stage)
  local main = {}
  for _, m in ipairs(MAIN) do
    local off = m.desc
    if off + 32 > #data then
      error(string.format("%s: the %s descriptor at 0x%06X is outside the file",
        stage, m.name, off), 0)
    end
    local count = be16(data, off + 12)
    local base  = be32(data, off + 20)
    if base ~= TEXTURE_BASE then
      error(string.format("%s: the %s texture base is 0x%04X, expected 0x%04X",
        stage, m.name, base, TEXTURE_BASE), 0)
    end
    if count < 1 or count > MAX_RECORDS then
      error(string.format("%s: the %s label count is %d at +12; expected 1..%d",
        stage, m.name, count, MAX_RECORDS), 0)
    end
    local ptr = be32(data, off + 16)
    local pos = ptr >= RAM_BASE and ptr - RAM_BASE or ptr
    if pos + count * RECORD_BYTES > #data then
      error(string.format(
        "%s: the %s record list 0x%08X (+16) does not fit: %d bytes from 0x%06X, the file ends at 0x%06X",
        stage, m.name, ptr, count * RECORD_BYTES, pos, #data), 0)
    end
    local recs = {}
    for k = 0, count - 1 do recs[k + 1] = parse_record(data, pos + k * RECORD_BYTES) end
    main[#main + 1] = {
      name = m.name, def = m, pos = pos, count = count,
      recs = records_for(recs, m.name, stage),
    }
  end

  local actions = {}
  for i = 0, ACTION_COUNT - 1 do
    local count = data:byte(ACTION_TABLE + i + 1)
    local ptr = be32(data, ACTION_POINTERS + i * 4)
    local pos = ptr >= RAM_BASE and ptr - RAM_BASE or ptr
    if count > MAX_RECORDS then
      error(string.format("%s: action list %d has %d records; expected at most %d",
        stage, i, count, MAX_RECORDS), 0)
    end
    if count > 0 and pos + count * RECORD_BYTES > #data then
      error(string.format(
        "%s: action list %d (0x%08X) does not fit: %d bytes from 0x%06X",
        stage, i, ptr, count * RECORD_BYTES, pos), 0)
    end
    local recs = {}
    for k = 0, count - 1 do recs[k + 1] = parse_record(data, pos + k * RECORD_BYTES) end
    actions[i] = { index = i, pos = pos, count = count, recs = recs }
  end

  local function fixed(pos, count, name)
    if pos + count * RECORD_BYTES > #data then
      error(string.format("%s: the %s list at 0x%06X is outside the file",
        stage, name, pos), 0)
    end
    local recs = {}
    for k = 0, count - 1 do recs[k + 1] = parse_record(data, pos + k * RECORD_BYTES) end
    return { pos = pos, count = count, recs = recs }
  end

  return {
    main = main,
    actions = actions,
    button = fixed(BUTTON_REC, BUTTON_COUNT, "button column"),
    mini = fixed(MINI_REC, MINI_COUNT, "mini label"),
  }
end

-- The twelve action-list artifacts, by list index; list 3 is empty in retail.
local ACTION_BY_INDEX = {}
for _, a in ipairs(ACTIONS) do ACTION_BY_INDEX[a.index] = a end
local EXIT_INDEX = 11

local function atlas_of(data)
  return prs:decode(data:sub(ATLAS_OFFSET + 1, ATLAS_OFFSET + ATLAS_SLOT))[1].data
end

-- The only argument is `rebuild=auto|always`; decode validates it so a typo in
-- the manifest fails at decode time, and encode consumes it.  An empty table is
-- treated as "no arguments" because the house test harness passes `{}`.
local function parse_args(args)
  if type(args) == "table" and next(args) == nil then args = nil end
  return args_parser.parse(args, {
    rebuild = { values = { "auto", "always" }, default = "auto" },
  }, "options menu gfx")
end

-- BMP palette from the parent's second 16-colour bank (label glyphs).
local function preview_palette(data, stage)
  if #data < PALETTE_TEXT + PALETTE_BANK_BYTES then
    error(string.format("%s: the options palette at 0x%06X is outside the file",
      stage, PALETTE_TEXT), 0)
  end
  local pal = bgr555_to_bmp(data:sub(PALETTE_TEXT + 1, PALETTE_TEXT + PALETTE_BANK_BYTES), 16)
  return pal:sub(1, 60) .. "\x00\x00\xFF\x00"
end

-- The background uses the *first* bank of the same 64-byte palette block.
local function background_palette(data, stage)
  if #data < PALETTE_OFFSET + PALETTE_BANK_BYTES then
    error(string.format("%s: the options palette at 0x%06X is outside the file",
      stage, PALETTE_OFFSET), 0)
  end
  return bgr555_to_bmp(
    data:sub(PALETTE_OFFSET + 1, PALETTE_OFFSET + PALETTE_BANK_BYTES), 16)
end

-- A second, private copy of the project's minimal JSON reader.  font.lua keeps
-- its version local; copying the ~90 lines here avoids changing that codec.
local function json_decode(text)
  local i = 1
  local function skip_ws()
    while i <= #text and text:sub(i, i):match("%s") do i = i + 1 end
  end
  local function parse_val()
    skip_ws()
    local c = text:sub(i, i)
    if c == '"' then
      i = i + 1
      local start = i
      while i <= #text and text:sub(i, i) ~= '"' do
        if text:sub(i, i) == '\\' then i = i + 2 else i = i + 1 end
      end
      if i > #text then error("unterminated string", 0) end
      local str = text:sub(start, i - 1)
      i = i + 1
      return str
    elseif c == '{' then
      i = i + 1
      local obj = {}
      while true do
        skip_ws()
        if text:sub(i, i) == '}' then i = i + 1 return obj end
        local key = parse_val()
        if type(key) ~= "string" then error("object key is not a string", 0) end
        skip_ws()
        if text:sub(i, i) ~= ':' then error("expected ':'", 0) end
        i = i + 1
        obj[key] = parse_val()
        skip_ws()
        if text:sub(i, i) == '}' then i = i + 1 return obj end
        if text:sub(i, i) ~= ',' then error("expected ',' or '}'", 0) end
        i = i + 1
      end
    elseif c == '[' then
      i = i + 1
      local arr = {}
      while true do
        skip_ws()
        if text:sub(i, i) == ']' then i = i + 1 return arr end
        arr[#arr + 1] = parse_val()
        skip_ws()
        if text:sub(i, i) == ']' then i = i + 1 return arr end
        if text:sub(i, i) ~= ',' then error("expected ',' or ']'", 0) end
        i = i + 1
      end
    elseif c == 't' then
      if text:sub(i, i + 3) == "true" then i = i + 4 return true end
    elseif c == 'f' then
      if text:sub(i, i + 4) == "false" then i = i + 5 return false end
    elseif c == 'n' then
      if text:sub(i, i + 3) == "null" then i = i + 4 return nil end
    elseif c:match("[%d%-]") then
      local start = i
      while i <= #text and text:sub(i, i):match("[%d%.%-eE]+") do i = i + 1 end
      return tonumber(text:sub(start, i - 1))
    end
    error("unexpected character at byte " .. i, 0)
  end

  skip_ws()
  local val = parse_val()
  skip_ws()
  if i <= #text then error("trailing characters after the value", 0) end
  return val
end

local function only_keys(tbl, allowed, where, stage)
  for key in pairs(tbl) do
    if not allowed[key] then
      error(string.format("%s: %s has an unknown key %q", stage, where, key), 0)
    end
  end
end

-- Every text list's anchor, in a stable order: 5 main rows, 10 action lists,
-- then the button column.
local function default_origins()
  local list = {}
  for _, m in ipairs(MAIN) do
    list[#list + 1] = { name = m.name, x = m.anchor.x, y = m.anchor.y }
  end
  for _, a in ipairs(ACTIONS) do
    list[#list + 1] = { name = a.name, x = ACTION_ANCHOR.x, y = ACTION_ANCHOR.y }
  end
  list[#list + 1] = { name = SPLIT_EXIT_NAME, x = ACTION_ANCHOR.x, y = ACTION_ANCHOR.y }
  list[#list + 1] = { name = BUTTON_ABC_NAME, x = BUTTON_ABC_ANCHOR.x, y = BUTTON_ABC_ANCHOR.y }
  list[#list + 1] = { name = BUTTON_XYZLR_NAME, x = BUTTON_XYZLR_ANCHOR.x, y = BUTTON_XYZLR_ANCHOR.y }
  return list
end

local function origins_json(list)
  local out = { "{\n  \"origins\": [" }
  for i, entry in ipairs(list) do
    out[#out + 1] = string.format(
      "%s    { \"name\": \"%s\", \"x\": %d, \"y\": %d }",
      i == 1 and "\n" or ",\n", entry.name, entry.x, entry.y)
  end
  out[#out + 1] = "\n  ]\n}\n"
  return table.concat(out)
end

-- Returns name -> {x, y}.  Absent entries fall back to the retail anchors.
local function parse_origins(text, stage)
  local ok, root = pcall(json_decode, text)
  if not ok then
    error(stage .. ": invalid JSON: " .. tostring(root), 0)
  end
  if type(root) ~= "table" then
    error(stage .. ": the top level must be an object", 0)
  end
  only_keys(root, { origins = true }, "the top level", stage)
  if type(root.origins) ~= "table" or type(root.origins[1]) ~= "table" then
    error(stage .. ": expected a non-empty \"origins\" array", 0)
  end

  local known = {}
  for _, entry in ipairs(default_origins()) do known[entry.name] = true end

  local out = {}
  for i, entry in ipairs(root.origins) do
    local where = "origins[" .. i .. "]"
    if type(entry) ~= "table" then
      error(stage .. ": " .. where .. " must be an object", 0)
    end
    only_keys(entry, { name = true, x = true, y = true }, where, stage)
    if type(entry.name) ~= "string" or not known[entry.name] then
      error(string.format("%s: %s has an unknown name %q", stage, where,
        tostring(entry.name)), 0)
    end
    if out[entry.name] then
      error(string.format("%s: %q appears twice", stage, entry.name), 0)
    end
    for _, key in ipairs({ "x", "y" }) do
      local value = entry[key]
      if type(value) ~= "number" or value % 1 ~= 0 then
        error(string.format("%s: %s.%s must be an integer", stage, where, key), 0)
      end
      if value < -32768 or value > 32767 then
        error(string.format("%s: %s.%s = %d is outside the signed 16-bit range",
          stage, where, key, value), 0)
      end
    end
    out[entry.name] = { x = entry.x, y = entry.y }
  end

  for _, entry in ipairs(default_origins()) do
    if not out[entry.name] then
      out[entry.name] = { x = entry.x, y = entry.y }
    end
  end
  return out
end

-- The selection-mark geometry: descriptor +4 is the choice count, +24 is a
-- list of 20-byte pairs (left record, right record) per choice and +28 is one
-- BE u32 per choice whose low s16 is the centre.  Unlike the +16 label list,
-- these two lists are read only by the drawer's second pass.
local function read_positions(data, stage)
  local rows = {}

  for _, m in ipairs(MAIN) do
    local off = m.desc
    if off + 32 > #data then
      error(string.format("%s: the %s descriptor at 0x%06X is outside the file",
        stage, m.name, off), 0)
    end

    local count = be16(data, off + 4)
    if count < 1 or count > MAX_CHOICES then
      error(string.format("%s: the %s choice count is %d at +4; expected 1..%d",
        stage, m.name, count, MAX_CHOICES), 0)
    end

    local pair_ptr   = be32(data, off + 24)
    local centre_ptr = be32(data, off + 28)
    local pair_pos   = pair_ptr >= RAM_BASE and pair_ptr - RAM_BASE or pair_ptr
    local centre_pos = centre_ptr >= RAM_BASE and centre_ptr - RAM_BASE or centre_ptr
    local pair_len   = count * 20
    local centre_len = count * 4

    if pair_pos + pair_len > #data then
      error(string.format(
        "%s: the %s +24 list 0x%08X does not fit: %d bytes from 0x%06X, the file ends at 0x%06X",
        stage, m.name, pair_ptr, pair_len, pair_pos, #data), 0)
    end
    if centre_pos + centre_len > #data then
      error(string.format(
        "%s: the %s +28 list 0x%08X does not fit: %d bytes from 0x%06X, the file ends at 0x%06X",
        stage, m.name, centre_ptr, centre_len, centre_pos, #data), 0)
    end

    local choices = {}
    for k = 0, count - 1 do
      local ro = pair_pos + k * 20
      local left  = parse_record(data, ro)
      local right = parse_record(data, ro + 10)
      if left.w == 0 or left.h == 0 or right.w == 0 or right.h == 0 then
        error(string.format("%s: %s choice %d has an empty mark sprite",
          stage, m.name, k), 0)
      end

      local co = centre_pos + k * 4
      choices[k + 1] = {
        center  = sbe16(data, co),
        center2 = be16(data, co + 2),
        left    = left,
        right   = right,
      }
    end

    rows[#rows + 1] = {
      name       = m.name,
      desc_off   = off,
      count      = count,
      pair_ptr   = pair_ptr,
      centre_ptr = centre_ptr,
      pair_pos   = pair_pos,
      centre_pos = centre_pos,
      choices    = choices,
    }
  end

  return rows
end

-- Metadata is deliberately small and declarative: one entry per row, one entry
-- per choice, with the three values a layout edit actually needs.  Everything
-- else in the pair records (y, w, h, characterOffset) is preserved.
local function positions_json(rows)
  local out = { "{\n  \"rows\": [" }
  for i, row in ipairs(rows) do
    out[#out + 1] = string.format(
      "%s    {\n      \"name\": \"%s\",\n      \"choices\": [",
      i == 1 and "\n" or ",\n", row.name)
    for k, choice in ipairs(row.choices) do
      out[#out + 1] = string.format(
        "%s        { \"center\": %d, \"left\": %d, \"right\": %d }",
        k == 1 and "\n" or ",\n", choice.center, choice.left.x, choice.right.x)
    end
    out[#out + 1] = "\n      ]\n    }"
  end
  out[#out + 1] = "\n  ]\n}\n"
  return table.concat(out)
end

-- Validate the metadata and return { ROW_NAME = { {center,left,right}, ... } }.
local function parse_positions(text, rows, stage)
  local ok, root = pcall(json_decode, text)
  if not ok then
    error(stage .. ": invalid JSON: " .. tostring(root), 0)
  end
  if type(root) ~= "table" then
    error(stage .. ": the top level must be an object", 0)
  end
  only_keys(root, { rows = true }, "the top level", stage)
  if type(root.rows) ~= "table" or type(root.rows[1]) ~= "table" then
    error(stage .. ": expected a non-empty \"rows\" array", 0)
  end

  local expected = {}
  for _, row in ipairs(rows) do expected[row.name] = row.count end

  local by_name = {}
  for i, entry in ipairs(root.rows) do
    local where = "rows[" .. i .. "]"
    if type(entry) ~= "table" then
      error(stage .. ": " .. where .. " must be an object", 0)
    end
    only_keys(entry, { name = true, choices = true }, where, stage)
    if type(entry.name) ~= "string" then
      error(stage .. ": " .. where .. ".name must be a string", 0)
    end
    if not expected[entry.name] then
      error(string.format("%s: unknown row %q", stage, entry.name), 0)
    end
    if by_name[entry.name] then
      error(string.format("%s: row %q appears twice", stage, entry.name), 0)
    end
    if type(entry.choices) ~= "table" then
      error(string.format("%s: %s.choices must be an array", stage, where), 0)
    end

    local choices = {}
    for k, choice in ipairs(entry.choices) do
      local cwhere = where .. ".choices[" .. k .. "]"
      if type(choice) ~= "table" then
        error(stage .. ": " .. cwhere .. " must be an object", 0)
      end
      only_keys(choice, { center = true, left = true, right = true }, cwhere, stage)
      for _, key in ipairs({ "center", "left", "right" }) do
        local value = choice[key]
        if type(value) ~= "number" or value % 1 ~= 0 then
          error(string.format("%s: %s.%s must be an integer", stage, cwhere, key), 0)
        end
        if value < -32768 or value > 32767 then
          error(string.format("%s: %s.%s = %d is outside the signed 16-bit range",
            stage, cwhere, key, value), 0)
        end
      end
      choices[k] = { center = choice.center, left = choice.left, right = choice.right }
    end

    if #choices ~= expected[entry.name] then
      error(string.format("%s: %s has %d choices, but the descriptor says %d",
        stage, entry.name, #choices, expected[entry.name]), 0)
    end
    by_name[entry.name] = choices
  end

  for _, row in ipairs(rows) do
    if not by_name[row.name] then
      error(string.format("%s: row %q is missing", stage, row.name), 0)
    end
  end

  return by_name
end

-- Build the two lists without touching y, w, h or characterOffset.  Returns
-- whether anything differs and one write per list that differs.
local function encode_positions(rows, meta, data, stage, protected)
  local writes, changed = {}, false

  for _, row in ipairs(rows) do
    local values = meta[row.name]
    local pair_parts, centre_parts = {}, {}
    for k, src in ipairs(row.choices) do
      local value = values[k]
      pair_parts[#pair_parts + 1] = pack_record(value.left,
        src.left.y, src.left.w, src.left.h, src.left.co)
      pair_parts[#pair_parts + 1] = pack_record(value.right,
        src.right.y, src.right.w, src.right.h, src.right.co)
      local word = (value.center & 0xffff) * 65536 + src.center2
      centre_parts[#centre_parts + 1] = string.pack(">I4", word)
    end

    local pair_bytes   = table.concat(pair_parts)
    local centre_bytes = table.concat(centre_parts)
    local old_pair = data:sub(row.pair_pos + 1, row.pair_pos + #pair_bytes)
    local old_centre = data:sub(row.centre_pos + 1, row.centre_pos + #centre_bytes)
    if pair_bytes ~= old_pair then
      changed = true
      writes[#writes + 1] = { offset = row.pair_pos, data = pair_bytes, name = row.name .. " +24" }
    end
    if centre_bytes ~= old_centre then
      changed = true
      writes[#writes + 1] = { offset = row.centre_pos, data = centre_bytes, name = row.name .. " +28" }
    end
  end

  if not changed then return false, {} end

  -- Distinct lists, and none may sit inside a descriptor, the atlas, the
  -- background stream or a text record that the same encode will write.
  for _, write in ipairs(writes) do
    if write.offset < 0 or write.offset + #write.data > #data then
      error(string.format("%s: the %s list runs outside the file", stage, write.name), 0)
    end
    local clash = overlaps_descriptor(write.offset, #write.data)
    if clash then
      error(string.format("%s: the %s list overlaps the %s descriptor",
        stage, write.name, clash), 0)
    end
    for _, range in ipairs({
      { ATLAS_OFFSET, ATLAS_OFFSET + ATLAS_SLOT, "atlas slot" },
      { BACKGROUND_OFFSET, BACKGROUND_OFFSET + BACKGROUND_SLOT, "background slot" },
    }) do
      if write.offset < range[2] and range[1] < write.offset + #write.data then
        error(string.format("%s: the %s list overlaps the %s",
          stage, write.name, range[3]), 0)
      end
    end
    for _, range in ipairs(protected or {}) do
      if write.offset < range[2] and range[1] < write.offset + #write.data then
        error(string.format("%s: the %s list overlaps %s",
          stage, write.name, range[3]), 0)
      end
    end
  end

  for i = 1, #writes do
    for j = i + 1, #writes do
      local a, b = writes[i], writes[j]
      if a.offset < b.offset + #b.data and b.offset < a.offset + #a.data then
        error(string.format("%s: the %s and %s lists overlap",
          stage, a.name, b.name), 0)
      end
    end
  end

  return true, writes
end

-- Statistics of the last encode, for tests and documentation.  Nothing in the
-- codec depends on it.
codec.stats = nil

function codec.decode(data, args)
  if type(data) ~= "string" then
    error("decode: expected binary data, got " .. type(data), 0)
  end
  parse_args(args)
  if #data < ATLAS_OFFSET + ATLAS_SLOT then
    error(string.format("decode: the file is %d bytes; the options atlas slot ends at 0x%06X",
      #data, ATLAS_OFFSET + ATLAS_SLOT), 0)
  end

  local atlas = atlas_of(data)
  if #atlas < 1 then
    error("decode: the options atlas decompresses to nothing", 0)
  end
  if #atlas > ATLAS_LIMIT then
    error(string.format("decode: the options atlas decompresses to %d bytes, over the 11,520-byte limit",
      #atlas), 0)
  end

  if #data < BACKGROUND_OFFSET + BACKGROUND_SLOT then
    error(string.format("decode: the file is %d bytes; the options background slot ends at 0x%06X",
      #data, BACKGROUND_OFFSET + BACKGROUND_SLOT), 0)
  end
  local background = prs:decode(
    data:sub(BACKGROUND_OFFSET + 1, BACKGROUND_OFFSET + BACKGROUND_SLOT))[1].data
  if #background < BACKGROUND_END then
    error(string.format(
      "decode: the options background decompresses to %d bytes, expected at least %d (the panel plus the 128-byte mark pair)",
      #background, BACKGROUND_END), 0)
  end

  local text = read_text(data, "decode")
  local positions = read_positions(data, "decode")
  local pal = preview_palette(data, "decode")
  local bg_pal = background_palette(data, "decode")

  local artifacts = {}
  local origins = {}

  -- Every list keeps the canvas its layout gives it: segments are cropped to
  -- their ink, so the records alone are shorter than the 16-px row the
  -- translator edits.  The frame is the retail anchor plus that height.
  local frame_of = {}
  for _, entry in ipairs(default_origins()) do
    frame_of[entry.name] = { x = entry.x, y = entry.y }
  end
  local function frame_for(name, h)
    local f = frame_of[name]
    return { x = f.x, y = f.y, h = h }
  end

  for _, label in ipairs(text.main) do
    local stage = "decode: " .. label.name
    local px, w, h, x0, y0 =
      compose_records(label.recs, atlas, stage, frame_for(label.name, LABEL_H))
    if h ~= LABEL_H then
      error(string.format("%s: composed height %d, expected %d", stage, h, LABEL_H), 0)
    end
    artifacts[#artifacts + 1] = {
      name = ARTIFACT_PREFIX .. label.name .. ".bmp",
      data = build_bmp(px, w, h, pal, 4),
    }
    origins[#origins + 1] = { name = label.name, x = x0, y = y0 }
  end

  for _, action in ipairs(ACTIONS) do
    local list = text.actions[action.index]
    if list.count > 0 then
      local stage = "decode: " .. action.name
      local px, w, h, x0, y0 =
        compose_records(list.recs, atlas, stage, frame_for(action.name, LABEL_H))
      if h ~= LABEL_H then
        error(string.format("%s: composed height %d, expected %d", stage, h, LABEL_H), 0)
      end
      artifacts[#artifacts + 1] = {
        name = ARTIFACT_PREFIX .. action.name .. ".bmp",
        data = build_bmp(px, w, h, pal, 4),
      }
      origins[#origins + 1] = { name = action.name, x = x0, y = y0 }
    end
  end

  -- Action list 11 is the controller screen's EXIT.  In retail it points at
  -- the main row's list, so the two artifacts start out identical; showing it
  -- separately is what lets a translation give the submenu its own label.
  local exit_list = text.actions[EXIT_INDEX]
  if exit_list.count > 0 then
    local stage = "decode: " .. SPLIT_EXIT_NAME
    local px, w, h, x0, y0 =
      compose_records(exit_list.recs, atlas, stage, frame_for(SPLIT_EXIT_NAME, LABEL_H))
    artifacts[#artifacts + 1] = {
      name = ARTIFACT_PREFIX .. SPLIT_EXIT_NAME .. ".bmp",
      data = build_bmp(px, w, h, pal, 4),
    }
    origins[#origins + 1] = { name = SPLIT_EXIT_NAME, x = x0, y = y0 }
  end

  -- The button column has no artifact of its own.  Its first eight records are
  -- the two button boards; its last four spell EXIT and are composed from the
  -- same records as SUB_11_EXIT above, so that art is exposed and edited once.
  local function push_board(name, recs, anchor, want_h)
    local stage = "decode: " .. name
    local px, w, h, x0, y0 = compose_records(recs, atlas, stage,
      { x = anchor.x, y = anchor.y, w = EXIT_CELL_WIDTH, h = want_h })
    if h ~= want_h then
      error(string.format("%s: composes to %d rows, but the button column draws it at %d",
        stage, h, want_h), 0)
    end
    artifacts[#artifacts + 1] = {
      name = ARTIFACT_PREFIX .. name .. ".bmp",
      data = build_bmp(px, w, h, pal, 4),
    }
    origins[#origins + 1] = { name = name, x = x0, y = y0 }
  end

  local column = text.button.recs
  push_board(BUTTON_ABC_NAME,
    { column[1], column[2], column[3] }, BUTTON_ABC_ANCHOR, BUTTON_ABC_H)
  push_board(BUTTON_XYZLR_NAME,
    { column[4], column[5], column[6], column[7], column[8] },
    BUTTON_XYZLR_ANCHOR, BUTTON_XYZLR_H)

  artifacts[#artifacts + 1] = {
    name = BACKGROUND_NAME,
    data = build_bmp(
      background:sub(1, BACKGROUND_PIXELS), BACKGROUND_W, BACKGROUND_H,
      bg_pal, 4),
  }

  -- The mark texture is the last 128 bytes of the same background stream.  It
  -- is not in the text atlas, so it is exposed separately and previewed with
  -- the background's own bank (0x05ad98).  The BMP palette never reaches the
  -- file; encode compares pixels only.
  artifacts[#artifacts + 1] = {
    name = BRACKET_LEFT_NAME,
    data = build_bmp(
      background:sub(BRACKET_OFFSET + 1, BRACKET_OFFSET + BRACKET_BYTES),
      BRACKET_W, BRACKET_H, bg_pal, 4),
  }
  artifacts[#artifacts + 1] = {
    name = BRACKET_RIGHT_NAME,
    data = build_bmp(
      background:sub(BRACKET_OFFSET + BRACKET_BYTES + 1, BRACKET_OFFSET + 2 * BRACKET_BYTES),
      BRACKET_W, BRACKET_H, bg_pal, 4),
  }

  artifacts[#artifacts + 1] = {
    name = POSITIONS_NAME,
    data = positions_json(positions),
  }
  artifacts[#artifacts + 1] = {
    name = ORIGINS_NAME,
    data = origins_json(origins),
  }

  return artifacts
end

function codec.encode(original, artifacts, args)
  if type(original) ~= "string" then
    error("encode: expected the parent bytes, got " .. type(original), 0)
  end
  if #original < ATLAS_OFFSET + ATLAS_SLOT then
    error("encode: the parent is too small for the options atlas slot", 0)
  end

  local opts = parse_args(args)

  local text = read_text(original, "encode")
  local positions = read_positions(original, "encode")

  local by_name = {}
  for _, artifact in ipairs(artifacts or {}) do
    if type(artifact) == "table" and type(artifact.name) == "string"
      and type(artifact.data) == "string" then
      by_name[artifact.name] = artifact.data
    end
  end

  -- Origin metadata is optional: absent entries keep the retail anchors.
  local origins = {}
  for _, entry in ipairs(default_origins()) do
    origins[entry.name] = { x = entry.x, y = entry.y }
  end
  if by_name[ORIGINS_NAME] then
    origins = parse_origins(by_name[ORIGINS_NAME], "encode: " .. ORIGINS_NAME)
  end

  -- Read one text artifact.  `want_h` is the height the screen's layout gives
  -- that list: 16 for a label row, 160 for the button column.  Decode rejects a
  -- parent whose rows do not compose to 16, so an encode that accepted another
  -- height would produce a file it cannot read.
  local function load_text(name, anchor, stage, want_h, flags)
    local bmp = by_name[ARTIFACT_PREFIX .. name .. ".bmp"]
    if not bmp then
      error("encode: " .. ARTIFACT_PREFIX .. name .. ".bmp is missing", 0)
    end
    local px, w, h = parse_bmp(bmp, stage, 4)
    if want_h and h ~= want_h then
      error(string.format("%s: %d pixels high, but the screen draws this list at %d",
        stage, h, want_h), 0)
    end
    if w > LABEL_MAX_W then
      error(string.format("%s: %d pixels wide; a VDP1 record can express at most %d",
        stage, w, LABEL_MAX_W), 0)
    end
    if w == 0 or w % LABEL_ALIGN ~= 0 then
      error(string.format("%s: %d pixels wide, not a positive multiple of %d",
        stage, w, LABEL_ALIGN), 0)
    end
    flags = flags or {}
    return {
      name = name, anchor = anchor, px = px, w = w, h = h, stage = stage,
      records = {}, cells = flags.cells, required = flags.required,
      icons = flags.icons,
    }
  end

  local entries = {}
  for _, m in ipairs(MAIN) do
    entries[#entries + 1] = load_text(m.name, origins[m.name],
      "encode: " .. ARTIFACT_PREFIX .. m.name .. ".bmp", LABEL_H,
      { required = true, cells = m.cells, icons = m.icons })
  end
  for _, a in ipairs(ACTIONS) do
    entries[#entries + 1] = load_text(a.name, origins[a.name],
      "encode: " .. ARTIFACT_PREFIX .. a.name .. ".bmp", LABEL_H)
  end

  -- The two button boards keep their 16-px cells: the drawer reads a fixed 12
  -- records (eight button letters and four EXIT letters), so the cut must not
  -- merge or split an icon.  Each board is a single column of icons.
  local abc_board = load_text(BUTTON_ABC_NAME, origins[BUTTON_ABC_NAME],
    "encode: " .. ARTIFACT_PREFIX .. BUTTON_ABC_NAME .. ".bmp", BUTTON_ABC_H,
    { cells = true, icons = BUTTON_ABC_COUNT })
  entries[#entries + 1] = abc_board
  local xyz_board = load_text(BUTTON_XYZLR_NAME, origins[BUTTON_XYZLR_NAME],
    "encode: " .. ARTIFACT_PREFIX .. BUTTON_XYZLR_NAME .. ".bmp", BUTTON_XYZLR_H,
    { cells = true, icons = BUTTON_XYZLR_COUNT })
  entries[#entries + 1] = xyz_board

  -- The shared EXIT: list 11 keeps aliasing the main row's list while the two
  -- artifacts are identical, and gets a list of its own as soon as they differ.
  local exit_entry = entries[5]
  local split_exit
  local split_bmp = by_name[ARTIFACT_PREFIX .. SPLIT_EXIT_NAME .. ".bmp"]
  if not split_bmp then
    -- The button column's EXIT comes from this image, so it is not optional.
    error("encode: " .. ARTIFACT_PREFIX .. SPLIT_EXIT_NAME .. ".bmp is missing", 0)
  end
  -- Its four 16-px cells are the column's last four records, so it is cut on
  -- the cell grid and never merged into wider segments.
  local alt = load_text(SPLIT_EXIT_NAME, origins[SPLIT_EXIT_NAME],
    "encode: " .. ARTIFACT_PREFIX .. SPLIT_EXIT_NAME .. ".bmp", LABEL_H,
    { cells = true, icons = EXIT_CELLS })
  if alt.px ~= exit_entry.px or alt.w ~= exit_entry.w or alt.h ~= exit_entry.h then
    split_exit = alt
    entries[#entries + 1] = alt
  end

  local function has_ink(px)
    for i = 1, #px do if px:byte(i) ~= 0 then return true end end
    return false
  end

  local function records_bytes(recs)
    local parts = {}
    for i, r in ipairs(recs) do parts[i] = pack_record(r.x, r.y, r.w, r.h, r.co) end
    return table.concat(parts)
  end

  -- Fast path: identical pixels, identical placement, nothing else to write.
  local changed = opts.rebuild == "always"
  if not changed then
    local atlas = atlas_of(original)
    local parent_text = text
    -- The composed pixels alone are not enough: moving a label translates it
    -- without changing a pixel, so the placement has to be compared too.
    local function same(entry, recs, stage)
      if #recs == 0 then return not has_ink(entry.px) end
      local px, w, h, x0, y0 = compose_records(recs, atlas, stage,
        { x = entry.anchor.x, y = entry.anchor.y, h = entry.h })
      if h ~= entry.h or x0 ~= entry.anchor.x or y0 ~= entry.anchor.y then
        return false
      end
      if w == entry.w then return px == entry.px end
      -- The records are ink-tight, so a parent built by this codec composes
      -- narrower than an artboard that still has blank trailing columns.  That
      -- is not an edit: the extra columns hold nothing.
      if w > entry.w then return false end
      local iw, ew = w // 2, entry.w // 2
      for y = 0, h - 1 do
        if px:sub(y * iw + 1, (y + 1) * iw)
          ~= entry.px:sub(y * ew + 1, y * ew + iw) then
          return false
        end
      end
      return true
    end
    -- The boards are compared against their own slice of the parent column.
    local board_slice = {
      [abc_board] = { table.unpack(parent_text.button.recs, 1, BUTTON_ABC_COUNT) },
      [xyz_board] = { table.unpack(parent_text.button.recs, 1 + BUTTON_ABC_COUNT,
        BUTTON_ABC_COUNT + BUTTON_XYZLR_COUNT) },
    }
    for _, entry in ipairs(entries) do
      if entry == exit_entry then
        if not same(entry, parent_text.main[5].recs, "encode: 04_EXIT") then changed = true end
      elseif board_slice[entry] then
        if not same(entry, board_slice[entry], "encode: " .. entry.name) then changed = true end
      else
        local found
        for _, m in ipairs(parent_text.main) do
          if m.name == entry.name then found = m.recs end
        end
        for _, a in ipairs(ACTIONS) do
          if a.name == entry.name then found = parent_text.actions[a.index].recs end
        end
        if entry.name == SPLIT_EXIT_NAME then
          found = parent_text.actions[EXIT_INDEX].recs
        end
        if not found or not same(entry, found, "encode: " .. entry.name) then changed = true end
      end
    end
  end

  -- Background and brackets, unchanged from version 3.
  local background_px, background_changed, background_tail
  local background_bmp    = by_name[BACKGROUND_NAME]
  local bracket_left_bmp  = by_name[BRACKET_LEFT_NAME]
  local bracket_right_bmp = by_name[BRACKET_RIGHT_NAME]
  if background_bmp or bracket_left_bmp or bracket_right_bmp then
    local decoded = prs:decode(
      original:sub(BACKGROUND_OFFSET + 1, BACKGROUND_OFFSET + BACKGROUND_SLOT))[1].data
    if #decoded < BACKGROUND_END then
      error(string.format(
        "encode: the parent background decompresses to %d bytes, expected at least %d (the panel plus the 128-byte mark pair)",
        #decoded, BACKGROUND_END), 0)
    end

    local retail_head = decoded:sub(1, BACKGROUND_PIXELS)
    background_px = retail_head
    background_tail = decoded:sub(BACKGROUND_PIXELS + 1)

    if background_bmp then
      local px, w, h = parse_bmp(background_bmp, "encode: " .. BACKGROUND_NAME, 4)
      if w ~= BACKGROUND_W or h ~= BACKGROUND_H then
        error(string.format("encode: %s is %dx%d, but the options background is exactly %dx%d",
          BACKGROUND_NAME, w, h, BACKGROUND_W, BACKGROUND_H), 0)
      end
      background_px = px
      background_changed = px ~= retail_head
    end

    local left = background_tail:sub(BRACKET_TAIL_AT + 1,
      BRACKET_TAIL_AT + BRACKET_BYTES)
    local right = background_tail:sub(BRACKET_TAIL_AT + BRACKET_BYTES + 1,
      BRACKET_TAIL_AT + 2 * BRACKET_BYTES)

    local function read_bracket(bmp, name)
      local px, w, h = parse_bmp(bmp, "encode: " .. name, 4)
      if w ~= BRACKET_W or h ~= BRACKET_H then
        error(string.format("encode: %s is %dx%d, but a selection mark is exactly %dx%d",
          name, w, h, BRACKET_W, BRACKET_H), 0)
      end
      return px
    end

    local new_left  = bracket_left_bmp  and read_bracket(bracket_left_bmp,  BRACKET_LEFT_NAME)  or left
    local new_right = bracket_right_bmp and read_bracket(bracket_right_bmp, BRACKET_RIGHT_NAME) or right
    if new_left ~= left or new_right ~= right then
      background_tail = background_tail:sub(1, BRACKET_TAIL_AT)
        .. new_left .. new_right
        .. background_tail:sub(BRACKET_TAIL_AT + 2 * BRACKET_BYTES + 1)
      background_changed = true
    end
  end

  -- Positions metadata is independent of the pixels and of the text records.
  local positions_changed, position_writes = false, {}
  local positions_bmp = by_name[POSITIONS_NAME]
  if positions_bmp then
    local meta = parse_positions(positions_bmp, positions, "encode: " .. POSITIONS_NAME)
    positions_changed, position_writes = encode_positions(
      positions, meta, original, "encode: " .. POSITIONS_NAME)
  end

  if not changed and not background_changed and not positions_changed then
    codec.stats = {
      segments = 0, unique = 0, sheet_bytes = #atlas_of(original),
      stream_bytes = 0, records = 0, arena_used = 0,
      arena_capacity = ATLAS_SLOT, unchanged = true, lists = {},
    }
    return original
  end

  --[[ Segmentation and packing.

    How an image is cut changes both numbers that matter.  Narrow pieces dedupe
    and compress better but need more records; wide pieces save records but
    store more transparent padding; and the record arena itself shrinks as the
    compressed stream grows, because its tail lives in the same fixed slot.

    So try a fixed ladder of cuts, discard the ones whose records cannot be
    placed, and keep the smallest stream among those that fit both budgets
    (fewer records on a tie).  When nothing fits, keep the smallest stream so
    the failure names the real blocker.  The ladder and the tie-break are fixed,
    so identical inputs always produce the same layout.
  ]]
  local CANDIDATES = {
    { gap = 0,  maxw = 16 },
    { gap = 0,  maxw = 32 },
    { gap = 0,  maxw = 64 },
    { gap = 0,  maxw = 128 },
    { gap = 0,  maxw = LABEL_MAX_W },
    { gap = 1,  maxw = LABEL_MAX_W },
    { gap = 2,  maxw = 16 },
    { gap = 2,  maxw = 32 },
    { gap = 2,  maxw = 64 },
    { gap = 2,  maxw = 128 },
    { gap = 2,  maxw = LABEL_MAX_W },
    { gap = 3,  maxw = 16 },
    { gap = 3,  maxw = 32 },
    { gap = 4,  maxw = 32 },
    { gap = 4,  maxw = 64 },
    { gap = 4,  maxw = 128 },
    { gap = 4,  maxw = LABEL_MAX_W },
    { gap = 8,  maxw = 64 },
    { gap = 8,  maxw = 128 },
    { gap = 8,  maxw = LABEL_MAX_W },
    { gap = 16, maxw = 128 },
    { gap = 16, maxw = LABEL_MAX_W },
    { gap = 24, maxw = LABEL_MAX_W },
  }

  -- Cut every image with one candidate.  Returns nil on success or a message.
  local function segment_all(cfg)
    for _, entry in ipairs(entries) do
      local opts = entry.cells and { cells = true } or cfg
      entry.segs = segments_of(entry.px, entry.w, entry.h, entry.stage, opts)
      if #entry.segs > MAX_RECORDS then
        return string.format("%s: the image needs %d records, over the %d-record cap",
          entry.stage, #entry.segs, MAX_RECORDS)
      end
      if entry.required and #entry.segs == 0 then
        return string.format(
          "%s: the image is blank; every Options row needs at least one glyph",
          entry.stage)
      end
      if entry.icons and #entry.segs ~= entry.icons then
        return string.format(
          "%s: yields %d icons, but the screen reads exactly %d; keep one icon per 16-px cell",
          entry.stage, #entry.segs, entry.icons)
      end
    end
    return nil
  end

  -- Two regions, first fit: the retired action pool (320 bytes the retail
  -- action strings no longer need) and then the dead tail of the atlas slot,
  -- which follows the PRS end marker.  The decompressor at 0x0600A164 returns
  -- on a zero back-reference word and never writes there, so relocated lists
  -- survive.
  local function make_arena(stream_len)
    local regions = {
      { at = ACTION_ARENA, stop = ACTION_ARENA + ACTION_ARENA_LEN },
      { at = ceil8(ATLAS_OFFSET + stream_len), stop = ATLAS_OFFSET + ATLAS_SLOT },
    }
    local used, capacity = 0, 0
    for _, r in ipairs(regions) do
      capacity = capacity + math.max(0, r.stop - r.at)
    end
    local api = { capacity = capacity }
    function api.used() return used end
    function api.free()
      local free = 0
      for _, r in ipairs(regions) do free = free + math.max(0, r.stop - r.at) end
      return free
    end
    function api.alloc(bytes)
      for _, r in ipairs(regions) do
        if r.at + bytes <= r.stop then
          local at = r.at
          r.at = r.at + bytes
          used = used + bytes
          return at
        end
      end
      return nil
    end
    return api
  end

  -- Placement of every relocated list.  The write pass below uses these
  -- offsets verbatim, so a candidate is rejected on exactly the arithmetic the
  -- final write performs.
  local function plan_records(arena, stream_len)
    local by = {}
    for _, e in ipairs(entries) do by[e.name] = e end
    local plan = { main = {}, actions = {} }

    local function fail(name, bytes)
      return string.format(
        "encode: %s needs %d bytes of relocated record storage, but only %d remain after the %d-byte atlas stream and the action pool; the screen's lists no longer fit the %d-byte slot (shorten the labels or move fewer lists)",
        name, bytes, arena.free(), stream_len, ATLAS_SLOT)
    end

    for _, m in ipairs(MAIN) do
      local n = #by[m.name].records
      local pos
      if n <= m.cap then
        pos = m.slot                       -- stays in its retail slot
      else
        pos = arena.alloc(n * RECORD_BYTES)
        if not pos then return nil, fail(m.name, n * RECORD_BYTES) end
      end
      plan.main[m.name] = pos
    end

    -- Action lists: a list never straddles the two regions.
    for _, a in ipairs(ACTIONS) do
      local n = #by[a.name].records
      local pos
      if n == 0 then
        pos = text.actions[a.index].pos    -- empty list keeps the retail pointer
      else
        pos = arena.alloc(n * RECORD_BYTES)
        if not pos then return nil, fail(a.name, n * RECORD_BYTES) end
      end
      plan.actions[a.index] = pos
    end

    if split_exit then
      local n = #split_exit.records
      local pos = arena.alloc(n * RECORD_BYTES)
      if not pos then return nil, fail(SPLIT_EXIT_NAME, n * RECORD_BYTES) end
      plan.split = pos
    end

    return plan
  end

  local function attempt(cfg)
    local why = segment_all(cfg)
    if why then return nil, why end
    local packed, list = build_atlas(entries)
    if not packed then return nil, "encode: " .. list end
    local stream = prs:encode("",
      { { name = "DECOMPRESSED", data = packed } },
      string.format('{"chain":%d}', ATLAS_CHAIN))
    local arena = make_arena(#stream)
    local plan, plan_why = plan_records(arena, #stream)
    local records = 0
    for _, e in ipairs(entries) do records = records + #e.records end
    return {
      cfg = cfg, sheet = packed, segments = list, stream = stream, plan = plan,
      records = records, unique = #list, arena_used = arena.used(),
      arena_capacity = arena.capacity, problem = plan_why,
      -- How much storage the relocated lists want in total, whatever the bin
      -- packing succeeds in doing: the number the diagnostic should quote.
      arena_need = (function()
        local by = {}
        for _, e in ipairs(entries) do by[e.name] = e end
        local need = 0
        for _, m in ipairs(MAIN) do
          local n = #by[m.name].records
          if n > m.cap then need = need + n * RECORD_BYTES end
        end
        for _, a in ipairs(ACTIONS) do need = need + #by[a.name].records * RECORD_BYTES end
        if split_exit then need = need + #split_exit.records * RECORD_BYTES end
        return need
      end)(),
      fits = (#stream <= ATLAS_SLOT) and plan ~= nil,
    }
  end

  local tried, best, first_problem = {}, nil, nil
  for _, cfg in ipairs(CANDIDATES) do
    local a, why = attempt(cfg)
    if a then
      tried[#tried + 1] = {
        gap = cfg.gap, maxw = cfg.maxw, sheet = #a.sheet, stream = #a.stream,
        records = a.records, unique = a.unique, arena = a.arena_used, fits = a.fits,
        problem = a.problem,
      }
      local better
      if not best then
        better = true
      elseif a.fits ~= best.fits then
        better = a.fits
      elseif a.fits then
        better = #a.stream < #best.stream
          or (#a.stream == #best.stream and a.records < best.records)
      elseif (a.plan ~= nil) ~= (best.plan ~= nil) then
        -- Nothing fits the slot here: prefer a cut whose records can still be
        -- placed, so the report describes a layout that only needs shorter
        -- labels rather than one that also exhausts the arena.
        better = (a.plan ~= nil)
      elseif #a.stream ~= #best.stream then
        better = #a.stream < #best.stream
      else
        better = a.records < best.records
      end
      if better then best = a end
    else
      tried[#tried + 1] = { gap = cfg.gap, maxw = cfg.maxw, rejected = why }
      first_problem = first_problem or why
    end
  end

  if not best then
    error("encode: no usable segmentation: " .. tostring(first_problem), 0)
  end
  -- `attempt` cuts the live entry tables, so the loop above leaves the last
  -- candidate's segments (and records) in place.  Cut again with the winner and
  -- check that the result is the one that was scored: the write pass below
  -- reads the entry tables, not the snapshot.  Doing it before the budget check
  -- also makes the failure diagnostic describe the layout it names.
  local recut = segment_all(best.cfg)
  if recut then error(recut, 0) end
  local packed, list = build_atlas(entries)
  if not packed then error("encode: " .. list, 0) end
  if packed ~= best.sheet or #list ~= #best.segments then
    error("encode: the chosen cut is not reproducible", 0)
  end

  if not best.fits then
    local per_list, segment_bytes = {}, 0
    for _, entry in ipairs(entries) do
      per_list[#per_list + 1] = { name = entry.name, records = #entry.records }
      for _, s in ipairs(entry.segs) do segment_bytes = segment_bytes + ceil8(#s.data) end
    end
    codec.stats = {
      segments = best.records, unique = #list, sheet_bytes = #packed,
      stream_bytes = #best.stream, records = best.records,
      dedupe_saved = segment_bytes - #packed,
      free_decoded = ATLAS_LIMIT - #packed,
      free_stream = ATLAS_SLOT - #best.stream,
      arena_used = best.arena_used, arena_capacity = best.arena_capacity,
      arena_need = best.arena_need,
      cut = { gap = best.cfg.gap, maxw = best.cfg.maxw },
      candidates = tried, lists = per_list, unchanged = false, fits = false,
    }
    local over_stream = math.max(0, #best.stream - ATLAS_SLOT)
    local over_records = math.max(0, best.arena_need - best.arena_capacity)
    if over_stream > 0 then
      local msg = string.format(
        "encode: the shared atlas compresses to %d bytes, over the %d-byte slot by %d; its %d records need %d bytes of relocated storage",
        #best.stream, ATLAS_SLOT, over_stream, best.records, best.arena_need)
      if over_records > 0 then
        msg = msg .. string.format(", over the %d-byte arena by %d",
          best.arena_capacity, over_records)
      end
      error(msg .. "; every consumer shares this one atlas, so it holds one language at a time - translate the remaining labels or shorten these", 0)
    end
    if over_records > 0 then
      error(string.format(
        "encode: the label record lists need %d bytes of relocated record storage, over the %d-byte arena by %d (the %d-byte atlas stream fits); shorten the labels so fewer lists move",
        best.arena_need, best.arena_capacity, over_records, #best.stream), 0)
    end
    error("encode: no cut of these labels fits the slot", 0)
  end

  local sheet, segments, stream = best.sheet, best.segments, best.stream
  local plan = best.plan
  local arena_used, arena_capacity = best.arena_used, best.arena_capacity

  local new_data = original
  local main_pos = {}

  local index = {}
  for i, entry in ipairs(entries) do index[entry.name] = entry end

  local record_total = 0
  for _, entry in ipairs(entries) do record_total = record_total + #entry.records end

  -- A background-only or position-only edit leaves every text list, the sheet
  -- and the descriptors byte-identical.
  if changed then
  -- 1. The sheet and its arena.
  local slot = stream .. string.rep("\0", ATLAS_SLOT - #stream)
  new_data = put(new_data, ATLAS_OFFSET, slot)

  -- 2. Main rows.  A list keeps its retail slot while it fits there, so a
  -- retail round trip rewrites pointers and records in place and nothing else.
  for i, m in ipairs(MAIN) do
    local entry = index[m.name]
    local recs = entry.records
    local pos = plan.main[m.name]
    new_data = put(new_data, pos, records_bytes(recs))
    main_pos[m.name] = pos

    -- `+12` is the label count in the high half of a BE u32; the low half is 0.
    new_data = put(new_data, m.desc + 12, string.pack(">I4", #recs << 16))
    new_data = put(new_data, m.desc + 16, string.pack(">I4", RAM_BASE + pos))
  end

  -- 3. Action lists: first fit into the retired pool, then the slot tail.  A
  -- list never straddles the two regions.
  local action_pos = {}
  for _, a in ipairs(ACTIONS) do
    local entry = index[a.name]
    local recs = entry.records
    local pos = plan.actions[a.index]
    if #recs > 0 then
      new_data = put(new_data, pos, records_bytes(recs))
    end
    action_pos[a.index] = pos
    new_data = put(new_data, ACTION_TABLE + a.index, string.char(#recs))
    new_data = put(new_data, ACTION_POINTERS + a.index * 4,
      string.pack(">I4", RAM_BASE + pos))
  end

  -- 4. The shared EXIT: list 11 keeps the main row's list unless split.
  do
    local recs, pos
    if split_exit then
      local entry = index[SPLIT_EXIT_NAME]
      recs, pos = entry.records, plan.split
      new_data = put(new_data, pos, records_bytes(recs))
    else
      recs, pos = exit_entry.records, main_pos["04_EXIT"]
    end
    new_data = put(new_data, ACTION_TABLE + EXIT_INDEX, string.char(#recs))
    new_data = put(new_data, ACTION_POINTERS + EXIT_INDEX * 4,
      string.pack(">I4", RAM_BASE + pos))
  end

  -- 5. The button column (fixed 12): the two boards, then the EXIT label's
  -- four cells moved to the column's own geometry.  The cells keep their
  -- characterOffset, so the label, the submenu's EXIT and the column's EXIT
  -- read one set of textures, and the mini icons reuse the button segments.
  local column = {}
  for _, board in ipairs({ index[BUTTON_ABC_NAME], index[BUTTON_XYZLR_NAME] }) do
    for _, r in ipairs(board.records) do column[#column + 1] = r end
  end
  local exit_source = index[SPLIT_EXIT_NAME] or exit_entry
  for _, r in ipairs(exit_source.records) do
    column[#column + 1] = {
      x = EXIT_COLUMN_X + (r.x - exit_source.anchor.x),
      y = EXIT_COLUMN_Y + (r.y - exit_source.anchor.y),
      w = r.w, h = r.h, co = r.co,
    }
  end
  if #column ~= BUTTON_COUNT then
    error(string.format(
      "encode: the button column needs %d records, but the boards and the EXIT label give %d",
      BUTTON_COUNT, #column), 0)
  end
  new_data = put(new_data, BUTTON_REC, records_bytes(column))
  -- The mini labels sit at their own fixed anchor, one per icon cell; the
  -- sprite is cropped to its ink, so its box carries the offset the crop
  -- removed and has to be re-applied against the icon's own 16-px cell, or a
  -- glyph whose ink does not start at the cell's top-left would shift.
  local mini = {}
  for k = 1, MINI_COUNT do
    local first = k <= BUTTON_ABC_COUNT
    local board = first and index[BUTTON_ABC_NAME] or index[BUTTON_XYZLR_NAME]
    local cell_top = board.anchor.y + LABEL_H * (first and (k - 1) or (k - BUTTON_ABC_COUNT - 1))
    local src = column[k]
    mini[k] = {
      x = -8 + (src.x - board.anchor.x),
      y = -8 + (src.y - cell_top),
      w = src.w, h = src.h, co = src.co,
    }
  end
  new_data = put(new_data, MINI_REC, records_bytes(mini))
  end

  if positions_changed then
    for _, write in ipairs(position_writes) do
      new_data = put(new_data, write.offset, write.data)
    end
  end

  if background_changed then
    -- 512-entry chains: the retail tail recompresses to 1,271 bytes with the
    -- default 256, over the slot, and to 1,245 with the deeper search.
    local bg_stream = prs:encode("", { { name = "DECOMPRESSED", data = background_px .. background_tail } },
      string.format('{"chain":%d}', BACKGROUND_CHAIN))
    if #bg_stream > BACKGROUND_SLOT then
      error(string.format(
        "encode: the background (panel plus selection marks) compresses to %d bytes, over the 1,256-byte slot (shed %d bytes)",
        #bg_stream, #bg_stream - BACKGROUND_SLOT), 0)
    end
    new_data = put(new_data, BACKGROUND_OFFSET,
      bg_stream .. string.rep("\0", BACKGROUND_SLOT - #bg_stream))
  end

  -- Only the slot, the text lists and the two independent data sets may differ.
  local allowed = {}
  if changed then
    allowed[#allowed + 1] = { ATLAS_OFFSET, ATLAS_OFFSET + ATLAS_SLOT }
    allowed[#allowed + 1] = { ACTION_TABLE, ACTION_POINTERS + ACTION_COUNT * 4 }
    allowed[#allowed + 1] = { ACTION_ARENA, ACTION_ARENA + ACTION_ARENA_LEN }
    allowed[#allowed + 1] = { BUTTON_REC, BUTTON_REC + BUTTON_COUNT * RECORD_BYTES }
    allowed[#allowed + 1] = { MINI_REC, MINI_REC + MINI_COUNT * RECORD_BYTES }
    for i, m in ipairs(MAIN) do
      allowed[#allowed + 1] = { m.desc + 12, m.desc + 20 }
      allowed[#allowed + 1] = { main_pos[m.name],
        main_pos[m.name] + #index[m.name].records * RECORD_BYTES }
    end
  end
  if background_changed then
    allowed[#allowed + 1] = { BACKGROUND_OFFSET, BACKGROUND_OFFSET + BACKGROUND_SLOT }
  end
  for _, write in ipairs(position_writes) do
    allowed[#allowed + 1] = { write.offset, write.offset + #write.data }
  end

  local stray
  for off = 0, #original - 1 do
    if new_data:byte(off + 1) ~= original:byte(off + 1) then
      local ok = false
      for _, range in ipairs(allowed) do
        if off >= range[1] and off < range[2] then ok = true; break end
      end
      if not ok and not stray then stray = off end
    end
  end
  if stray then
    error(string.format("encode: first unexpected modified byte at 0x%06X", stray), 0)
  end

  local per_list, segment_bytes = {}, 0
  for _, entry in ipairs(entries) do
    per_list[#per_list + 1] = { name = entry.name, records = #entry.records }
    for _, s in ipairs(entry.segs) do segment_bytes = segment_bytes + ceil8(#s.data) end
  end

  codec.stats = {
    segments = record_total,
    unique = #segments,
    sheet_bytes = #sheet,
    stream_bytes = #stream,
    records = record_total,
    dedupe_saved = segment_bytes - #sheet,
    free_decoded = ATLAS_LIMIT - #sheet,
    free_stream = ATLAS_SLOT - #stream,
    arena_used = arena_used,
    arena_capacity = arena_capacity,
    cut = { gap = best.cfg.gap, maxw = best.cfg.maxw },
    candidates = tried,
    lists = per_list,
    unchanged = false,
  }

  return new_data
end

function codec.can_handle(data)
  if type(data) ~= "string" then
    return "no"
  end
  if #data < ATLAS_OFFSET + ATLAS_SLOT then
    return "no"
  end
  -- Hash only a file of the right size: can_handle also sees whole disc images,
  -- and the codec's offsets are meaningless outside this executable.
  if #data == FILE_BYTES and sha256.hex(data) == FILE_SHA256 then
    return "certain"
  end

  -- Weaker, content-based evidence: the five descriptors must look like option
  -- rows and the atlas must decompress.
  for _, m in ipairs(MAIN) do
    if be32(data, m.desc + 20) ~= TEXTURE_BASE then
      return "no"
    end
    local count = be16(data, m.desc + 12)
    if count < 1 or count > MAX_RECORDS then
      return "no"
    end
    local ptr = be32(data, m.desc + 16)
    local pos = ptr >= RAM_BASE and ptr - RAM_BASE or ptr
    if pos + count * RECORD_BYTES > #data then
      return "no"
    end
  end

  local ok, atlas = pcall(function()
    return prs:decode(data:sub(ATLAS_OFFSET + 1, ATLAS_OFFSET + ATLAS_SLOT))[1].data
  end)
  if not ok or type(atlas) ~= "string" or #atlas < 1 then
    return "no"
  end

  return "likely"
end

function codec.decode_name(args)
  return "OPTIONS"
end

return codec
