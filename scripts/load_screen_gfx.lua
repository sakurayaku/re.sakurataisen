--[[
  Sakura Taisen (Saturn) — load / memory-card screen graphics and labels

  PATCH codec for two PRS blocks and one string table inside the SAKURA
  executable: the load-screen pictures, the 16 x 16 glyph sheet they are drawn
  with, and the episode / prompt strings that index that sheet.

  Pictures (SakuraTaisen.cpp FixupSakura 3764-3830)
  -------------------------------------------------
  Disc-1 0x5E190 / disc-2 0x5E2C8 is a 2,292-byte slot that decompresses to
  42,048 bytes.  FixupSakura copies three BMPs into it with memcpy_s, each at
  its own destination, so the block is a set of independent 4bpp VDP1 bitmaps:

      0x0000  LoadMenu.bmp      288 x 176   25,344 bytes
      0x6300  not exposed       192 x 140   13,440 bytes  (preserved)
      0x9780  CartridgeRam.bmp  112 x  50    2,800 bytes
      0xA200  choice left arrow   8 x 16       64 bytes
      0xA240  choice right arrow  8 x 16       64 bytes
      0xA280  CopyFile.bmp       56 x  16      448 bytes

  The arrow textures overlap the final 112 bytes of CartridgeRam.bmp.  Encode
  writes them after that image, preserving the original arrows when no arrow
  BMP is supplied.

  Disc 2 inserts 24 bytes early and another 288 at 0x52E00, so every offset
  past 0x52E00 moves by +0x138: 0x5E190 -> 0x5E2C8 and 0x5AD98 -> 0x5AED0.
  Both blocks decompress to byte-identical pixels.

  Each 4bpp VDP1 bitmap is row-major, top-down, two pixels per byte, high
  nibble first, no row padding.  The region at 0x6300..0x9780 is carried
  through byte for byte.
  The slot palette at 0x5AD98 is 64 bytes = two 16-colour BGR555 banks; the
  first is the load-screen bank.  Text labels use the shared
  adv_dialogue_jp_for_bmp palette: its last entry is bright red (BGR555 0x001F)
  instead of the retail white, a colour the artists can see while they draw.
  The C++ writes neither bank back, so both BMP palettes are display-only.

  Labels (SakuraTaisen.cpp ExtractLoadScreen 8884, PatchLoadScreen 10450)
  ----------------------------------------------------------------------
  The episode names and menu prompts are not part of the picture block.  They
  are drawn from a second PRS block: a flat sheet of 16 x 16 4bpp tiles,
  128 bytes each, at disc-1 0x5C654 / disc-2 0x5C78C.  Retail decompresses to
  16,384 bytes = 128 tiles and the stream occupies its whole 6,970-byte slot
  (0x5C654..0x5E18E, immediately before the picture block).

  The strings live at disc-1 0x5A09E / disc-2 0x5A1D6 as big-endian 16-bit
  glyph indices: 1-based into the sheet (the engine uses index - 1), 0 ends a
  string, two zeroes end the table.  45 strings, 762 bytes exactly, ending on
  the pointer table at 0x5A398 / 0x5A4D0.  That table (and the menu structures
  after it) holds 38 big-endian RAM pointers (file offset + 0x06004000) to the
  strings, so a re-encode rewrites every dword in the executable that pointed
  at a string.  A whole-file scan finds exactly those 38.

  The string area is a fixed budget, not a growable one: the pointer table
  follows immediately, so writing past 762 bytes would overwrite it.  Retail
  fills it to the byte and the US translation used 684, so a translation has to
  fit too -- encode refuses a longer block and reports how many bytes it needs.
  Nothing in the executable moves; only bytes inside the 762-byte area and the
  pointer dwords change.

  Model (the same one shared/main_menu_gfx.lua uses): the translator edits
  whole rendered labels.

  Related labels are consolidated into one sheet, one label per 16-pixel row,
  in table order:

      LOAD_SCREEN/EPISODE_NUMBERS.bmp      80 x 160   entries 1, 3 .. 17, 33
      LOAD_SCREEN/EPISODE_TITLES.bmp      208 x 160  entries 2, 4 .. 20
      LOAD_SCREEN/COMMANDS_CONTEXT.bmp    144 x  64  entries 21 .. 25
      LOAD_SCREEN/COMMANDS_CONFIRM.bmp    128 x  64  entries 27, 40 .. 42
      LOAD_SCREEN/COMMANDS_RESULT.bmp     176 x  48  entries 43 .. 45
      LOAD_SCREEN/UNUSED_ALONE_GLYPH.bmp   16 x  16  entry 34
      LOAD_SCREEN/ERRORS.bmp              272 x  64  entries 30, 35, 31, 32
      LOAD_SCREEN/UNUSED.bmp              224 x  64  entries 36 .. 39

  Two labels stand alone, named rather than numbered:

      LOAD_SCREEN/EMPTY_SAVE.bmp         64 x  16  entry 26  記録無し
      LOAD_SCREEN/UNUSED_EPISODE_10.bmp  64 x  16  entry 19  第10話

  The five menu buttons have a file each, one 16-pixel row, and nothing else:

      LOAD_SCREEN/COMMANDS_CHOICE_YES.bmp     32 x 16  はい
      LOAD_SCREEN/COMMANDS_CHOICE_NO.bmp      48 x 16  いいえ
      LOAD_SCREEN/COMMANDS_CHOICE_COPY.bmp    48 x 16  コピー
      LOAD_SCREEN/COMMANDS_CHOICE_DELETE.bmp  32 x 16  消去
      LOAD_SCREEN/COMMANDS_CHOICE_EXIT.bmp    32 x 16  終了

  All five buttons are drawn from 10-byte sprite descriptors at disc-1 0x59C70
  (disc-2 0x59DA8), not from the duplicate YES/NO strings.  Their groups have
  3/2/2/3/2 cells (COPY/DELETE/YES/NO/EXIT), and the menu records hold each group's
  count and pointer.  Encode rebuilds their atlas cells with the other labels,
  rewrites the descriptors' glyph sources, and repacks the groups in the same
  twelve-record area.  A button can gain a cell if another gives one up.

  The numbers share one five-cell draw area, so that sheet is 5 cells wide.
  The titles have no fixed area and are up to thirteen cells long (entry 10),
  so that sheet is 13 cells wide and short titles leave the rest blank.  Every
  other sheet is as wide as the longest retail label of its group.  A label
  that stands alone keeps its own `width / 16`-cell file and may be widened,
  up to the 18-cell screen.

  Entry 34 is not addressed as a string.  Its retail glyph is also drawn by
  the EXIT button, which has its own descriptors and BMP in this codec.
  UNUSED_ALONE_GLYPH.bmp therefore edits only that unreferenced string.

  A row of EPISODE_NUMBERS holds five cells.  Retail stores three glyphs
  (第1話; four on the tenth row) at cells 1-3, so cells 4 and 5 are the free
  drawing room, 32 pixels on the right.  A row that draws exactly what retail
  draws keeps its retail string (three or four glyphs); any other row is stored
  as all five cells, which is the whole draw area, and the drawer lays a label
  out by its cell count.  When all ten numbers use five cells, encode moves
  their shared draw origin 16 pixels left.  The final episode uses this same
  origin, so a different final width needs its own positioning patch.

  A row of EPISODE_TITLES has no fixed area, so a row is stored up to the last
  cell that is drawn in: blank cells after that are dropped again, which keeps
  a short title short (and keeps an untouched decode byte for byte).  Every
  other sheet works the same way, one row per label.  All the label images use
  the label palette, so all end on the bright red entry.

  Encode cuts each image into 16 x 16 cells from its origin, stores every
  distinct cell once (the sheet is the atlas), and rewrites all 45 strings and
  the pointers to them.  Cells are deduplicated exactly, so a letter shared by
  several labels costs one tile.  The sheet starts with the button cells,
  then adds the other labels in first-use order.  This keeps button sprites
  in the early part of the atlas and drops retail tiles no label uses.

  Limits, all measured rather than guessed:
    * 181 tiles — the load-screen VDP1 layout can hold a relocated sheet of
      0x5A80 bytes between the preceding picture and the following picture
      on both discs.
      Retail uses 128 tiles; the US sheet has 144.
    * 6,970 compressed bytes — the font slot ends at the picture block.
    * 762 bytes of string data — the pointer table follows immediately.  A
      block that would go over that first drops the eight strings no pointer
      addresses (table entries 19, 28, 29, 34 and 36-39: retail leftovers the
      load screen never draws, among them a lone 了 and duplicate prompts).
    * 16 pixels high and at most 288 pixels wide (18 cells, the screen width).
    * EPISODE_NUMBERS.bmp is always 80 x 160: five cells by ten rows.

  Encoding never resizes the executable: picture edits keep the 2,292-byte
  slot, label edits keep the 6,970-byte font slot and the 762-byte string area.
  Button edits also update the twelve sprite descriptors and their menu references.
  Sheets above 144 tiles relocate the font and following picture; CD2 also
  moves the preceding picture.  Their VDP1 bases and transfer size follow.
]]

