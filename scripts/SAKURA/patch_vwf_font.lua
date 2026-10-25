--[[
  Sakura Taisen (Saturn) — variable-width glyph layout for the ADV engine.

  Standalone Lua codec for Ludared.  No external dependencies.

  WHAT IT CHANGES
  ---------------
  patch_8px_font.lua steps the text cursor a fixed 8 px per glyph.  This codec
  replaces that fixed step with a *per-glyph* advance carried inside the string
  itself, and stops the layout routines (line origin, centring) from assuming a
  fixed 16 px cell.

  The string ABI is unchanged: every glyph is still one big-endian u16, so the
  existing 2-byte stride and the existing containers stay as they are.  What
  changes is what the u16 *means*:

      packed_word = (glyph_id << 8) | advance

      byte 1 (high)  glyph id, 1..255        (0 is the reserved control byte)
      byte 2 (low)   advance in pixels, 1..N (the width column of the font
                                              table, see I18N_FONT.tbl)

  Two control words keep their old meaning by construction: 0x0000 is the string
  terminator and 0x000D is the newline.  A real glyph always has a non-zero id,
  so a packed word for a glyph is at least 0x0100 and can never collide with a
  control word in 0x0000..0x00FF.

  WHY BYTE-SPLIT
  --------------
  The earlier nibble packing — (id << 4) | (advance - 1) — forced every caller
  to unpack the advance with a mask-and-increment sequence (mov/and/add) plus a
  push of the glyph id across the draw call, and needed extra frame slots in the
  layout routine.  Splitting the two fields on byte boundaries instead makes the
  decode a single instruction each way:

      GLYPH     shlr8 r6        -> id   = packed >> 8
      caller    extu.b r6,r0    -> advance = packed & 0xFF

  so the id survives in r6 untouched for GLYPH and each caller extracts the
  advance *before* the call and adds it to its own cursor.  That fits the
  existing draw blocks byte for byte with no code cave, no register spills and
  no frame growth: every write below overwrites an instruction in place.

  THE SITES
  ---------
    GLYPH                 0x01036C                packed >> 8
    fnA  (dialogue text)  0x0104DE..0x0104E6     latch X, advance, call
                          0x010510                newline literal
    fnB  (choice/LIPS)    pass 1 0x0105B2..C4    accumulate advance per line
                          origins 0x01060E/0x010642  X = 8 - width/2
                          pass 2 0x010664..0x01066C
                          0x0106A4                newline literal
    fnC  (secondary text) 0x010740..0x010748     latch X, advance, call
                          0x01076C                newline literal
    newline sentinels     0x010B12, 0x010BF4     interpreter-side tests (splitter
                                                  + line counter), same word

  fnA and fnC keep their original shape: the only edited instructions are the
  four-slot tail `mov r8,rX / add #0x10,rX / exts.w rX,r8` which becomes
  `mov r8,r4 / extu.b r6,r0 / jsr / add r0,r8`.  fnB pass 1 used to count
  characters; it now adds the glyph's advance to the line's running width, and
  both origin computations become 8 - width/2 so centring is preserved for
  variable-width lines (the original 8 - 8*count is the special case width =
  16*count).

  The line pitch (0x0104D7, 0x010733) and the choice-menu start rows
  (0x0105FB, 0x010603) are the same 8x12 layout constants patch_8px_font.lua
  writes; they are repeated here so this codec is a complete ADV layout on its
  own.  patch_8px_font.lua writes the fixed 8 px *advance* bytes at 0x0104E5,
  0x01066B and 0x010747, which this codec overwrites whole — the 8 px layout
  and this VWF layout are two alternatives for the same engine, not a stack.
  Do not apply both.

  LIMITS / TODO
  -------------
  scripts/dialogues.lua emits (id << 8) | width and the newline 0x000D when
  ACTIVATE_VWF is enabled.  This codec only rewrites the executable.

  The parallel SLG engine (SLG.BIN) is untouched: its advance lives in three
  post-call `add #0x10` sites whose surrounding slots have not been verified.

  IDENTIFICATION
  --------------
  As with every codec here, identification is the byte values at the sites
  alone: no file name, no size, no container knowledge.  A file is this codec's
  business when every site reads either its pristine or its patched value; the
  SLG executable matches none of them and is refused.

  PATCH CODEC SHAPE
  -----------------
  `decode` emits no artifacts; `encode(original, decode(original))` is the
  patched file.  Re-running is safe (a patched site is left alone); any third
  value at a site is a hard error naming the offset.
]]

local codec = {}

codec.name        = "Sakura Taisen VWF Layout (ADV)"
codec.description = "Patches the Sakura Taisen (Saturn) ADV engine so each "
                 .. "glyph advances by the width carried in its packed word "
                 .. "(id<<8)|advance, with line origin and centring computed "
                 .. "from variable widths. Emits no artifacts."
