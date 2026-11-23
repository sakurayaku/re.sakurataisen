--[[
  Sakura Taisen (Saturn) — status screen strings

  PATCH plugin for the SAKURA executable.

  SakuraTaisen.cpp: ExtractStatusScreen 1664, PatchStatusScreen 10654.

  The status screen's labels are not text: each one is a list of big-endian
  glyph indices, 0-terminated, into the font sheet that
  scripts/status_screen_gfx.lua patches inside SAKURA1/ICATALL.DAT.  The
  reference's SakuraFontSheet uses index - 1, so glyph 1 is tile 0 of that
  sheet.

  ## The tables

  Disc 1

      0x5F428 .. 0x5F4B3   140 bytes   the 18 strings
      0x5F4B4 .. 0x5F4E3    48 bytes   12 RAM pointers
      0x3E458 .. 0x3E463    12 bytes   3 stats pointers

  Disc 2 inserts 24 bytes early and 288 more at 0x52E00, so the string area and
  its pointer table move by +0x138 (0x5F560 / 0x5F5EC) and everything below
  0x52E00 — the stats pointers and the drawing code — by +0x18.

  Every pointer is a big-endian u32 RAM address: the file offset plus
  0x06004000.  The twelve address slots 1, 5, 6, 3, 2, 4, 7, 8, 9, 10, 11, 12 --
  the table's order is not the string order, so it is read from the file rather
  than assumed -- and the three stats pointers address slots 13, 14, 15.

  Slots 16 .. 18 are addressed by no pointer table but are not dead: the stats
  formatter's literal pool holds their RAM addresses directly (0x06063496 and
  0x0606349E on disc 1).  Slot 16 is the padding glyph written between the label
  and the number, slot 17 a separator, and slot 18 the ten digit glyphs indexed
  by 0..9.  A rebuild keeps all three and moves them with the labels, so it also
  rewrites the two pool words that point at them.

  ## Two string formats

  Retail writes every glyph index as a big-endian u16, and the English build
  keeps that but makes the stats formatter read two of them at once (the four
  SH-2 words at 0x3E3F2, 0x3E3F8, 0x3E3FC and 0x3E3FE).  Both are decoded here.

  This codec's own builds write **one byte per glyph** for the fifteen labels,
  because the 140-byte area is a hard budget: at two bytes per glyph the labels
  may use 37 cells, at one byte 92..95 depending on the alignment the stats
  cost.  The tail (padding, separator, digits) stays u16, so the formatter's two
  pool dwords do not move.

  The byte format is a code change, not just a layout one:

    * The label drawer at 0x3E674 reads the string it is handed one glyph at a
      time.  Its only two callers pass it status-screen text — the panel routine
      hands it a label straight from the twelve-pointer table, and the stats
      routine hands it the line buffer the formatter filled — so its
      `mov.w @r8+,r3` (0x6385) becomes `mov.b @r8+,r3` (0x6384).  Glyph values
      stay below 0x80, so the `extu.w` that follows is still correct.
    * The stats formatter's line buffer becomes bytes with it: four blank
      glyphs, the label's two bytes, the number, the padding and the 0
      terminator.  With byte slots the retail instruction shape is already
      right — `mov.w @r1,r1` picks up both label bytes and `mov.w r1,@r6` stores
      them — so the four English longword words are reverted and only the buffer
      offsets and store widths change.  The digit table and the padding glyph
      are still loaded with `mov.w` from the pool and stored as bytes.
    * The line is filled with a fixed glyph (`mov #20,r2` at 0x3E3AE).  Retail's
      glyph 20 happens to be an empty cell, so the fill draws nothing; a rebuilt
      atlas has text there.  The tail therefore ends with an empty cell and the
      immediate is repointed at it, or every zero stat would show that cell's
      letters where its number belongs.

  `read_format` recognises the three states from those instruction words, so a
  retail or English file is still read correctly and a half-patched file is
  refused instead of misread.

  ## The labels are the source

  The glyph lists are not edited by hand here: they are derived from the three
  canvases scripts/status_screen_gfx.lua decodes from ICATALL.DAT --
  `STATUS_NAMES.bmp` (labels 1..6), `STATUS_MOODS.bmp` (7..12) and
  `STATUS_STATS.bmp` (13..15), one label per row.  A build that edits one
  re-cuts every label into 16x16 cells,
  de-duplicates them into the sheet and writes the index lists that point at
  it, so a translation draws whole sentences instead of picking Japanese
  glyphs.

  Both codecs derive the atlas from the same canvases through
  scripts/shared/status_labels.lua, so the sheet this codec's indices describe
  is exactly the one the graphics codec writes.  That is why the two nodes
  belong in the manifest together: rewriting one without the other leaves the
  strings pointing at another build's tiles.

  The canvases are read at build time from the ICATALL node -- the workspace
  override when there is one, the pristine decoded artifact otherwise.  Both
  discs ship the same ICATALL.DAT, so the other disc's node is tried as well.
  With no ICATALL node to read, this codec leaves the executable alone rather
  than write indices for a sheet nobody is rebuilding.

  ## decode

  decode writes `STATUS_TEXT.txt`: the slot layout as it stands, as
  documentation of what the indices currently mean, and which of the three
  formats the formatter is in.  It is not an input -- editing it does nothing,
  because the labels decide the indices.

  ## The budget

  The string area is fixed: the pointer table follows it immediately, so a
  table that grows past 140 bytes would overwrite the twelve pointers.  The
  fifteen labels come first, then the three tail slots (padding, separator,
  digits), which cost 30 bytes and leave 110 for the labels.  In the byte
  format a label costs one byte per glyph plus its terminator, and a stats
  string is read with one `mov.w`, so it starts on an even offset and may cost
  one 0 byte of alignment; the tail likewise starts even.  The padding bytes
  are skipped when the file is read back.

  The byte format carries glyphs 1 .. 127 (the drawer sign-extends a byte), and
  the digits are stored through the same byte buffer, so the whole atlas —
  labels plus the twelve tail cells — has to stay below 128 tiles.
]]--