local bmp = dofile(LUDARED.SCRIPTS .. "/shared/bmp.lua")
local palettes = dofile(LUDARED.SCRIPTS .. "/shared/palettes.lua")
local prs = LUDARED.codec("std/sega/compression/prs")

local can_handle = dofile(LUDARED.SCRIPTS .. "/shared/can_handle.lua")

local codec = {}

codec.name        = "Sakura Taisen Load Screen Graphics"
codec.description = "Patches the load/memory-card images, glyph sheet and labels in the SAKURA executable"
codec.version     = 18
codec.kind        = "patch"

local DISC1 = {
  block   = 0x0005E190,
  palette = 0x0005AD98,
  font    = 0x0005C654,
  strings = 0x0005A09E,
  format  = 0x00059C70,
  number_x = 0x000397D6,
  code_delta = 0,
  data_delta = 0,
}
local DISC2 = {
  block   = 0x0005E2C8,
  palette = 0x0005AED0,
  font    = 0x0005C78C,
  strings = 0x0005A1D6,
  format  = 0x00059DA8,
  number_x = 0x000397EE,
  code_delta = 0x18,
  data_delta = 0x138,
}

local COMPRESSED_SIZE = 2292
local DECOMP_SIZE     = 42048
local PALETTE_BYTES   = 32
local BPP             = 4

-- Label sheet and string table.
local TILE         = 16
local TILE_BYTES   = TILE * TILE * BPP // 8      -- 128
local FONT_SLOT    = 6970                        -- 0x5C654..0x5E18E
-- The active screen has 0x4800 bytes before its next texture.  Relocation
-- uses the free space through 0x060F5800 / VDP1 0x80000 on both discs.
local MAX_TILES    = 181
local FONT_WINDOW  = 0x4800
local STRING_BUDGET = 0x5A398 - 0x5A09E          -- 762, up to the pointer table
-- If this budget becomes limiting, a u8 string format is a possible experiment:
-- glyphs 1..181 and terminator 0 fit in one byte, allowing 716 glyph references
-- across 45 strings instead of 335.  The load-label drawer at CD1 SAKURA
-- 0x39034 (CD2 0x3904C) reads u16 at CD1 0x3905E/0x3907A and CD2
-- 0x39076/0x39092.  Change both mov.w loads to mov.b and their extu.w at
-- CD1 0x39060/0x39080 and CD2 0x39078/0x39098 to extu.b (mov.b sign-extends;
-- @r8+ then advances one byte).  In this codec, adapt read_strings,
-- pack_strings and the offset cursor in encode; recognize retail u16 and
-- patched u8 when decoding, and repoint strings using the new byte offsets.
-- Audit other consumers and verify in-game before enabling this format.
local RAM_BASE     = 0x06004000                  -- file offset -> RAM address
local TEXT_MAX_CELLS = 18                        -- 288 px, the screen width

