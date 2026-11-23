--[[
  Tests for scripts/SAKURA/status_screen_metadata.lua against retail SAKURA.

  The retail status-screen glyph strings are 18 0-terminated big-endian u16
  lists at 0x5F428, filling 140 bytes up to the 12-dword pointer table at
  0x5F4B4.  Each pointer is a RAM address (file offset + 0x06004000); the three
  stats pointers at 0x3E458 address the 13th, 14th and 15th strings, and slots
  16-18 are addressed by the formatter's literal pool.

  This codec's builds switch the fifteen labels to one byte per glyph and keep
  the three tail slots u16: the drawer at 0x3E674 loads glyph bytes with
  `mov.b @r8+,r3`, and the stats formatter's line buffer becomes bytes too.  The
  tests restate both formats from the retail bytes and from the instruction
  words, and never import the codec's tables.

  The expectations are restated from the retail bytes, the reference
  (SakuraTaisen.cpp PatchStatusScreen 10654) and the English build's four
  longword words.
]]

local codec = dofile(LUDARED.SCRIPTS .. "/SAKURA/status_screen_metadata.lua")
local bmp = dofile(LUDARED.SCRIPTS .. "/shared/bmp.lua")
local assets = dofile(LUDARED.SCRIPTS .. "/tests/shared/real_assets.lua")
local prs = LUDARED.codec("std/sega/compression/prs")

local pass, fail = 0, 0

local function check(name, ok, detail)
  if ok then
    pass = pass + 1
    print("  ok    " .. name)
  else
    fail = fail + 1
    print("  FAIL  " .. name .. (detail and ("  -- " .. detail) or ""))
  end
end

local function check_error(name, fn, pattern)
  local ok, err = pcall(fn)
  check(name, not ok and tostring(err):find(pattern) ~= nil,
    ok and "call unexpectedly succeeded" or tostring(err))
end

local file = assert(io.open(LUDARED.PROJECT_ROOT .. "/SAKURA", "rb"),
  "the retail SAKURA executable is required")
local sakura = file:read("*a")
file:close()

local RAM_BASE  = 0x06004000
local TEXT      = 0x5F428
local POINTERS  = 0x5F4B4
local STATS     = 0x3E458
local POOL_DIGITS = 0x3E468
local POOL_PAD  = 0x3E46C
local DRAWER    = 0x3E69C
local ROOM      = POINTERS - TEXT        -- 140
local TAIL_BYTES = 30                    -- pad, separator, ten digits, u16
local CD2_BYTES = 392024
local NAME      = "STATUS/STATUS_TEXT.txt"

local function u16(data, offset)
  return string.unpack(">I2", data, offset + 1)
end

local function u32(data, offset)
  return string.unpack(">I4", data, offset + 1)
end