local constants = dofile(LUDARED.SCRIPTS .. "/shared/constants.lua")
local can_handle = dofile(LUDARED.SCRIPTS .. "/shared/can_handle.lua")
local bmp = dofile(LUDARED.SCRIPTS .. "/shared/bmp.lua")
local labels = dofile(LUDARED.SCRIPTS .. "/shared/status_labels.lua")

local codec = {}

codec.name        = "Sakura Taisen Status Screen Strings"
codec.description = "Derives the status-screen glyph strings from the label canvases in the SAKURA executable"
  codec.version     = 7
codec.kind        = "patch"

local LABEL      = "status_screen_metadata"
local RAM_BASE   = 0x06004000
local MAX_GLYPH  = labels.MAX_TILES
local TEXT_NAME  = "STATUS_TEXT.txt"

-- The stats pointer table is three dwords below the 0x52E00 split on disc 1,
-- so disc 2 moves it by +0x18 rather than the +0x138 the string area takes.
-- The formatter and the drawer are below that split too.
local DISCS = {
  [constants.CD1_SAKURA_BYTES] = {
    number = 1, track = "SakTaiCD1_Track1.bin",
    text = 0x5F428, pointers = 0x5F4B4, stats = 0x3E458,
    pool_digits = 0x3E468, pool_pad = 0x3E46C,
  },
  [constants.CD2_SAKURA_BYTES] = {
    number = 2, track = "SakTaiCD2_Track1.bin",
    text = 0x5F560, pointers = 0x5F5EC, stats = 0x3E470,
    pool_digits = 0x3E480, pool_pad = 0x3E484,
  },
}

local POINTER_COUNT      = 12
local STAT_POINTER_COUNT = 3

-- The drawer's glyph load, at 0x3E69C on disc 1: `mov.w @r8+,r3` reads a u16
-- string, `mov.b @r8+,r3` the byte format.
local DRAWER_LOAD = 0x3E69C