-- The episode-number labels share one draw area five cells wide: table
-- entries 1, 3 .. 17 and 33 (the final chapter) in episode order.  Decode
-- puts them in one image.
local EPISODE_CELLS   = 5
local EPISODE_ROWS    = 10
local EPISODE_WIDTH   = EPISODE_CELLS * TILE      -- 80
local EPISODE_HEIGHT  = EPISODE_ROWS * TILE       -- 160
local EPISODE_ART     = "EPISODE_NUMBERS.bmp"

local function episode_index(row)
  if row == EPISODE_ROWS then return 33 end
  return row * 2 - 1
end

local EPISODE_ROW = {}
for row = 1, EPISODE_ROWS do EPISODE_ROW[episode_index(row)] = row end

-- The episode titles are the even entries 2, 4 .. 20, in episode order.  They
-- have no fixed draw area; entry 10 is the longest at thirteen cells.
local TITLE_CELLS    = 13
local TITLE_ROWS     = 10
local TITLE_WIDTH    = TITLE_CELLS * TILE       -- 208
local TITLE_HEIGHT   = TITLE_ROWS * TILE        -- 160
local TITLE_ART      = "EPISODE_TITLES.bmp"

local function title_index(row) return row * 2 end

local TITLE_ROW = {}
for row = 1, TITLE_ROWS do TITLE_ROW[title_index(row)] = row end

-- The command prompts and the leftover messages are independent labels of
-- different lengths, like the titles, so each group is one sheet with a
-- 16-pixel row per label and a row is stored up to the last cell it draws in.
-- Each sheet is as wide as the longest retail label of its group, which is
-- what keeps an untouched decode byte for byte.  Entry 34 is the dead leftover
-- (one blank glyph that no pointer addresses): one row, one cell,
-- UNUSED_ALONE_GLYPH.bmp.
local LABEL_SHEETS = {
  { art = "COMMANDS_CONTEXT.bmp", cells = 9,  indices = { 21, 22, 23, 24, 25 } },
  { art = "COMMANDS_CONFIRM.bmp", cells = 8,  indices = { 27, 40, 41, 42 } },
  { art = "COMMANDS_RESULT.bmp",  cells = 11, indices = { 43, 44, 45 } },
  { art = "UNUSED_ALONE_GLYPH.bmp", cells = 1, indices = { 34 } },
  -- セーブデータがありません, 記録を正しく読み込めませんでした。, then the two
  -- CD-swap prompts: the "that save is unusable" family, in reading order.
  { art = "ERRORS.bmp",           cells = 17, indices = { 30, 35, 31, 32 } },
  -- Nothing in the executable points at these four: retail leftovers.
  { art = "UNUSED.bmp",           cells = 14, indices = { 36, 37, 38, 39 } },
}

-- Table position -> its sheet and row in it.
local SHEET_ROW, SHEET_GROUP = {}, {}
for _, group in ipairs(LABEL_SHEETS) do
  for row, index in ipairs(group.indices) do
    SHEET_ROW[index] = row
    SHEET_GROUP[index] = group
  end
end

-- Two labels are not part of a family and keep a file of their own.  Unlike a
-- sheet row they can be widened, which is why they are not one-row sheets.
local SINGLES = {
  { art = "EMPTY_SAVE.bmp",         index = 26 },
  { art = "UNUSED_EPISODE_10.bmp", index = 19 },
}

local SINGLE_OF = {}
for _, single in ipairs(SINGLES) do SINGLE_OF[single.index] = single end

-- One parent record per button; the others repeat these counts and pointers.
-- Offsets are relative to the first sprite descriptor at spec.format.
local CHOICE_YES    = "COMMANDS_CHOICE_YES.bmp"
local CHOICE_NO     = "COMMANDS_CHOICE_NO.bmp"
local CHOICE_COPY   = "COMMANDS_CHOICE_COPY.bmp"
local CHOICE_DELETE = "COMMANDS_CHOICE_DELETE.bmp"
local CHOICE_EXIT   = "COMMANDS_CHOICE_EXIT.bmp"

local CHOICES = {
  { art = CHOICE_YES,    parent = 0x150, refs = 3 },
  { art = CHOICE_NO,     parent = 0x160, refs = 3 },
  { art = CHOICE_COPY,   parent = 0x0A0, refs = 9 },
  { art = CHOICE_DELETE, parent = 0x0B0, refs = 9 },
  { art = CHOICE_EXIT,   parent = 0x220, refs = 6 },
}
local FORMAT_CHOICES = { CHOICES[3], CHOICES[4], CHOICES[1], CHOICES[2], CHOICES[5] }
local CHOICE_RECORD_BYTES = 10
local CHOICE_RECORDS = 12

-- off is the destination of the matching memcpy_s in FixupSakura; size is
-- width * height * BPP / 8 and must stay equal to the copied byte counts.
local REGIONS = {
  { off = 0x0000, width = 288, height = 176, name = "LOAD_MENU.bmp" },
  { off = 0x9780, width = 112, height = 50,  name = "LOAD_MENU_MEMCARD.bmp" },
  { off = 0xA280, width = 56,  height = 16,  name = "LOAD_MENU_COPY_SOURCE.bmp" },
}
local ARROWS = {
  { off = 0xA200, width = 8, height = 16, name = "COMMANDS_CHOICE_ARROW_LEFT.bmp" },
  { off = 0xA240, width = 8, height = 16, name = "COMMANDS_CHOICE_ARROW_RIGHT.bmp" },
}

local function be16(data, offset)
  return data:byte(offset + 1) * 256 + data:byte(offset + 2)
end

local function be32(data, offset)
  return ((data:byte(offset + 1) * 256 + data:byte(offset + 2)) * 256
    + data:byte(offset + 3)) * 256 + data:byte(offset + 4)
end

local function patch_u32(data, offset, retail, moved, relocate)
  local current = be32(data, offset)
  if current ~= retail and current ~= moved then
    error(string.format("load_screen: unexpected word at 0x%06X", offset), 0)
  end
  local value = relocate and moved or retail
  return data:sub(1, offset) .. string.pack(">I4", value)
    .. data:sub(offset + 5)
end