-- Independent reader of the retail u16 table: skip the 0 word a stats string's
-- alignment leaves, then walk to the string's own terminator, and stop at the
-- pointer table.
local function read_strings(data, text, pointers)
  local out, pos = {}, text
  while pos + 2 <= pointers do
    while pos + 2 <= pointers and u16(data, pos) == 0 do pos = pos + 2 end
    if pos + 2 > pointers then break end
    local indices = {}
    while true do
      local value = u16(data, pos)
      pos = pos + 2
      if value == 0 then break end
      assert(value <= 48, "glyph out of range")
      indices[#indices + 1] = value
    end
    out[#out + 1] = indices
  end
  return out
end

-- Independent reader of this codec's byte format: fifteen byte strings, then
-- the three u16 tail slots on an even offset.
local function read_bytes(data, text, pointers)
  local out, pos = {}, text
  for i = 1, 15 do
    while data:byte(pos + 1) == 0 do pos = pos + 1 end
    local indices = {}
    while true do
      local value = data:byte(pos + 1)
      pos = pos + 1
      if value == 0 then break end
      assert(value <= 127, "glyph does not fit a byte")
      indices[#indices + 1] = value
    end
    out[i] = indices
  end
  if pos % 2 ~= 0 then pos = pos + 1 end
  for k = 1, 3 do
    local indices = {}
    while true do
      local value = u16(data, pos)
      pos = pos + 2
      if value == 0 then break end
      indices[#indices + 1] = value
    end
    out[15 + k] = indices
  end
  return out, pos
end

-- Where each slot begins in a byte-format area: fifteen byte strings, then the
-- three u16 tail slots on an even offset.
local function byte_starts(data, text)
  local starts, pos = {}, text
  for i = 1, 15 do
    while data:byte(pos + 1) == 0 do pos = pos + 1 end
    starts[i] = pos
    while data:byte(pos + 1) ~= 0 do pos = pos + 1 end
    pos = pos + 1
  end
  if pos % 2 ~= 0 then pos = pos + 1 end
  starts[16], starts[17], starts[18] = pos, pos + 4, pos + 8
  return starts, pos
end

-- Where each slot begins in the retail (u16) area, alignment gaps included.
local function slot_starts(data, count, text)
  local starts, pos = {}, text
  for i = 1, count do
    while u16(data, pos) == 0 do pos = pos + 2 end
    starts[i] = pos
    while u16(data, pos) ~= 0 do pos = pos + 2 end
    pos = pos + 2
  end
  return starts
end

local function mapped_slots(data, starts_of, base, count)
  local offsets = {}
  for i, start in ipairs(starts_of) do offsets[start] = i end
  local out = {}
  for i = 0, count - 1 do
    out[i + 1] = offsets[u32(data, base + i * 4) - RAM_BASE]
  end
  return out
end

-- The artifact is a list of "<slot> <glyph>..." lines with '#' comments.
local function read_artifact(text)
  local out, seen = {}, {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local body = line:gsub("#.*$", "")
    local tokens = {}
    for token in body:gmatch("%S+") do tokens[#tokens + 1] = token end
    if #tokens > 0 then
      local slot = tonumber(tokens[1])
      local indices = {}
      for k = 2, #tokens do indices[#indices + 1] = tonumber(tokens[k]) end
      assert(not seen[slot], "duplicate slot in the artifact")
      seen[slot] = true
      out[slot] = indices
    end
  end
  return out
end

-- Labels: composed from the retail sheet exactly as the graphics codec shows
-- them, plus flat synthetic strips for edits.
local icatall = assets.read("SakTaiCD1_Track1.bin/SAKURA1/ICATALL.DAT")
local font = prs:decode(icatall:sub(0x13800 + 1, 0x13800 + 2522))[1].data

local function compose(indices)
  local rows = {}
  for row = 0, 15 do
    local parts = {}
    for cell, glyph in ipairs(indices) do
      local at = (glyph - 1) * 128 + row * 8
      parts[cell] = font:sub(at + 1, at + 8)
    end
    rows[row + 1] = table.concat(parts)
  end
  return table.concat(rows)
end

local function strip(bytes)
  local rows = {}
  for row = 0, 15 do
    local parts = {}
    for k, value in ipairs(bytes) do parts[k] = string.char(value):rep(8) end
    rows[row + 1] = table.concat(parts)
  end
  return table.concat(rows), #bytes * 16
end

local function reader(strips)
  return function(index) return strips[index] end
end

print("test_status_screen_metadata.lua")

local strings = read_strings(sakura, TEXT, POINTERS)

--------------------------------------------------------------------- layout --
check("SAKURA size", #sakura == 391712, tostring(#sakura))
check("18 strings", #strings == 18, tostring(#strings))
check("the strings fill the area exactly",
  slot_starts(sakura, 18, TEXT)[18] + 2 * (#strings[18] + 1) == POINTERS,
  tostring(slot_starts(sakura, 18, TEXT)[18]))
check("every glyph is 1 .. 48", (function()
  for _, indices in ipairs(strings) do
    for _, glyph in ipairs(indices) do
      if glyph < 1 or glyph > 48 then return false end
    end
  end
  return true
end)())
check("slot 1 is three glyphs", #strings[1] == 3, tostring(#strings[1]))
check("slot 16 is one glyph", #strings[16] == 1, tostring(#strings[16]))
check("slot 18 is ten glyphs", #strings[18] == 10, tostring(#strings[18]))
check("the fifteen labels use 40 glyphs", (function()
  local total = 0
  for i = 1, 15 do total = total + #strings[i] end
  return total == 40
end)())

do
  local pointer_slots = mapped_slots(sakura, slot_starts(sakura, 18, TEXT), POINTERS, 12)
  check("the twelve pointers address slots in the retail order",
    table.concat(pointer_slots, ",") == "1,5,6,3,2,4,7,8,9,10,11,12",
    table.concat(pointer_slots, ","))
  check("no twelve-pointer entry addresses a slot past 12", (function()
    for _, slot in ipairs(pointer_slots) do
      if slot > 12 then return false end
    end
    return true
  end)())
  check("the stats pointers address slots 13, 14, 15",
    table.concat(mapped_slots(sakura, slot_starts(sakura, 18, TEXT), STATS, 3), ",")
    == "13,14,15")
end

check("pointer 1 addresses the area's first byte",
  u32(sakura, POINTERS) == RAM_BASE + TEXT,
  string.format("0x%08X", u32(sakura, POINTERS)))

------------------------------------------------------------------ detection --
check("can_handle real SAKURA", codec.can_handle(sakura) == "certain",
  codec.can_handle(sakura))
check("can_handle rejects non-strings", codec.can_handle(nil) == "no")
check("can_handle rejects random data",
  codec.can_handle(string.rep("\xA5", 391712)) == "no")
check("decode_name default", codec.decode_name(nil) == "STATUS")
check("decode_name strips trailing slashes", codec.decode_name("A/B//") == "A/B")

check("retail is the two-byte format", codec._format_of(sakura).kind == "u16"
  and codec._format_of(sakura).text:find("retail") ~= nil,
  codec._format_of(sakura).text)

--------------------------------------------------------------------- decode --
local arts = codec.decode(sakura, nil)
check("one text artifact", #arts == 1, tostring(#arts))
check("artifact name", arts[1].name == NAME, arts[1].name)
check("the artifact names the disc and offset",
  arts[1].data:find("# Sakura Taisen status screen strings .* disc 1, 0x05F428") ~= nil,
  arts[1].data:sub(1, 60))
check("the artifact names the format",
  arts[1].data:find("# format: two%-byte glyphs %(retail%)") ~= nil,
  arts[1].data:sub(1, 120))
check("the artifact names the pointer order it found",
  arts[1].data:find("# 12%-pointer table %-> slots 1, 5, 6, 3, 2, 4, 7, 8, 9, 10, 11, 12") ~= nil)
check("the artifact names the stats slots",
  arts[1].data:find("# stats pointers   %-> slots 13, 14, 15") ~= nil)
check("the artifact describes the tail slots",
  arts[1].data:find("Slots 16 %.%. 18 are the formatter's padding glyph") ~= nil)
check("the artifact says it is not an input",
  arts[1].data:find("editing this file changes nothing") ~= nil)

local decoded = read_artifact(arts[1].data)
check("the artifact holds every slot", #decoded == 18, tostring(#decoded))
do
  local same = true
  for i, indices in ipairs(strings) do
    if #decoded[i] ~= #indices then same = false end
    for k, glyph in ipairs(indices) do
      if decoded[i][k] ~= glyph then same = false end
    end
  end
  check("the artifact matches the retail table", same)
end

------------------------------------------------------------- unchanged travel --
-- The tests stay hermetic: encode looks the ICATALL canvases up under its
-- prefix, so a prefix no node declares has nothing to rebuild from.
local NO_NODE = { prefix = "NO_SUCH_NODE" }
check("encode without canvases is byte-identical", codec.encode(sakura, arts, NO_NODE) == sakura)
check("encode without artifacts is byte-identical", codec.encode(sakura, {}, NO_NODE) == sakura)
check("encode with a nil artifact list", codec.encode(sakura, nil, NO_NODE) == sakura)

-------------------------------------------------------------------- the atlas --
-- Synthetic, short labels: twelve one-cell rows and three two-cell stats rows.
-- The atlas numbers them in slot order, then appends the tail the stats
-- formatter needs -- tile 37's cell (padding), tile 38's (separator) and the
-- ten digits.
local retail_strips = {}
for i = 1, 12 do
  retail_strips[i] = { pixels = compose({ i }), width = 16 }
end
for i = 13, 15 do
  retail_strips[i] = { pixels = compose({ 1, 1 }), width = 32 }
end
local function retail_reader() return reader(retail_strips) end

local renumbered = codec.patch_strings(sakura, retail_reader(), nil)
local full = codec.patch_formatter(renumbered)
check("a rebuild keeps the file size", #renumbered == #sakura, tostring(#renumbered))

local rebuilt, rebuilt_end = read_bytes(renumbered, TEXT, POINTERS)
check("a rebuild leaves eighteen slots", #rebuilt == 18, tostring(#rebuilt))
check("a rebuild numbers the labels in slot order",
  table.concat(rebuilt[1], ",") == "1"
  and table.concat(rebuilt[2], ",") == "2"
  and table.concat(rebuilt[12], ",") == "12")
check("a stats label keeps its two glyphs",
  table.concat(rebuilt[13], ",") == "1,1", table.concat(rebuilt[13], ","))
check("the padding and separator follow the labels",
  table.concat(rebuilt[16], ",") == "13"
  and table.concat(rebuilt[17], ",") == "14")
check("the digits follow the separator",
  table.concat(rebuilt[18], ",") == "15,16,17,18,19,20,21,22,23,24",
  table.concat(rebuilt[18], ","))

do
  -- Twelve two-byte labels (glyph + terminator), three three-byte stats
  -- strings whose `mov.w` start is even, then the 30-byte u16 tail.
  local starts, tail = byte_starts(renumbered, TEXT)
  check("the rebuild uses 66 of the 140 bytes", rebuilt_end - TEXT == 66,
    tostring(rebuilt_end - TEXT))
  check("the rest of the area is zeroed",
    renumbered:sub(rebuilt_end + 1, POINTERS) == string.rep("\0", ROOM - 66))
  check("every stats string starts on an even offset",
    starts[13] % 2 == 0 and starts[14] % 2 == 0 and starts[15] % 2 == 0,
    string.format("%d %d %d", starts[13], starts[14], starts[15]))
  check("the tail starts on an even offset", tail % 2 == 0, tostring(tail))
  check("the labels end where the tail begins",
    starts[16] == tail and rebuilt_end == tail + TAIL_BYTES)

  check("every pointer follows the new layout",
    table.concat(mapped_slots(renumbered, starts, POINTERS, 12), ",")
    == "1,5,6,3,2,4,7,8,9,10,11,12")
  check("every stats pointer follows the new layout",
    table.concat(mapped_slots(renumbered, starts, STATS, 3), ",") == "13,14,15")
  check("pointer 1 still addresses the area's first byte",
    u32(renumbered, POINTERS) == RAM_BASE + TEXT,
    string.format("0x%08X", u32(renumbered, POINTERS)))
  check("the formatter's pool addresses the padding and the digits",
    u32(renumbered, POOL_PAD) == RAM_BASE + starts[16]
    and u32(renumbered, POOL_DIGITS) == RAM_BASE + starts[18])
  -- Twelve distinct label cells, then pad, separator, ten digits and the empty
  -- cell the line fill points at: glyph 25, `mov #25,r2`.
  check("the formatter's line fill points at the blank tail cell",
    u16(renumbered, 0x3E3AE) == 0xE219,
    string.format("0x%04X", u16(renumbered, 0x3E3AE)))
  check("a label is one byte per glyph",
    renumbered:byte(TEXT + 1) == 1 and renumbered:byte(TEXT + 2) == 0
    and renumbered:byte(TEXT + 3) == 2 and renumbered:byte(TEXT + 4) == 0)
  check("nothing outside the strings, tables, pool and fill changed",
    renumbered:sub(1, 0x3E3AE) == sakura:sub(1, 0x3E3AE)
    and renumbered:sub(0x3E3B1, STATS) == sakura:sub(0x3E3B1, STATS)
    and renumbered:sub(0x3E465, 0x3E468) == sakura:sub(0x3E465, 0x3E468)
    and renumbered:sub(0x3E470 + 1, TEXT) == sakura:sub(0x3E470 + 1, TEXT)
    and renumbered:sub(POINTERS + 49) == sakura:sub(POINTERS + 49))
end

check("the byte area and the patched formatter agree", codec._format_of(full).kind == "u8"
  and codec._format_of(full).text:find("one byte per glyph") ~= nil,
  codec._format_of(full).text)
check("a rebuilt file reads back as one byte per glyph",
  (function()
    local back = read_artifact(codec.decode(full, nil)[1].data)
    for i = 1, 18 do
      if table.concat(back[i], ",") ~= table.concat(rebuilt[i], ",") then return false end
    end
    return true
  end)())
check("a rebuilt file re-encodes stably",
  codec.patch_strings(full, retail_reader(), nil) == full
  and codec.patch_formatter(full) == full)

------------------------------------------------------------------ label edits --
do
  local strips = {}
  for i = 1, 15 do strips[i] = retail_strips[i] end
  local pixels, width = strip({ 0x21, 0x22 })
  strips[1] = { pixels = pixels, width = width }

  local out = codec.patch_strings(sakura, reader(strips), nil)
  local back = read_bytes(out, TEXT, POINTERS)

  check("a widened label keeps the file size", #out == #sakura)
  check("a widened label keeps eighteen slots", #back == 18, tostring(#back))
  check("a widened label is written as two bytes",
    table.concat(back[1], ",") == "1,2" and out:byte(TEXT + 3) == 0,
    table.concat(back[1], ","))
  check("the label after it follows the atlas",
    table.concat(back[2], ",") == "3", table.concat(back[2], ","))
  check("a widened label re-encodes stably",
    codec.patch_strings(codec.patch_formatter(out), reader(strips), nil)
    == codec.patch_formatter(out))
end

-- The byte format spends one byte per glyph, so text that was over the u16
-- budget fits: six cells on each of the twelve panel labels is 84 bytes plus
-- terminators, well inside the 110 available.
do
  local strips = {}
  local pixels, width = strip({ 0x31, 0x32, 0x33, 0x34, 0x35, 0x36 })
  for i = 1, 15 do strips[i] = retail_strips[i] end
  for i = 1, 12 do strips[i] = { pixels = pixels, width = width } end

  local out = codec.patch_strings(sakura, reader(strips), nil)
  local back, ends = read_bytes(out, TEXT, POINTERS)
  check("seventy-two panel glyphs fit the area", #back[1] == 6
    and table.concat(back[12], ",") == "1,2,3,4,5,6", tostring(#back[1]))
  check("that layout is inside 140 bytes", ends - TEXT <= ROOM,
    tostring(ends - TEXT))
end

------------------------------------------------------------------- rejection --
check_error("a one-cell stats label is refused", function()
  local strips = {}
  for i = 1, 15 do strips[i] = retail_strips[i] end
  strips[13] = { pixels = compose({ 1 }), width = 16 }
  codec.patch_strings(sakura, reader(strips), nil)
end, "exactly two cells")

check_error("a three-cell stats label is refused", function()
  local strips = {}
  for i = 1, 15 do strips[i] = retail_strips[i] end
  strips[14] = { pixels = compose({ 1, 2, 3 }), width = 48 }
  codec.patch_strings(sakura, reader(strips), nil)
end, "exactly two cells")

check_error("a missing label is refused", function()
  local strips = {}
  for i = 1, 15 do strips[i] = retail_strips[i] end
  strips[3] = nil
  codec.patch_strings(sakura, reader(strips), nil)
end, "label 3 is missing")

check_error("labels longer than the area are refused", function()
  local strips = {}
  local pixels, width = strip({ 1, 2, 3, 4, 5, 6, 7, 8, 9 })
  for i = 1, 15 do strips[i] = retail_strips[i] end
  for i = 1, 12 do strips[i] = { pixels = pixels, width = width } end
  codec.patch_strings(sakura, reader(strips), nil)
end, "too many")

check_error("an unknown file size is refused", function()
  codec.decode(string.rep("\0", 1000), nil)
end, "not a retail SAKURA")

------------------------------------------------------------------- the patch --
-- The byte format turns the drawer's glyph load and every formatter buffer
-- access into byte accesses, and reverts the English build's four longword
-- words because a byte buffer carries both glyphs in one word already.
local BYTE_WORDS = {
  { 0x3E3B0, 0x2620 }, { 0x3E3B4, 0x7101 }, { 0x3E3B6, 0x2120 },
  { 0x3E3BA, 0x7102 }, { 0x3E3BC, 0x2120 }, { 0x3E3C0, 0x7103 },
  { 0x3E3C2, 0x2120 }, { 0x3E3C6, 0x7204 }, { 0x3E3D0, 0x2210 },
  { 0x3E3F2, 0x6111 }, { 0x3E3F8, 0x6111 }, { 0x3E3FC, 0x6111 },
  { 0x3E3FE, 0x2611 }, { 0x3E414, 0x7203 }, { 0x3E434, 0x2210 },
  { 0x3E43C, 0x7602 }, { 0x3E446, 0x7202 }, { 0x3E448, 0x2210 },
  { 0x3E44E, 0x7601 }, { 0x3E450, 0x2610 }, { DRAWER, 0x6384 },
}

local patched = codec.patch_formatter(sakura)
check("the formatter is patched in place", #patched == #sakura)
check("the retail drawer walks words and the byte patch walks bytes",
  u16(sakura, DRAWER) == 0x6385 and u16(patched, DRAWER) == 0x6384,
  string.format("0x%04X -> 0x%04X", u16(sakura, DRAWER), u16(patched, DRAWER)))
check("the store becomes a byte store",
  u16(sakura, 0x3E3B0) == 0x2621 and u16(patched, 0x3E3B0) == 0x2620)
check("the line offsets halve",
  u16(patched, 0x3E3B4) == 0x7101 and u16(patched, 0x3E3C6) == 0x7204
  and u16(patched, 0x3E43C) == 0x7602 and u16(patched, 0x3E44E) == 0x7601)
check("the stats read keeps the retail word instructions",
  u16(patched, 0x3E3F2) == 0x6111 and u16(patched, 0x3E3F8) == 0x6111
  and u16(patched, 0x3E3FC) == 0x6111 and u16(patched, 0x3E3FE) == 0x2611)
check("the patch changes only the words it owns", (function()
  local function put(data, at, bytes)
    return data:sub(1, at) .. bytes .. data:sub(at + #bytes + 1)
  end
  local want = sakura
  for _, entry in ipairs(BYTE_WORDS) do
    want = put(want, entry[1], string.pack(">I2", entry[2]))
  end
  return want == patched
end)())
check("the patch is idempotent", codec.patch_formatter(patched) == patched)

-- An English build's longwords are undone by the byte patch.
do
  local english = sakura
  for at, word in pairs({ [0x3E3F2] = 0x6112, [0x3E3F8] = 0x6112,
                          [0x3E3FC] = 0x6112, [0x3E3FE] = 0x2612 }) do
    english = english:sub(1, at) .. string.pack(">I2", word) .. english:sub(at + 3)
  end
  check("the English format is recognised as two-byte",
    codec._format_of(english).text:find("English") ~= nil,
    codec._format_of(english).text)
  check("the byte patch reverts the English longwords",
    codec.patch_formatter(english) == patched)
  check("a mixed format is refused", (function()
    local ok = pcall(codec._format_of, patched)
    local mixed = patched:sub(1, DRAWER) .. "\x63\x85" .. patched:sub(DRAWER + 3)
    return ok and not pcall(codec._format_of, mixed)
  end)())
end

---------------------------------------------------------------------- disc 2 --
-- Disc 2 keeps the same area and tables, moved by +0x138 past 0x52E00 and
-- +0x18 for the stats pointers, the formatter and the drawer below it.  The
-- addresses *inside* the tables point into the area, so their values gain
-- 0x138 as well.
local function place(fake, offset, source)
  return fake:sub(1, offset) .. source .. fake:sub(offset + #source + 1)
end

local pointer_bytes = {}
for i = 0, 11 do
  pointer_bytes[i + 1] = string.pack(">I4", u32(sakura, POINTERS + i * 4) + 0x138)
end
local stats_bytes = {}
for i = 0, 2 do
  stats_bytes[i + 1] = string.pack(">I4", u32(sakura, STATS + i * 4) + 0x138)
end
local pool_digits = string.pack(">I4",
  u32(sakura, POOL_DIGITS) + 0x138)
local pool_pad = string.pack(">I4",
  u32(sakura, POOL_PAD) + 0x138)

local fake_disc2 = string.rep("\0", CD2_BYTES)
fake_disc2 = place(fake_disc2, 0x3E3A4 + 0x18, sakura:sub(0x3E3A4 + 1, 0x3E700))
fake_disc2 = place(fake_disc2, 0x5F560, sakura:sub(TEXT + 1, POINTERS))
fake_disc2 = place(fake_disc2, POINTERS + 0x138, table.concat(pointer_bytes))
fake_disc2 = place(fake_disc2, 0x3E470, table.concat(stats_bytes))
fake_disc2 = place(fake_disc2, POOL_DIGITS + 0x18, pool_digits)
fake_disc2 = place(fake_disc2, POOL_PAD + 0x18, pool_pad)

check("a synthetic disc-2 input is rejected by can_handle",
  codec.can_handle(fake_disc2) == "no", codec.can_handle(fake_disc2))
check("disc 2 decodes the same strings", (function()
  local disc2 = read_artifact(codec.decode(fake_disc2, nil)[1].data)
  for i = 1, 18 do
    if table.concat(disc2[i], ",") ~= table.concat(strings[i], ",") then return false end
  end
  return true
end)())
check("disc 2 says so in its artifact",
  codec.decode(fake_disc2, nil)[1].data:find("disc 2, 0x05F560") ~= nil)

do
  local out = codec.patch_strings(fake_disc2, retail_reader(), nil)
  local back, ends = read_bytes(out, 0x5F560, 0x5F5EC)
  local starts, tail = byte_starts(out, 0x5F560)
  check("disc 2's labels end where its tail begins", starts[16] == tail
    and ends == tail + TAIL_BYTES, tostring(ends))

  check("disc 2 keeps its size", #out == CD2_BYTES, tostring(#out))
  check("disc 2 writes its own strings", #back == 18, tostring(#back))
  check("disc 2 writes one byte per glyph",
    table.concat(back[1], ",") == "1" and out:byte(0x5F560 + 1) == 1,
    table.concat(back[1], ","))
  check("disc 2 keeps its first pointer",
    u32(out, POINTERS + 0x138) == RAM_BASE + 0x5F560,
    string.format("0x%08X", u32(out, POINTERS + 0x138)))
  check("disc 2 maps its pointers",
    table.concat(mapped_slots(out, starts, POINTERS + 0x138, 12), ",")
    == "1,5,6,3,2,4,7,8,9,10,11,12")
  check("disc 2 maps its stats pointers",
    table.concat(mapped_slots(out, starts, 0x3E470, 3), ",") == "13,14,15")
  check("disc 2's pool addresses its own tail",
    u32(out, POOL_PAD + 0x18) == RAM_BASE + tail
    and u32(out, POOL_DIGITS + 0x18) == RAM_BASE + tail + 8)
  check("disc 2 leaves the disc-1 area untouched",
    out:sub(TEXT + 1, 0x5F560) == fake_disc2:sub(TEXT + 1, 0x5F560))
  check("disc 2 re-encodes stably", (function()
    local done = codec.patch_formatter(out)
    return codec.patch_strings(done, retail_reader(), nil) == done
  end)())
  local once = codec.patch_formatter(out)
  check("disc 2's formatter and drawer move by 0x18",
    u16(once, DRAWER + 0x18) == 0x6384
    and u16(once, 0x3E3B0 + 0x18) == 0x2620
    and u16(once, 0x3E3F2 + 0x18) == 0x6111)
  check("disc 2's patch writes only its shifted words", (function()
    local want = out
    for _, entry in ipairs(BYTE_WORDS) do
      local at = entry[1] + 0x18
      want = want:sub(1, at) .. string.pack(">I2", entry[2]) .. want:sub(at + 3)
    end
    return once == want
  end)())
end

print(string.format("%d passed, %d failed", pass, fail))
assert(fail == 0)