-- The stats formatter starts its line by filling four slots with `mov #20,r2`
-- (0x3E3AE on disc 1).  Retail's glyph 20 is a blank cell, so the fill draws
-- nothing.  A rebuilt atlas has text at that index, so the tail carries an
-- empty cell and this immediate is repointed at it -- otherwise every zero stat
-- would show that cell's letters instead of a blank.
local BLANK_FILL = 0x3E3AE
local BLANK_FILL_RETAIL = 0xE214

-- The formatter words the byte format touches, disc-1 offsets, with the retail
-- value and the byte-format value.  The four stats-string accesses are shared
-- with the English build, which uses longwords because its buffer is u16; with
-- a byte buffer the retail words are already right.
local FORMATTER_WORDS = {
  { 0x3E3B0, 0x2621, 0x2620 },  -- mov.w -> mov.b: blank into line+0
  { 0x3E3B4, 0x7102, 0x7101 },  -- line+1
  { 0x3E3B6, 0x2121, 0x2120 },
  { 0x3E3BA, 0x7104, 0x7102 },  -- line+2
  { 0x3E3BC, 0x2121, 0x2120 },
  { 0x3E3C0, 0x7106, 0x7103 },  -- line+3
  { 0x3E3C2, 0x2121, 0x2120 },
  { 0x3E3C6, 0x7208, 0x7204 },  -- line+4, the terminator
  { 0x3E3D0, 0x2211, 0x2210 },  -- mov.w -> mov.b: the terminator
  { 0x3E3F2, 0x6111, 0x6111 },  -- the label's two glyph bytes
  { 0x3E3F8, 0x6111, 0x6111 },
  { 0x3E3FC, 0x6111, 0x6111 },
  { 0x3E3FE, 0x2611, 0x2611 },  -- both into line+0 and line+1
  { 0x3E414, 0x7206, 0x7203 },  -- line+3, the units digit
  { 0x3E434, 0x2211, 0x2210 },
  { 0x3E43C, 0x7604, 0x7602 },  -- line+2, padding after one digit
  { 0x3E446, 0x7204, 0x7202 },  -- line+2, the tens digit
  { 0x3E448, 0x2211, 0x2210 },
  { 0x3E44E, 0x7602, 0x7601 },  -- line+1, padding after two digits
  { 0x3E450, 0x2611, 0x2610 },  -- mov.w -> mov.b
  { DRAWER_LOAD, 0x6385, 0x6384 },  -- mov.w -> mov.b: the drawer's glyph load
}

-- The English build's four longword words, which a byte build has to undo.
local ENGLISH_WORDS = {
  [0x3E3F2] = 0x6112, [0x3E3F8] = 0x6112,
  [0x3E3FC] = 0x6112, [0x3E3FE] = 0x2612,
}

local FORMATS = {
  u8  = { kind = "u8",  text = "one byte per glyph (labels u8, tail u16)" },
  u16 = { kind = "u16", text = "two-byte glyphs (retail)" },
  english = { kind = "u16", text = "two-byte glyphs with the English longword reads" },
}

local function prefix(args)
  local value
  if type(args) == "table" then value = args.prefix else value = args end
  if not value or value == "" then value = "STATUS" end
  return (value:gsub("/+$", ""))
end