local function region_size(region)
  return region.width * region.height * BPP // 8
end

local function check_layout()
  local previous_end = 0
  for _, region in ipairs(REGIONS) do
    local size = region_size(region)
    if region.off < previous_end then
      error(string.format("load_screen: %s overlaps the previous region", region.name), 0)
    end
    if region.off + size > DECOMP_SIZE then
      error(string.format("load_screen: %s does not fit the 42,048-byte block",
        region.name), 0)
    end
    previous_end = region.off + size
  end
end

local function wanted_disc(args)
  if type(args) == "table" and args.disc == 2 then return 2 end
  if type(args) == "string" then
    local lower = args:lower()
    if lower:find("cd2") or lower:find("disc2") then return 2 end
  end
  return 1
end

local function prefix(args)
  local value
  if type(args) == "table" then value = args.prefix else value = args end
  if not value or value == "" then value = "LOAD_SCREEN" end
  return (value:gsub("/+$", ""))
end

local function valid_block(data, offset)
  if #data < offset + COMPRESSED_SIZE then return nil end
  local ok, decompressed = pcall(function()
    return prs:decode(data:sub(offset + 1, offset + COMPRESSED_SIZE))[1].data
  end)
  if not ok or #decompressed ~= DECOMP_SIZE then return nil end
  return decompressed
end

-- A retail hash identifies the disc and its offsets. find_block still locates
-- either layout when decode or encode is explicitly given a modified executable.

local function find_block(data, args)
  local preferred = wanted_disc(args) == 2 and DISC2 or DISC1
  local other = preferred == DISC1 and DISC2 or DISC1
  for _, spec in ipairs({ preferred, other }) do
    local decompressed = valid_block(data, spec.block)
    if decompressed and spec.palette + PALETTE_BYTES <= #data then
      return spec.block, spec.palette, decompressed, spec
    end
  end
  error("load_screen: no 42,048-byte load block with its palette was found", 0)
end