codec.version     = 1
codec.kind        = "patch"

local LABEL = "VWF layout (ADV)"

-- ---------------------------------------------------------------------------
-- The write list.  { file offset, pristine, patched, what }, values as hex.
-- ---------------------------------------------------------------------------

local SITES = {
  -- Layout constants shared with the 8x12 build (see the header note).
  { 0x0104D7, "10", "0C", "line pitch, dialogue text" },
  { 0x0105FB, "CC", "CE", "choice menu start row, two-option list" },
  { 0x010603, "C4", "C6", "choice menu start row, three-option list" },
  { 0x010733, "10", "0C", "line pitch, secondary text renderer" },

  -- GLYPH: the packed word arrives with the id in the high byte.  The dead
  -- extu.w r6,r6 becomes shlr8 r6; everything after (add #-1, *128, +base) is
  -- the untouched original.  The second dead instruction, extu.w r7,r7, is
  -- harmless and left as-is.
  { 0x01036C, "666D", "4619", "GLYPH: r6 = packed >> 8 (glyph id)" },

  -- fnA, dialogue text: latch X, extract the advance, add it, then call.
  { 0x0104DE, "4D0B", "6483", "fnA: r4 = X (latch before advancing)" },
  { 0x0104E0, "6483", "606C", "fnA: r0 = packed & 0xFF (advance)" },
  { 0x0104E2, "6183", "4D0B", "fnA: call GLYPH" },
  { 0x0104E4, "7110", "380C", "fnA: r8 = X + advance (delay slot)" },
  { 0x0104E6, "681F", "0009", "fnA: nop" },
  { 0x010510, "0A0D", "000D", "fnA: newline literal -> 0x000D" },

  -- fnC, count-limited renderer: X is r8; r9 is the character index.  Advancing
  -- r9 here skips glyphs and can miss the index == count exit test at 0x010750.
  { 0x010740, "420B", "6483", "fnC: r4 = X (latch before advancing)" },
  { 0x010742, "6483", "606C", "fnC: r0 = packed & 0xFF (advance)" },
  { 0x010744, "6183", "420B", "fnC: call GLYPH (via r2)" },
  { 0x010746, "7110", "380C", "fnC: r8 = X + advance (delay slot)" },
  { 0x010748, "681F", "0009", "fnC: nop" },
  { 0x01076C, "0A0D", "000D", "fnC: newline literal -> 0x000D" },

  -- fnB, choice/LIPS text.  Pass 1 no longer counts characters: it adds each
  -- glyph's advance into the per-line width counters at [r14+0,2,4,6].  The
  -- newline branch skips the accumulation and lands on the index increment.
  { 0x0105B2, "A005", "A006", "fnB pass 1: newline skips the accumulation" },
  { 0x0105B6, "322C", "601C", "fnB pass 1: r0 = packed & 0xFF (advance)" },
  { 0x0105B8, "32EC", "322C", "fnB pass 1: r2 = line * 2" },
  { 0x0105BA, "6121", "32EC", "fnB pass 1: r2 = frame + line * 2" },
  { 0x0105BC, "7101", "6121", "fnB pass 1: r1 = counter[line]" },
  { 0x0105BE, "2211", "310C", "fnB pass 1: counter += advance" },
  { 0x0105C0, "6183", "2211", "fnB pass 1: store counter[line]" },
  { 0x0105C2, "7101", "7801", "fnB pass 1: index++" },
  { 0x0105C4, "681F", "0009", "fnB pass 1: nop" },

  -- fnB origins: X = 8 - width/2 (shlr, neg, add #8).  Two slots freed per
  -- block compared with the original 8 - 8*count sequence.
  { 0x01060E, "611D", "4101", "fnB origin (first line): width / 2" },
  { 0x010612, "4108", "7108", "fnB origin (first line): 8 - width/2" },
  { 0x010614, "311C", "0009", "fnB origin (first line): nop" },
  { 0x010616, "7108", "0009", "fnB origin (first line): nop" },
  { 0x010642, "611D", "4101", "fnB origin (after newline): width / 2" },
  { 0x010646, "4108", "7108", "fnB origin (after newline): 8 - width/2" },
  { 0x010648, "311C", "0009", "fnB origin (after newline): nop" },
  { 0x01064A, "7108", "0009", "fnB origin (after newline): nop" },

  -- fnB pass 2 draw path: latch X, extract the advance, add it, then call.
  { 0x010664, "4D0B", "6493", "fnB pass 2: r4 = X (latch before advancing)" },
  { 0x010666, "6493", "606C", "fnB pass 2: r0 = packed & 0xFF (advance)" },
  { 0x010668, "6193", "4D0B", "fnB pass 2: call GLYPH" },
  { 0x01066A, "7110", "390C", "fnB pass 2: r9 = X + advance (delay slot)" },
  { 0x01066C, "691F", "0009", "fnB pass 2: nop" },
  { 0x0106A4, "0A0D", "000D", "fnB: newline literal -> 0x000D" },

  -- The ADV script/message interpreter tests the newline word in two more
  -- places, outside the three drawing routines: the per-character line splitter
  -- that builds the current line buffer (0x010A66) and the line counter that
  -- sizes the box (0x010BBE).  Both load this literal and compare, so they must
  -- move to 0x000D with the rest or they never see a line break.
  { 0x010B12, "0A0D", "000D", "message splitter: newline literal -> 0x000D" },
  { 0x010BF4, "0A0D", "000D", "line counter: newline literal -> 0x000D" },
}

-- ---------------------------------------------------------------------------
-- Site machinery
-- ---------------------------------------------------------------------------

local function fromhex(s)
  return (s:gsub("%x%x", function(b) return string.char(tonumber(b, 16)) end))
end

for _, site in ipairs(SITES) do
  if type(site[2]) == "number" then site[2] = string.char(site[2]) else site[2] = fromhex(site[2]) end
  if type(site[3]) == "number" then site[3] = string.char(site[3]) else site[3] = fromhex(site[3]) end
end

local function hex(data)
  local out = {}
  for i = 1, #data do out[i] = string.format("%02x", data:byte(i)) end
  return table.concat(out)
end

-- "patched", "pristine" or nil when the site holds a value this codec does not
-- know.
local function site_state(data, site)
  local current = data:sub(site[1] + 1, site[1] + #site[2])
  if current == site[3] then return "patched" end
  if current == site[2] then return "pristine" end
  return nil
end

-- A few lines naming what was expected, for the failure message.
local function report(data, sites)
  local lines, shown = {}, 0
  for _, site in ipairs(sites) do
    if not site_state(data, site) then
      lines[#lines + 1] = string.format("  0x%06X (%s) wants %s or %s, found %s",
        site[1], site[4], hex(site[2]), hex(site[3]),
        hex(data:sub(site[1] + 1, site[1] + #site[2])))
      shown = shown + 1
      if shown == 3 then break end
    end
  end
  return table.concat(lines, "\n")
end

-- Returns the site list, how many of its sites read a value this codec knows,
-- and a one-line summary.  score == 0 means nothing here is this codec's
-- business, and the site list is nil.
local function detect(data)
  local score = 0
  for _, site in ipairs(SITES) do
    if site_state(data, site) then score = score + 1 end
  end
  if score == 0 then return nil, 0, "0 of " .. #SITES .. " sites match" end
  return SITES, score, score .. " of " .. #SITES .. " sites match"
end

-- Applies every site.  A site already holding its patched value is skipped,
-- which is what makes repeated runs idempotent.  Any other value is an error.
local function apply(data, sites, stage)
  local out = data
  for _, site in ipairs(sites) do
    local offset, pristine, patched, what = site[1], site[2], site[3], site[4]
    local current = out:sub(offset + 1, offset + #pristine)

    if current == patched then
      -- Already applied.
    elseif current == pristine then
      out = out:sub(1, offset) .. patched .. out:sub(offset + #pristine + 1)
    else
      error(string.format(
        "%s: %s: 0x%06X (%s) holds %s; expected %s (pristine) or %s (patched)",
        LABEL, stage, offset, what, hex(current), hex(pristine), hex(patched)), 0)
    end
  end
  return out
end

local function fail(stage, data, sites, detail)
  error(string.format("%s: %s: nothing to patch here (%s)\n%s",
    LABEL, stage, detail, report(data, sites or SITES)), 0)
end

-- The codec takes no arguments; anything else is a manifest mistake.
local function check_args(args)
  if args ~= nil and args ~= "" then
    error(LABEL .. ": this codec takes no arguments, got '" .. tostring(args) .. "'", 0)
  end
end

-- ---------------------------------------------------------------------------
-- Codec
-- ---------------------------------------------------------------------------

function codec.can_handle(data)
  if type(data) ~= "string" then return "no" end

  local _, score = detect(data)
  if score == 0 then return "no" end
  if score == #SITES then return "certain" end
  if score * 2 >= #SITES then return "likely" end
  return "possible"
end

function codec.decode_name(args)
  if type(args) == "string" and #args > 0 then return args end
  return "vwf_font"
end

function codec.decode(data, args)
  check_args(args)
  if type(data) ~= "string" then error(LABEL .. ": decode: expected binary string", 0) end

  local sites, _, detail = detect(data)
  if not sites then fail("decode", data, nil, detail) end
  apply(data, sites, "decode")

  return {}
end

function codec.encode(original, artifacts, args)
  check_args(args)
  if type(original) ~= "string" then
    error(LABEL .. ": encode: expected binary string for `original`", 0)
  end

  local sites, _, detail = detect(original)
  if not sites then fail("encode", original, nil, detail) end

  return apply(original, sites, "encode")
end

return codec