local function disc_of(data, stage)
  if type(data) ~= "string" then
    error(string.format("%s: %s: expected a binary string", LABEL, stage), 0)
  end
  local disc = DISCS[#data]
  if not disc then
    error(string.format(
      "%s: %s: %d bytes is not a retail SAKURA (%d on disc 1, %d on disc 2)",
      LABEL, stage, #data, constants.CD1_SAKURA_BYTES, constants.CD2_SAKURA_BYTES), 0)
  end
  return disc
end

local function code_shift(disc)
  return disc.number == 2 and 0x18 or 0
end

local function u16(data, offset, stage)
  if offset + 2 > #data then
    error(string.format("%s: %s: u16 at 0x%06X is outside the file", LABEL, stage, offset), 0)
  end
  return string.unpack(">I2", data, offset + 1)
end

local function u32(data, offset, stage)
  if offset + 4 > #data then
    error(string.format("%s: %s: u32 at 0x%06X is outside the file", LABEL, stage, offset), 0)
  end
  return string.unpack(">I4", data, offset + 1)
end

-- Which of the three string formats the file's formatter is in.  The drawer's
-- load and the formatter's first store separate a byte build from a u16 one,
-- and the stats-string words separate retail from the English longword patch.
local function read_format(data, disc, stage)
  local shift = code_shift(disc)
  local drawer = u16(data, DRAWER_LOAD + shift, stage)
  local buffer = u16(data, 0x3E3B0 + shift, stage)
  local load   = u16(data, 0x3E3F2 + shift, stage)
  local store  = u16(data, 0x3E3FE + shift, stage)

  if drawer == 0x6384 and buffer == 0x2620 and load == 0x6111 and store == 0x2611 then
    return FORMATS.u8
  end
  if drawer == 0x6385 and buffer == 0x2621 then
    if load == 0x6112 and store == 0x2612 then return FORMATS.english end
    if load == 0x6111 and store == 0x2611 then return FORMATS.u16 end
  end

  error(string.format(
    "%s: %s: the status formatter at 0x%06X is neither retail, the English "
    .. "longword patch, nor this codec's byte format (drawer 0x%04X, buffer "
    .. "0x%04X, stats load 0x%04X, store 0x%04X)",
    LABEL, stage, DRAWER_LOAD + shift, drawer, buffer, load, store), 0)
end

-- The u16 format: a string ends on a 0 word, and a run of 0 words between
-- strings is alignment padding that is skipped rather than read as the end.
local function read_slots_u16(data, disc, stage)
  local area_end = disc.pointers
  local slots, pos = {}, disc.text

  while pos + 2 <= area_end do
    while pos + 2 <= area_end and u16(data, pos, stage) == 0 do pos = pos + 2 end
    if pos + 2 > area_end then break end

    local indices, start = {}, pos
    while true do
      if pos + 2 > area_end then
        error(string.format(
          "%s: %s: the string at 0x%06X has no terminator before the pointer table at 0x%06X",
          LABEL, stage, start, area_end), 0)
      end
      local value = u16(data, pos, stage)
      pos = pos + 2
      if value == 0 then break end
      if value > MAX_GLYPH then
        error(string.format(
          "%s: %s: the string at 0x%06X holds glyph %d; the sheet has %d tiles",
          LABEL, stage, start, value, MAX_GLYPH), 0)
      end
      indices[#indices + 1] = value
    end

    slots[#slots + 1] = { start = start, indices = indices }
  end

  if #slots == 0 then
    error(string.format("%s: %s: no strings found at 0x%06X", LABEL, stage, disc.text), 0)
  end
  return slots
end

-- The byte format: fifteen byte strings, then the u16 tail on an even offset.
-- The tail's two pool pointers are checked against where it actually sits, so
-- a file whose area and formatter disagree is refused rather than drawn wrong.
local function read_slots_u8(data, disc, stage)
  local slots, pos = {}, disc.text

  for i = 1, labels.SLOTS do
    while pos < disc.pointers and data:byte(pos + 1) == 0 do pos = pos + 1 end
    if pos >= disc.pointers then
      error(string.format(
        "%s: %s: the area at 0x%06X holds only %d of the %d label strings",
        LABEL, stage, disc.text, i - 1, labels.SLOTS), 0)
    end

    local indices, start = {}, pos
    while true do
      if pos >= disc.pointers then
        error(string.format(
          "%s: %s: the string at 0x%06X has no terminator before the pointer table at 0x%06X",
          LABEL, stage, start, disc.pointers), 0)
      end
      local value = data:byte(pos + 1)
      pos = pos + 1
      if value == 0 then break end
      if value > 127 then
        error(string.format(
          "%s: %s: the string at 0x%06X holds glyph %d; the byte format carries 1 .. 127",
          LABEL, stage, start, value), 0)
      end
      if value > MAX_GLYPH then
        error(string.format(
          "%s: %s: the string at 0x%06X holds glyph %d; the sheet has %d tiles",
          LABEL, stage, start, value, MAX_GLYPH), 0)
      end
      indices[#indices + 1] = value
    end

    slots[i] = { start = start, indices = indices }
  end

  if pos % 2 ~= 0 then pos = pos + 1 end

  for k = 1, 3 do
    local indices, start = {}, pos
    while true do
      if pos + 2 > disc.pointers then
        error(string.format(
          "%s: %s: the tail string at 0x%06X has no terminator before the pointer table",
          LABEL, stage, start), 0)
      end
      local value = u16(data, pos, stage)
      pos = pos + 2
      if value == 0 then break end
      if value > MAX_GLYPH then
        error(string.format(
          "%s: %s: the tail string at 0x%06X holds glyph %d; the sheet has %d tiles",
          LABEL, stage, start, value, MAX_GLYPH), 0)
      end
      indices[#indices + 1] = value
    end
    slots[labels.SLOTS + k] = { start = start, indices = indices }
  end

  local tail = slots[labels.SLOTS + 1].start
  local pad_at, digits_at = u32(data, disc.pool_pad, stage), u32(data, disc.pool_digits, stage)
  if pad_at ~= RAM_BASE + tail or digits_at ~= RAM_BASE + tail + 8 then
    error(string.format(
      "%s: %s: the formatter's padding pointer is 0x%08X and its digit pointer "
      .. "0x%08X, but the tail sits at 0x%08X; the string area and the formatter disagree",
      LABEL, stage, pad_at, digits_at, RAM_BASE + tail), 0)
  end

  return slots
end

local function read_slots(data, disc, format, stage)
  if format.kind == "u8" then return read_slots_u8(data, disc, stage) end
  return read_slots_u16(data, disc, stage)
end

-- Each pointer is the RAM address of one slot's first glyph.  Reading the slot
-- from the address, rather than assuming an order, is what lets a rebuilt file
-- be patched again.
local function read_pointers(data, disc, slots, base, count, what, stage)
  local slot_of_start = {}
  for i, slot in ipairs(slots) do slot_of_start[slot.start] = i end

  local out = {}
  for i = 0, count - 1 do
    local at = base + i * 4
    local value = u32(data, at, stage)
    local slot = slot_of_start[value - RAM_BASE]
    if not slot then
      error(string.format(
        "%s: %s: %s entry %d at 0x%06X holds 0x%08X, which is not the start of a string",
        LABEL, stage, what, i + 1, at, value), 0)
    end
    out[i + 1] = slot
  end
  return out
end

-- Lay the strings out in slot order from the area's start, then the three tail
-- slots.  A label costs one byte per glyph plus its terminator.  A stats string
-- is read with one `mov.w`, and the tail with `mov.w` too, so both start on an
-- even offset; when the preceding bytes end on an odd one that costs a 0 byte,
-- which read_slots skips.  Returns the whole area (zero-padded to the pointer
-- table), where each label begins, and where the tail slots begin.
local function build_area(lists, extras, disc, stage)
  local parts, starts, tail_starts, cursor = {}, {}, {}, 0

  local function align()
    if (disc.text + cursor) % 2 ~= 0 then
      parts[#parts + 1] = "\0"
      cursor = cursor + 1
    end
  end

  local function put_bytes(indices)
    local bytes = {}
    for k, glyph in ipairs(indices) do bytes[k] = string.char(glyph) end
    bytes[#bytes + 1] = "\0"
    parts[#parts + 1] = table.concat(bytes)
    cursor = cursor + #parts[#parts]
  end

  local function put_words(indices)
    local words = {}
    for k, glyph in ipairs(indices) do words[k] = string.pack(">I2", glyph) end
    words[#words + 1] = "\0\0"
    parts[#parts + 1] = table.concat(words)
    cursor = cursor + #parts[#parts]
  end

  for i, glyphs in ipairs(lists) do
    if labels.is_stats(i) then align() end
    starts[i] = disc.text + cursor
    put_bytes(glyphs)
  end

  align()

  for _, glyphs in ipairs({ { extras.pad }, { extras.gap }, extras.digits }) do
    tail_starts[#tail_starts + 1] = disc.text + cursor
    put_words(glyphs)
  end

  local room = disc.pointers - disc.text
  if cursor > room then
    error(string.format(
      "%s: %s: the labels need %d bytes of glyph indices but the area before the "
      .. "pointer table holds %d; %d bytes too many.  Shorten the widest labels",
      LABEL, stage, cursor, room, cursor - room), 0)
  end

  return table.concat(parts) .. string.rep("\0", room - cursor), starts, tail_starts
end

local function build_pointers(slots, starts)
  local out = {}
  for i, slot in ipairs(slots) do
    out[i] = string.pack(">I4", RAM_BASE + starts[slot])
  end
  return table.concat(out)
end

local function replace(data, offset, bytes)
  return data:sub(1, offset) .. bytes .. data:sub(offset + #bytes + 1)
end

-- A group canvas as one label strip per row; its own header gives the size and
-- depth, since a translation is free to widen it or to save it from an editor.
local function group_strips(image, group, stage)
  local ok, pixels, width, height = pcall(labels.read_canvas, image, group.name)
  if not ok then
    error(string.format("%s: %s: %s", LABEL, stage, tostring(pixels)), 0)
  end
  return labels.split_group(group, pixels, width, height)
end

-- Read the pristine artifact of one ICATALL output through the decode cache.
local function cache_cat(vpath)
  local pipe = io.popen("ludared cache cat '" .. vpath .. "' 2>/dev/null", "r")
  if not pipe then return nil end
  local data = pipe:read("*a")
  if not pipe:close() or not data or data == "" then return nil end
  return data
end

-- The label canvases of this build: the workspace override where there is one,
-- the pristine decoded artifact otherwise.  Both discs carry the same
-- ICATALL.DAT, so this disc's node is tried first and the other one second.
local function label_sources(disc, dir, stage)
  local other = disc.number == 2 and DISCS[constants.CD1_SAKURA_BYTES]
    or DISCS[constants.CD2_SAKURA_BYTES]
  local tracks = { disc.track, other.track }

  -- One canvas per group, from the workspace when it is overridden and from the
  -- decode cache otherwise.
  local function read_group(name, from_workspace)
    for _, track in ipairs(tracks) do
      local vpath = track .. "/SAKURA1/ICATALL.DAT/" .. dir .. "_" .. name
      if from_workspace then
        local file = io.open(LUDARED.WORKSPACE .. "/" .. vpath, "rb")
        if file then
          local data = file:read("*a")
          file:close()
          if data and data ~= "" then return data end
        end
      else
        local data = cache_cat(vpath)
        if data then return data end
      end
    end
    return nil
  end

  local pristine, override, missing, edited = {}, {}, false, false
  for _, group in ipairs(labels.GROUPS) do
    local cached = read_group(group.name, false)
    local workspace = read_group(group.name, true)

    if not cached then missing = true end
    if cached then
      local rows = group_strips(cached, group, stage)
      for k, slot in ipairs(group.slots) do pristine[slot] = rows[k] end
    end
    if workspace then
      edited = true
      local rows = group_strips(workspace, group, stage)
      for k, slot in ipairs(group.slots) do override[slot] = rows[k] end
    end
  end

  -- STATUS_DIGITS.bmp does not change a string, but it rebuilds the sheet, and a
  -- rebuilt sheet is only consistent with rewritten strings and the patched
  -- formatter.  So an edited digit canvas counts as an edit too.
  local digits_edit = false
  do
    local cached = read_group(labels.DIGITS.name, false)
    local workspace = read_group(labels.DIGITS.name, true)
    digits_edit = workspace ~= nil and cached ~= nil and workspace ~= cached
  end

  if missing then
    if edited or digits_edit then
      error(string.format(
        "%s: %s: label overrides exist but the ICATALL.DAT status node is not "
        .. "decoded, so the untouched labels cannot be read.  Add or unpack that node first",
        LABEL, stage), 0)
    end
    return nil
  end

  local changed = false
  for i = 1, labels.SLOTS do
    if override[i] and override[i].pixels ~= pristine[i].pixels then changed = true end
  end
  if not changed and not digits_edit then return nil end

  return function(index) return override[index] or pristine[index] end
end

function codec.can_handle(data)
  return can_handle.can_handle_sakura1(data)
end

function codec.decode_name(args)
  return prefix(args)
end

function codec.decode(data, args)
  local disc = disc_of(data, "decode")
  local format = read_format(data, disc, "decode")
  local slots = read_slots(data, disc, format, "decode")
  local pointers = read_pointers(data, disc, slots, disc.pointers,
    POINTER_COUNT, "12-pointer table", "decode")
  local stats = read_pointers(data, disc, slots, disc.stats,
    STAT_POINTER_COUNT, "stats pointer", "decode")

  local lines = {
    string.format("# Sakura Taisen status screen strings — disc %d, 0x%06X",
      disc.number, disc.text),
    string.format("# format: %s", format.text),
    "# The glyph lists as they stand.  This file is documentation only: the",
    "# labels in the ICATALL.DAT node's STATUS_NAMES.bmp, STATUS_MOODS.bmp and",
    "# STATUS_STATS.bmp decide what",
    "# the encoder writes, and editing this file changes nothing.",
    "#",
    "# 12-pointer table -> slots " .. table.concat(pointers, ", "),
    "# stats pointers   -> slots " .. table.concat(stats, ", "),
    "# Slots 16 .. 18 are the formatter's padding glyph, separator and digit",
    "# table; a rebuilt table keeps them and moves them with the labels.",
    "",
  }

  for i, slot in ipairs(slots) do
    local words = { tostring(i) }
    for k, glyph in ipairs(slot.indices) do words[k + 1] = tostring(glyph) end
    lines[#lines + 1] = table.concat(words, " ")
  end

  return {
    { name = prefix(args) .. "/" .. TEXT_NAME, data = table.concat(lines, "\n") .. "\n" },
  }
end

-- Point the formatter's line fill at the atlas's empty cell.  Retail's value
-- is `mov #20,r2`; a byte build writes `mov #<blank>,r2`, and both are accepted
-- so the patch stays idempotent.
local function patch_blank(data, disc, glyph, stage)
  local at = BLANK_FILL + code_shift(disc)
  local word = u16(data, at, stage)
  local want = 0xE200 + glyph
  if word ~= BLANK_FILL_RETAIL and word ~= want then
    error(string.format(
      "%s: %s: the formatter's line fill at 0x%06X holds 0x%04X, not the retail "
      .. "0x%04X", LABEL, stage, at, word, BLANK_FILL_RETAIL), 0)
  end
  if word == want then return data end
  return replace(data, at, string.pack(">I2", want))
end

-- Rewrite the tables from a reader that returns label strips 1 .. 15 as
-- { pixels, width }.  Split out of encode so the atlas can be exercised
-- without a decoded ICATALL node.
function codec.patch_strings(original, read_label, args)
  local stage = "encode"
  local disc = disc_of(original, stage)
  local format = read_format(original, disc, stage)
  local slots = read_slots(original, disc, format, stage)
  local pointers = read_pointers(original, disc, slots, disc.pointers,
    POINTER_COUNT, "12-pointer table", stage)
  local stats = read_pointers(original, disc, slots, disc.stats,
    STAT_POINTER_COUNT, "stats pointer", stage)

  local lists = {}
  for i = 1, labels.SLOTS do
    local strip = read_label(i)
    if type(strip) ~= "table" or type(strip.pixels) ~= "string" then
      error(string.format("%s: %s: label %d is missing", LABEL, stage, i), 0)
    end
    local cells = labels.cells(strip.pixels, strip.width, labels.TILE)
    if labels.is_stats(i) and #cells ~= 2 then
      error(string.format(
        "%s: %s: label %d is %d cells wide, but the stats formatter reads both "
        .. "glyphs with one word; draw it as exactly two cells",
        LABEL, stage, i, #cells), 0)
    end
    lists[i] = cells
  end

  -- The atlas numbers the tail after the labels, so its first index depends
  -- only on how many distinct cells the labels use.  The tail is the padding
  -- glyph, the separator, the ten digits, then the empty cell the formatter's
  -- line fill points at.
  local sheet, indices = labels.atlas(lists)
  local distinct = #sheet // labels.TILE_BYTES
  local blank = distinct + 2 + #labels.DIGIT_GLYPHS + 1
  if blank > labels.MAX_TILES then
    error(string.format(
      "%s: %s: the atlas reaches glyph %d, over the %d-tile sheet",
      LABEL, stage, blank, labels.MAX_TILES), 0)
  end
  if blank > 127 then
    error(string.format(
      "%s: %s: the atlas reaches glyph %d, but the byte format carries glyphs "
      .. "1 .. 127", LABEL, stage, blank), 0)
  end
  local extras = {
    pad = distinct + 1,
    gap = distinct + 2,
    digits = {},
    blank = blank,
  }
  for i = 1, #labels.DIGIT_GLYPHS do
    extras.digits[i] = distinct + 2 + i
  end

  local area, starts, tail_starts = build_area(indices, extras, disc, stage)

  local out = replace(original, disc.text, area)
  out = replace(out, disc.pointers, build_pointers(pointers, starts))
  out = replace(out, disc.stats, build_pointers(stats, starts))
  -- The formatter's literal pool addresses the padding glyph (slot 16) and the
  -- digit table (slot 18) directly; both follow the labels.
  out = replace(out, disc.pool_digits, string.pack(">I4", RAM_BASE + tail_starts[3]))
  out = replace(out, disc.pool_pad, string.pack(">I4", RAM_BASE + tail_starts[1]))
  return patch_blank(out, disc, extras.blank, stage)
end

-- The byte format's code change.  Retail's formatter fills a u16 line buffer
-- and the drawer walks u16 strings; this rewrites both to one byte per glyph so
-- a 140-byte area carries over ninety label glyphs instead of thirty-seven.
-- Every word is checked against the retail, English or byte value, so a file
-- that is not in one of those states is refused rather than mangled.
local function patch_formatter(data, disc, stage)
  local shift = code_shift(disc)
  local out = data
  for _, entry in ipairs(FORMATTER_WORDS) do
    local at, retail, byte = entry[1] + shift, entry[2], entry[3]
    local word = u16(out, at, stage)
    if word ~= retail and word ~= byte and word ~= ENGLISH_WORDS[entry[1]] then
      error(string.format(
        "%s: %s: the status formatter at 0x%06X holds 0x%04X, not the retail "
        .. "0x%04X", LABEL, stage, at, word, retail), 0)
    end
    if word ~= byte then out = replace(out, at, string.pack(">I2", byte)) end
  end
  return out
end

-- Exposed so a test can check the words without a cache to read canvases from.
codec.patch_formatter = function(original)
  local disc = disc_of(original, "patch")
  return patch_formatter(original, disc, "patch")
end

-- Exposed for tests only: which format a file's formatter describes.
codec._format_of = function(original)
  local disc = disc_of(original, "format")
  return read_format(original, disc, "format")
end

function codec.encode(original, artifacts, args)
  local disc = disc_of(original, "encode")
  local read_label = label_sources(disc, prefix(args), "encode")
  if not read_label then return original end
  return patch_formatter(codec.patch_strings(original, read_label, args), disc, "encode")
end

-- Exposed for tests only; the codec contract is decode/encode.
codec._discs = DISCS
codec._label_sources = label_sources

return codec