-- The glyph sheet: 128-byte 16 x 16 4bpp tiles, packed back to back in index
-- order, so tile N of the decompressed stream is glyph index N + 1.
local function read_font(data, spec, stage)
  if #data < spec.font + FONT_SLOT then
    error(string.format(
      "%s: the file is %d bytes; the glyph sheet slot at 0x%06X ends at 0x%06X",
      stage, #data, spec.font, spec.font + FONT_SLOT), 0)
  end

  local ok, sheet = pcall(function()
    return prs:decode(data:sub(spec.font + 1, spec.font + FONT_SLOT))[1].data
  end)
  if not ok or #sheet == 0 then
    error(string.format("%s: the glyph sheet at 0x%06X is not a PRS stream",
      stage, spec.font), 0)
  end
  if #sheet % TILE_BYTES ~= 0 then
    error(string.format(
      "%s: the glyph sheet decompresses to %d bytes, not a multiple of %d",
      stage, #sheet, TILE_BYTES), 0)
  end

  local tiles = #sheet // TILE_BYTES
  if tiles > MAX_TILES then
    error(string.format(
      "%s: the glyph sheet holds %d tiles, over the %d the reader accepts",
      stage, tiles, MAX_TILES), 0)
  end
  return sheet, tiles
end

-- Big-endian u16 glyph indices; 0 ends a string and two zeroes end the table.
-- Each string remembers the file offset it started at so encode can repoint
-- the table of RAM addresses that points into it.
local function read_strings(data, offset, tiles, stage, limit)
  if #data < offset + 2 then
    error(string.format("%s: the string table at 0x%06X is outside the file",
      stage, offset), 0)
  end

  local strings, pos, indices, start = {}, offset, {}, nil
  while true do
    if pos + 2 > #data then
      error(string.format("%s: the string table runs past the end of the file",
        stage), 0)
    end
    local value = be16(data, pos)
    if value == 0 then
      strings[#strings + 1] = { offset = start or pos, indices = indices }
      indices, start = {}, nil
      if pos + 4 > #data or be16(data, pos + 2) == 0 then
        pos = pos + 2
        break
      end
      pos = pos + 2
    else
      if value > tiles then
        error(string.format(
          "%s: string %d uses glyph %d, but the sheet has only %d tiles",
          stage, #strings + 1, value, tiles), 0)
      end
      start = start or pos
      indices[#indices + 1] = value
      pos = pos + 2
    end
  end

  if pos > limit then
    error(string.format(
      "%s: the string table is %d bytes, past the %d-byte area it occupies",
      stage, pos - offset, limit - offset), 0)
  end
  return strings, pos
end

-- One string as a full-view 4bpp image: each glyph is a 16 x 16 cell laid out
-- left to right at the sprite pitch the game draws it with.
local function compose_string(sheet, indices)
  local cells = math.max(#indices, 1)
  local width = cells * TILE
  local row_bytes = TILE // 2
  local rows = {}
  for row = 0, TILE - 1 do
    local parts = {}
    for cell = 1, cells do
      local glyph = indices[cell]
      if glyph then
        local base = (glyph - 1) * TILE_BYTES + row * row_bytes
        parts[cell] = sheet:sub(base + 1, base + row_bytes)
      else
        parts[cell] = string.rep("\0", row_bytes)
      end
    end
    rows[row + 1] = table.concat(parts)
  end
  return table.concat(rows), width, TILE
end

local function single_name(dir, single)
  return string.format("%s/%s", dir, single.art)
end

local function episode_name(dir)
  return string.format("%s/%s", dir, EPISODE_ART)
end

local function title_name(dir)
  return string.format("%s/%s", dir, TITLE_ART)
end

local function sheet_name(dir, group)
  return string.format("%s/%s", dir, group.art)
end

local function choice_name(dir, choice)
  return string.format("%s/%s", dir, choice.art)
end

-- The tiles one string is built from, in string order.
local function glyph_tiles(sheet, indices)
  local out = {}
  for k, glyph in ipairs(indices) do
    out[k] = sheet:sub((glyph - 1) * TILE_BYTES + 1, glyph * TILE_BYTES)
  end
  return out
end

local function read_choice(data, spec, sheet, tiles, choice)
  local parent = spec.format + choice.parent
  local count = be16(data, parent + 2)
  local pointer = be32(data, parent + 4)
  local start = pointer - RAM_BASE
  if count < 1 or start < spec.format
      or start + count * CHOICE_RECORD_BYTES > spec.format + CHOICE_RECORDS * CHOICE_RECORD_BYTES then
    error(string.format("load_screen: invalid %s descriptor list", choice.art), 0)
  end

  local cells, records = {}, {}
  for i = 1, count do
    local offset = start + (i - 1) * CHOICE_RECORD_BYTES
    local source = be16(data, offset + 8)
    if be16(data, offset + 4) ~= TILE or be16(data, offset + 6) ~= TILE
        or source % TILE ~= 0 or source // TILE >= tiles then
      error(string.format("load_screen: invalid %s cell %d", choice.art, i), 0)
    end
    cells[i] = sheet:sub(source // TILE * TILE_BYTES + 1,
      (source // TILE + 1) * TILE_BYTES)
    records[i] = data:sub(offset + 1, offset + CHOICE_RECORD_BYTES)
  end
  return { cells = cells, records = records, count = count, pointer = pointer }
end

-- One 16-pixel label: the cells left to right.
local function frame_of_tiles(cells)
  local rows = {}
  for row = 0, TILE - 1 do
    local parts = {}
    for k, tile in ipairs(cells) do
      parts[k] = tile:sub(row * (TILE // 2) + 1, (row + 1) * (TILE // 2))
    end
    rows[row + 1] = table.concat(parts)
  end
  return table.concat(rows)
end

-- A stacked sheet: one 16-pixel row per label, `width_cells` cells wide,
-- blank after the label's own glyphs.
local function stacked_frame(sheet, strings, rows, width_cells, index_of)
  local out = {}
  for frame_row = 0, rows * TILE - 1 do
    local index = index_of(frame_row // TILE + 1)
    local indices = strings[index].indices
    if #indices > width_cells then
      error(string.format(
        "load_screen: string %d is %d cells wide, over the %d-cell sheet",
        index, #indices, width_cells), 0)
    end
    local y = frame_row % TILE
    local parts = {}
    for cell = 1, width_cells do
      local glyph = indices[cell]
      if glyph then
        local base = (glyph - 1) * TILE_BYTES + y * (TILE // 2)
        parts[cell] = sheet:sub(base + 1, base + TILE // 2)
      else
        parts[cell] = string.rep("\0", TILE // 2)
      end
    end
    out[frame_row + 1] = table.concat(parts)
  end
  return table.concat(out)
end

function codec.can_handle(data)
  return can_handle.can_handle_sakura1(data)
end

function codec.decode_name(args)
  return (prefix(args))
end

function codec.decode(data, args)
  check_layout()
  local _, palette_offset, decompressed, spec = find_block(data, args)
  local palette = bmp.from_bgr555(
    data:sub(palette_offset + 1, palette_offset + PALETTE_BYTES), 16)
  local label_palette = bmp.from_bgr555(palettes.raw("adv_dialogue_jp_for_bmp"), 16)
  local dir = prefix(args)
  local artifacts = {}

  for _, region in ipairs(REGIONS) do
    local pixels = decompressed:sub(region.off + 1, region.off + region_size(region))
    artifacts[#artifacts + 1] = {
      name = string.format("%s/%s", dir, region.name),
      data = bmp.build(pixels, region.width, region.height, BPP, palette),
    }
  end
  for _, region in ipairs(ARROWS) do
    local pixels = decompressed:sub(region.off + 1, region.off + region_size(region))
    artifacts[#artifacts + 1] = {
      name = string.format("%s/%s", dir, region.name),
      data = bmp.build(pixels, region.width, region.height, BPP, palette),
    }
  end

  local sheet, tiles = read_font(data, spec, "decode")
  local strings = read_strings(data, spec.strings, tiles, "decode",
    spec.strings + STRING_BUDGET)
  artifacts[#artifacts + 1] = {
    name = episode_name(dir),
    data = bmp.build(
      stacked_frame(sheet, strings, EPISODE_ROWS, EPISODE_CELLS, episode_index),
      EPISODE_WIDTH, EPISODE_HEIGHT, BPP, label_palette),
  }
  artifacts[#artifacts + 1] = {
    name = title_name(dir),
    data = bmp.build(
      stacked_frame(sheet, strings, TITLE_ROWS, TITLE_CELLS, title_index),
      TITLE_WIDTH, TITLE_HEIGHT, BPP, label_palette),
  }
  for _, group in ipairs(LABEL_SHEETS) do
    artifacts[#artifacts + 1] = {
      name = sheet_name(dir, group),
      data = bmp.build(
        stacked_frame(sheet, strings, #group.indices, group.cells,
          function(row) return group.indices[row] end),
        group.cells * TILE, #group.indices * TILE, BPP, label_palette),
    }
  end
  for _, single in ipairs(SINGLES) do
    local pixels, width, height = compose_string(sheet, strings[single.index].indices)
    artifacts[#artifacts + 1] = {
      name = single_name(dir, single),
      data = bmp.build(pixels, width, height, BPP, label_palette),
    }
  end
  for _, choice in ipairs(CHOICES) do
    local cells = read_choice(data, spec, sheet, tiles, choice).cells
    artifacts[#artifacts + 1] = {
      name = choice_name(dir, choice),
      data = bmp.build(frame_of_tiles(cells), #cells * TILE, TILE, BPP, label_palette),
    }
  end

  return artifacts
end

-- A label BMP as raw top-down 4bpp pixels; the geometry comes from its own
-- header because a translation may widen a label.
local function parse_label(image, name)
  if type(image) ~= "string" or #image < 14 + 40 then
    error(string.format("%s: BMP is too short", name), 0)
  end
  local width, height = string.unpack("<i4i4", image, 19)
  return bmp.parse(image, width, math.abs(height), BPP), width, math.abs(height)
end

-- Split one label image into 16 x 16 cells from its top-left corner.
local function label_cells(image, name)
  local pixels, width, height = parse_label(image, name)
  if height ~= TILE then
    error(string.format("%s: the label is %d pixels high; a load-screen string is %d",
      name, height, TILE), 0)
  end
  if width % TILE ~= 0 then
    error(string.format(
      "%s: the label is %d pixels wide, not a multiple of the %d-pixel glyph pitch",
      name, width, TILE), 0)
  end
  local cells = width // TILE
  if cells < 1 or cells > TEXT_MAX_CELLS then
    error(string.format(
      "%s: the label is %d glyph cells wide; the screen holds 1..%d",
      name, cells, TEXT_MAX_CELLS), 0)
  end

  local stride = width // 2
  local row_bytes = TILE // 2
  local out = {}
  for cell = 0, cells - 1 do
    local parts = {}
    for row = 0, TILE - 1 do
      local base = row * stride + cell * row_bytes
      parts[row + 1] = pixels:sub(base + 1, base + row_bytes)
    end
    out[cell + 1] = table.concat(parts)
  end

  return out
end

-- A stacked sheet as one list of cells per row.  The numbers keep a row's
-- retail string while the row still draws exactly what retail draws, so an
-- untouched decode re-encodes byte for byte; the titles drop trailing blanks.
local function stacked_rows(image, name, width_cells, rows)
  local pixels, width, height = parse_label(image, name)
  if width ~= width_cells * TILE or height ~= rows * TILE then
    error(string.format(
      "%s: expected %d x %d pixels (%d rows of %d cells), got %d x %d",
      name, width_cells * TILE, rows * TILE, rows, width_cells,
      width, height), 0)
  end

  local stride = width // 2
  local row_bytes = TILE // 2
  local out = {}
  for row = 1, rows do
    local cells = {}
    for cell = 0, width_cells - 1 do
      local parts = {}
      for y = 0, TILE - 1 do
        local base = ((row - 1) * TILE + y) * stride + cell * row_bytes
        parts[y + 1] = pixels:sub(base + 1, base + row_bytes)
      end
      cells[cell + 1] = table.concat(parts)
    end
    out[row] = cells
  end
  return out
end

-- Two cell lists, with a missing cell counting as blank.
local function same_cells(left, right)
  local blank = string.rep("\0", TILE_BYTES)
  for i = 1, math.max(#left, #right) do
    if (left[i] or blank) ~= (right[i] or blank) then return false end
  end
  return true
end

-- Drop the blank cells at the end of a row (never the first one: an empty
-- string would read as the end of the table).
local function trim_cells(cells)
  local blank = string.rep("\0", TILE_BYTES)
  local last = 1
  for i, tile in ipairs(cells) do
    if tile ~= blank then last = i end
  end
  local out = {}
  for i = 1, last do out[i] = cells[i] end
  return out
end

-- Build both the strings and the five button lists from one deduplicated atlas.
local function build_sheet(all_cells, stage, buttons)
  local index, order = {}, {}
  local function add(tile)
    if not index[tile] then
      if #order >= MAX_TILES then
        error(string.format(
          "%s: the labels use more than %d distinct glyphs, over the %d-tile sheet",
          stage, MAX_TILES, MAX_TILES), 0)
      end
      order[#order + 1] = tile
      index[tile] = #order
    end
    return index[tile]
  end

  -- Keep the buttons at the beginning of the atlas, as validated in-game.
  local choice_indices = {}
  for _, choice in ipairs(FORMAT_CHOICES) do
    local indices = {}
    for _, tile in ipairs(buttons[choice]) do indices[#indices + 1] = add(tile) end
    choice_indices[choice] = indices
  end
  local strings = {}
  for i, cells in ipairs(all_cells) do
    strings[i] = {}
    for _, tile in ipairs(cells) do strings[i][#strings[i] + 1] = add(tile) end
  end

  if #order == 0 then
    error(stage .. ": the labels are empty", 0)
  end
  return table.concat(order), strings, choice_indices
end

local function pack_strings(strings)
  local parts = {}
  for _, indices in ipairs(strings) do
    for _, glyph in ipairs(indices) do
      parts[#parts + 1] = string.pack(">I2", glyph)
    end
    parts[#parts + 1] = "\0\0"
  end
  parts[#parts + 1] = "\0\0"      -- the table's own terminator
  return table.concat(parts)
end

-- Every dword in the executable that held a string's RAM address now holds
-- the address of the rewritten string.  The retail table at 0x5A398 is one
-- such list; the C++ does the same sweep (PatchLoadScreen 10599).
local function repoint(data, strings, new_offsets)
  local map = {}
  for i, string in ipairs(strings) do
    map[RAM_BASE + string.offset] = RAM_BASE + new_offsets[i]
  end

  local writes = {}
  for pos = 0, #data - 4, 4 do
    local new = map[be32(data, pos)]
    if new and new ~= be32(data, pos) then
      writes[#writes + 1] = { pos = pos, data = string.pack(">I4", new) }
    end
  end

  local out = data
  for _, write in ipairs(writes) do
    out = out:sub(1, write.pos) .. write.data .. out:sub(write.pos + #write.data + 1)
  end
  return out
end

-- A string is live while some dword in the executable holds its RAM address;
-- every one of those is exactly what repoint rewrites.
local function referenced(data, strings)
  local seen = {}
  for pos = 0, #data - 4, 4 do seen[be32(data, pos)] = true end
  local live = {}
  for i, string in ipairs(strings) do
    live[i] = seen[RAM_BASE + string.offset] or false
  end
  return live
end

local function write_choices(out, original, spec, layouts, indices)
  local records, pointers, cursor = {}, {}, spec.format
  for _, choice in ipairs(FORMAT_CHOICES) do
    local ids = indices[choice]
    local old = layouts[choice]
    pointers[choice] = RAM_BASE + cursor
    for i, id in ipairs(ids) do
      local template = old.records[math.min(i, old.count)]
      local x = #ids == old.count and template:sub(1, 2)
        or string.pack(">i2", -(#ids * TILE) // 2 + (i - 1) * TILE)
      records[#records + 1] = x .. template:sub(3, 8)
        .. string.pack(">I2", (id - 1) * TILE)
    end
    cursor = cursor + #ids * CHOICE_RECORD_BYTES
  end
  if cursor > spec.format + CHOICE_RECORDS * CHOICE_RECORD_BYTES then
    error("load_screen: the five buttons need more than twelve sprite cells", 0)
  end

  local region = table.concat(records)
  out = out:sub(1, spec.format) .. region .. out:sub(spec.format + #region + 1)
  local seen = {}
  for pos = spec.format + 0x90, spec.format + 0x390, 0x10 do
    local pointer = be32(original, pos + 4)
    for _, choice in ipairs(FORMAT_CHOICES) do
      local old = layouts[choice]
      if pointer == old.pointer then
        if be16(original, pos + 2) ~= old.count then
          error(string.format("load_screen: inconsistent %s sprite count", choice.art), 0)
        end
        out = out:sub(1, pos + 2)
          .. string.pack(">I2I4", #indices[choice], pointers[choice])
          .. out:sub(pos + 9)
        seen[choice] = (seen[choice] or 0) + 1
      end
    end
  end
  for _, choice in ipairs(FORMAT_CHOICES) do
    if seen[choice] ~= choice.refs then
      error(string.format("load_screen: expected %d %s sprite records, found %d",
        choice.refs, choice.art, seen[choice] or 0), 0)
    end
  end
  return out
end

local function position_episode_numbers(out, original, spec, strings)
  local five = 0
  for row = 1, EPISODE_ROWS do
    if #strings[episode_index(row)] == EPISODE_CELLS then five = five + 1 end
  end
  if five == 0 then return out end
  if five ~= EPISODE_ROWS then
    error("load_screen: episode numbers share one X position; all ten must use five cells", 0)
  end

  local opcode = be16(original, spec.number_x)
  if opcode ~= 0x75B8 and opcode ~= 0x75A8 then
    error("load_screen: unexpected episode-number X instruction", 0)
  end
  return out:sub(1, spec.number_x) .. string.pack(">I2", 0x75A8)
    .. out:sub(spec.number_x + 3)
end

local FONT_BASE_CODE = { 0x38DD4, 0x3902C, 0x394F8, 0x398AC }
local FONT_BASE_DATA = { 0x59BEC, 0x59BF4, 0x59BFC }
local NEXT_BASE_CODE = { 0x393C8, 0x39994 }
local NEXT_BASE_DATA = { 0x59C04 }

local function position_font(out, spec, size)
  local relocate = size > FONT_WINDOW
  local disc2 = spec == DISC2
  -- CD2's preceding image ends at 0x77F80 after moving it; CD1 needs no move.
  out = patch_u32(out, 0x394C8 + spec.code_delta,
    0x75000, 0x74C80, relocate and disc2)
  for _, offset in ipairs(FONT_BASE_CODE) do
    out = patch_u32(out, offset + spec.code_delta,
      0x78800, disc2 and 0x78000 or 0x77F00, relocate)
  end
  for _, offset in ipairs(FONT_BASE_DATA) do
    out = patch_u32(out, offset + spec.data_delta,
      0x78800, disc2 and 0x78000 or 0x77F00, relocate)
  end
  for _, offset in ipairs(NEXT_BASE_CODE) do
    out = patch_u32(out, offset + spec.code_delta, 0x7D000, 0x7DA80, relocate)
  end
  for _, offset in ipairs(NEXT_BASE_DATA) do
    out = patch_u32(out, offset + spec.data_delta, 0x7D000, 0x7DA80, relocate)
  end
  out = patch_u32(out, 0x5A4C0 + spec.data_delta,
    0x060EA800, 0x060EA480, relocate and disc2)
  out = patch_u32(out, 0x5A4C8 + spec.data_delta,
    0x060EE000, disc2 and 0x060ED800 or 0x060ED700, relocate)
  out = patch_u32(out, 0x5A4D0 + spec.data_delta,
    0x060F2800, 0x060F3280, relocate)
  return patch_u32(out, 0x35E28 + spec.code_delta,
    0x14D80, 0x15800, relocate)
end

function codec.encode(original, artifacts, args)
  check_layout()
  local block_offset, _, decompressed, spec = find_block(original, args)
  local dir = prefix(args)
  local by_name = {}
  for _, artifact in ipairs(artifacts or {}) do
    by_name[artifact.name] = artifact.data
  end

  local rebuilt = decompressed
  for _, region in ipairs(REGIONS) do
    local bmp_data = by_name[string.format("%s/%s", dir, region.name)]
    if bmp_data then
      local size = region_size(region)
      local pixels = bmp.parse(bmp_data, region.width, region.height, BPP)
      local old = decompressed:sub(region.off + 1, region.off + size)
      if pixels ~= old then
        rebuilt = rebuilt:sub(1, region.off) .. pixels
          .. rebuilt:sub(region.off + size + 1)
      end
    end
  end
  for _, region in ipairs(ARROWS) do
    local size = region_size(region)
    local bmp_data = by_name[string.format("%s/%s", dir, region.name)]
    local pixels = bmp_data and bmp.parse(bmp_data, region.width, region.height, BPP)
      or decompressed:sub(region.off + 1, region.off + size)
    if pixels ~= rebuilt:sub(region.off + 1, region.off + size) then
      rebuilt = rebuilt:sub(1, region.off) .. pixels
        .. rebuilt:sub(region.off + size + 1)
    end
  end

  local out = original
  if rebuilt ~= decompressed then
    local compressed = prs:encode("", { { name = "LOAD_SCREEN", data = rebuilt } })
    if #compressed > COMPRESSED_SIZE then
      error(string.format(
        "load_screen: compressed block size %d exceeds limit %d",
        #compressed, COMPRESSED_SIZE), 0)
    end
    if #compressed < COMPRESSED_SIZE then
      compressed = compressed .. string.rep("\0", COMPRESSED_SIZE - #compressed)
    end

    out = out:sub(1, block_offset) .. compressed
      .. out:sub(block_offset + COMPRESSED_SIZE + 1)
  end

  -- Labels are optional: an image-only edit leaves the font and strings alone.
  local sheet, tiles = read_font(original, spec, "encode")
  local strings = read_strings(original, spec.strings, tiles, "encode",
    spec.strings + STRING_BUDGET)

  local images, numbers, titles, commands, any = {}, nil, nil, {}, false
  for _, single in ipairs(SINGLES) do
    local name = single_name(dir, single)
    if by_name[name] then
      any = true
      images[single.index] = by_name[name]
    end
  end
  if by_name[episode_name(dir)] then
    any = true
    numbers = stacked_rows(by_name[episode_name(dir)], episode_name(dir),
      EPISODE_CELLS, EPISODE_ROWS)
  end
  if by_name[title_name(dir)] then
    any = true
    titles = stacked_rows(by_name[title_name(dir)], title_name(dir),
      TITLE_CELLS, TITLE_ROWS)
  end
  for _, group in ipairs(LABEL_SHEETS) do
    local name = sheet_name(dir, group)
    if by_name[name] then
      any = true
      commands[group] = stacked_rows(by_name[name], name, group.cells,
        #group.indices)
    end
  end

  local layouts, buttons, choice_changed, button_cells = {}, {}, false, 0
  for _, choice in ipairs(CHOICES) do
    local name = choice_name(dir, choice)
    local layout = read_choice(original, spec, sheet, tiles, choice)
    layouts[choice] = layout
    local image = by_name[name]
    local cells = layout.cells
    if image then
      any = true
      cells = label_cells(image, name)
      if #cells ~= layout.count or not same_cells(cells, layout.cells) then
        choice_changed = true
      end
    end
    buttons[choice] = cells
    button_cells = button_cells + #cells
  end
  if button_cells > CHOICE_RECORDS then
    error(string.format("load_screen: the five buttons need %d sprite cells, over the %d available",
      button_cells, CHOICE_RECORDS), 0)
  end

  if any then
    -- A label that is not supplied keeps its retail string, so editing one
    -- episode name does not require carrying the other 44 images.
    local cells, changed = {}, false
    for index, string in ipairs(strings) do
      local number_row = EPISODE_ROW[index]
      local title_row = TITLE_ROW[index]
      local current = glyph_tiles(sheet, string.indices)
      if number_row and numbers then
        -- Untouched rows keep the retail string; a row that draws anything
        -- different becomes all five cells, the size of the draw area.
        cells[index] = same_cells(numbers[number_row], current)
          and current or numbers[number_row]
      elseif title_row and titles then
        -- A title has no fixed area: it keeps exactly the cells it is drawn in.
        cells[index] = trim_cells(titles[title_row])
      elseif SHEET_ROW[index] and commands[SHEET_GROUP[index]] then
        -- A sheet row is independent too: store the cells it is drawn in.
        cells[index] = trim_cells(
          commands[SHEET_GROUP[index]][SHEET_ROW[index]])
      elseif images[index] then
        local single = SINGLE_OF[index]
        cells[index] = trim_cells(label_cells(images[index], single_name(dir, single)))
      else
        cells[index] = current
      end

      local supplied = cells[index]
      if #supplied ~= #current then
        changed = true
      else
        for k = 1, #current do
          if supplied[k] ~= current[k] then changed = true end
        end
      end
    end

    if changed or choice_changed then
      -- Strings no dword in the file addresses are retail leftovers (the load
      -- screen never draws them), so a block that does not fit may drop them.
      -- Ten rows that use their new cells need four bytes each more than the
      -- retail area holds, which is exactly what this frees.
      local live = referenced(original, strings)
      local new_sheet, new_strings, choice_indices = build_sheet(cells, "encode", buttons)
      local packed = pack_strings(new_strings)
      if #packed > STRING_BUDGET then
        -- A dead entry becomes one blank glyph rather than nothing: the table
        -- ends on two zeroes, and two emptied neighbours (28 and 29 are both
        -- dead) would cut every string after them off.
        local BLANK = string.rep("\0", TILE_BYTES)
        local kept = {}
        for i, list in ipairs(cells) do
          kept[i] = live[i] and list or { BLANK }
        end
        new_sheet, new_strings, choice_indices = build_sheet(kept, "encode", buttons)
        packed = pack_strings(new_strings)
      end

      local compressed = prs:encode("", { { name = "LOAD_SCREEN_FONT", data = new_sheet } })
      if #compressed > FONT_SLOT then
        error(string.format(
          "load_screen: the %d-glyph sheet compresses to %d bytes, over the %d-byte slot",
          #new_sheet // TILE_BYTES, #compressed, FONT_SLOT), 0)
      end

      -- The pointer table follows the strings immediately, so the block is a
      -- hard budget: a longer translation would overwrite it.
      if #packed > STRING_BUDGET then
        error(string.format(
          "load_screen: the labels need %d string bytes, over the %d-byte area before the pointer table",
          #packed, STRING_BUDGET), 0)
      end

      local slot = compressed .. string.rep("\0", FONT_SLOT - #compressed)
      out = out:sub(1, spec.font) .. slot .. out:sub(spec.font + FONT_SLOT + 1)
      out = position_font(out, spec, #new_sheet)

      local offsets, cursor = {}, spec.strings
      for index, indices in ipairs(new_strings) do
        offsets[index] = cursor
        cursor = cursor + (#indices + 1) * 2
      end

      -- Zero the rest of the area: a shorter translation leaves no half string
      -- behind, and the double zero before the pointer table is always clean.
      local region = packed .. string.rep("\0", STRING_BUDGET - #packed)
      if region ~= out:sub(spec.strings + 1, spec.strings + STRING_BUDGET) then
        out = out:sub(1, spec.strings) .. region
          .. out:sub(spec.strings + STRING_BUDGET + 1)
      end
      out = repoint(out, strings, offsets)
      out = write_choices(out, original, spec, layouts, choice_indices)
      out = position_episode_numbers(out, original, spec, new_strings)
    end
  end

  return out
end

return codec
