--[[
  Sakura Taisen (Saturn) — Dialogue codec for NNNNTBL.BIN / M##MES.BIN

  Standalone Lua codec for Ludared.  `kind = "patch"`.

  DECODE produces one artifact, <table>.TXT, with explicit, sequential
  1-based dialogue indices (0001:, 0002:, ...). ENCODE accepts blank lines
  and full-line # comments, but dialogue indices must remain in order.
  A newline word inside an entry — 0x0A0D, or 0x000D when ACTIVATE_VWF packs
  the table — becomes the literal text "<br>".

  The artifact is named after the dialogue table it decoded, not after the font
  `args` names: `args = "0100KNJ"` on 0100TBL.BIN yields 0100TBL.TXT.  See
  "Artifact naming" for why the name has to be derived from `args` at all.

  ENCODE rewrites each entry's glyph payload from its TXT line.  Everything that
  is not dialogue text is carried over verbatim from the input buffer:

    * the header string IDs  — never re-derived, never reordered (they are not
      sequential and do not follow the TXT line order: M01MES starts
      186,187,182,183,... and 0100TBL jumps from 0x9C4x to 0xD6Dx);
    * each entry's 4-byte metadata prefix (two u16 BE words);
    * the timing footer, byte for byte.

  Only the glyph payload, the header offset table and the timing offset (which
  depends on the payload size) are rebuilt.

  File format (verified against SakuraTaisen.cpp and against all 69 shipped
  TBL/MES files on disc 1):

      offset 0x00  u16 BE  headerSize/2      header ends at 2*headerSize
      offset 0x02  u16 BE  timingOffset/2    timing footer starts at 2*that
      offset 0x04  N x { u16 BE stringId, u16 BE stringOffset }
                   N = headerSize*2/4 - 1
                   stringOffset is in halfwords, measured from headerSize.

      Each entry occupies [headerSize + 2*stringOffset, next entry's start)
      (the last entry ends at the timing footer) and is:

          4 bytes   prefix    (two u16 BE; per-line metadata, NOT dialogue)
          M x u16 BE glyph codes
          0x0000    terminator

      Glyph code G selects font tile G-1, i.e. the .tbl entry with ID G
      (1-based).  0x0A0D is a newline sentinel, not a glyph.

  The layout is identical for TBL and MES files.  The differences described in
  SAKTAI_ISO_ARCHITECTURE.md §3.2 ("1 byte per glyph", 8-byte header entries,
  synthetic timing) describe the *patched English inserter's* output under
  USE_SINGLE_BYTE_LOOKUPS / USE_4_BYTE_OFFSETS, not the original Japanese files.

  Font tables (`workspace/tables/<font>.tbl`):

      HEX=GLYPH                 glyph width defaults to DEFAULT_GLYPH_WIDTH
      HEX=WIDTH=GLYPH           explicit per-glyph width, in pixels (VWF)

  The width is always used for line breaking.  What is written to the .BIN
  depends on ACTIVATE_VWF.  Off, each glyph stays its plain u16 ID exactly as
  the historical files store it.  On (the default), each glyph becomes the
  packed word (id << 8) | width and the newline becomes 0x000D — the format
  scripts/SAKURA/patch_vwf_font.lua reads back.  The packed form is applied only
  to tables whose font stem names a *patched* engine (VWF_FONT_STEMS): the
  SAKURA (ADV) tables, never the M##MES tables SLG.BIN renders.  Decode is not
  affected: it reads whichever of the two formats the bytes actually are.

  Overridable globals (defined by the host *before* loading this codec, and
  never clobbered here — each uses `X = X or <default>`):

      ENCODE_FONT          font used by encode() to map text back to glyphs
      MAX_LINES            maximum text lines one dialogue may occupy
      LINE_WIDTH_PX        line-break width
      DEFAULT_GLYPH_WIDTH  width for a table entry written as HEX=GLYPH
      ACTIVATE_VWF         write the packed (id << 8) | width format
      VWF_FONT_STEMS       font stems whose engine is VWF-patched

  ACTIVATE_VWF is on by default and applies the packed format only to tables
  whose `args` font stem matches one of VWF_FONT_STEMS.  Turn it on only
  alongside scripts/SAKURA/patch_vwf_font.lua, or an unpatched engine will read
  packed words as glyph IDs.  The stem split is the engine split, not a
  preference: SAKURA (ADV) renders its own NNNNKNJ fonts and
  is the only engine with a VWF patch, while SLG.BIN renders the M##MES tables
  and has none, so those must keep the historical encoding.  A table outside
  VWF_FONT_STEMS is encoded exactly as if ACTIVATE_VWF were off.

  Round-trip status against all 69 disc-1 TBL/MES files: the framing, the string
  IDs, the per-entry prefixes and the timing footer are exact everywhere, and
  the glyph payloads are exact everywhere too, with one caveat.  0904KNJ #221
  (id=0x28AB) centres text on a 16-tile line, "太正七年帝国陸軍" padded with
  U+3000; at the 16px default that line is 256px, over LINE_WIDTH_PX, so the
  encoder re-wraps it.  The original engine evidently measured the full-width
  space as 8px.  Tagging that tile with the HEX=WIDTH=GLYPH form (`00E4=8=　`
  in 0100KNJ; the ID differs per table) makes this entry — and therefore every
  file — bit-exact, which is exactly what the width column is for.  With that
  annotation all 69 files round-trip byte for byte.
]]

-- ---------------------------------------------------------------------------
-- Project layout
--
-- TODO(ludared): Replace this hardcoded project root (and the derived
-- WORKSPACE / SCRIPTS paths) with the runtime-provided global table, i.e.
-- LUDARED.PROJECT_ROOT, LUDARED.WORKSPACE and LUDARED.SCRIPTS.  They are not
-- available in the currently installed ludared build, so the absolute path is
-- pinned here for now.  `args` stays a font identifier; it must never carry a
-- path.
-- ---------------------------------------------------------------------------

local PROJECT_ROOT = "/Users/red/Projects/Hashire/re.sakurataisen"
local WORKSPACE    = PROJECT_ROOT .. "/workspace"
local TABLES_DIR   = WORKSPACE .. "/tables"

-- ---------------------------------------------------------------------------
-- Overridable tuning knobs (globals: `X = X or default`, so a host that sets
-- one before loading the codec keeps it).
-- ---------------------------------------------------------------------------

ENCODE_FONT         = ENCODE_FONT         or "I18N_FONT"
MAX_LINES           = MAX_LINES           or 99
LINE_WIDTH_PX       = LINE_WIDTH_PX       or 240
DEFAULT_GLYPH_WIDTH = DEFAULT_GLYPH_WIDTH or 16

-- Variable-width text.  When true, a dialogue table rendered by a *patched*
-- engine is written with the packed word (id << 8) | advance and the newline
-- 0x000D, i.e. the format scripts/SAKURA/patch_vwf_font.lua reads back.  When
-- false, every table keeps the historical plain-glyph encoding.  decode() is
-- format-agnostic either way (it reads whichever the bytes actually are), so
-- this switch only changes what encode() writes.
--
-- ON by default, because the manifest pairs this codec with the VWF layout
-- (scripts/SAKURA/patch_vwf_font.lua), whose engine reads the packed word.  It
-- must be turned OFF if the 8px layout is installed instead, or the engine will
-- read packed words as plain IDs.  `X = X or true` would be stuck on (`false or
-- true` is `true`), so the default is only applied when the host left the global
-- unset — which keeps an explicit `ACTIVATE_VWF = false` working.
if ACTIVATE_VWF == nil then ACTIVATE_VWF = true end

-- Which tables use the packed format: a table is VWF-encoded only when
-- ACTIVATE_VWF is true *and* its `args` font stem matches one of these Lua
-- patterns.  The split is the engine split.  SAKURA (ADV) renders its own
-- NNNNKNJ fonts and is VWF-patched; SLG.BIN renders the M##MES tables and is
-- not, so those must stay legacy.  Add "^M%d+MES$" here only once SLG.BIN
-- carries the same patch.
VWF_FONT_STEMS = VWF_FONT_STEMS or { "^%d+KNJ$", "^I18N_FONT$" }

-- ---------------------------------------------------------------------------
-- Format constants
-- ---------------------------------------------------------------------------

local NEWLINE_CODE = 0x0A0D   -- SakuraChar::NewLine
local VWF_NEWLINE  = 0x000D   -- newline in the packed (id << 8) | advance form
local TERMINATOR   = 0x0000   -- end of an entry's glyph payload
local PREFIX_BYTES = 4        -- two u16 BE words of per-entry metadata
local NEWLINE_TEXT = "<br>"   -- matches the historical extractor's NewLineWord

-- Does this table use the packed format?  Only when the master switch is on
-- *and* the font stem names a VWF-patched engine, so a table the unpatched SLG
-- engine renders is never packed.
local function uses_vwf(args)
  if not ACTIVATE_VWF then return false end
  for _, pattern in ipairs(VWF_FONT_STEMS) do
    if args:match(pattern) then return true end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- Little helpers
-- ---------------------------------------------------------------------------

-- u16 big-endian at 0-based byte offset `off`.
local function u16be(data, off)
  local hi, lo = data:byte(off + 1, off + 2)
  if not lo then return nil end
  return hi * 256 + lo
end

local function char_u16be(value)
  return string.char(math.floor(value / 256) % 256, value % 256)
end

-- The whole UTF-8 character starting at byte `i` (for error messages).
local function next_char(text, i)
  local b = text:byte(i)
  if not b then return "" end
  local len = 1
  if b >= 0xF0 then len = 4
  elseif b >= 0xE0 then len = 3
  elseif b >= 0xC0 then len = 2 end
  return text:sub(i, i + len - 1)
end

-- ---------------------------------------------------------------------------
-- Font table
--
-- An empty value is meaningful (the glyph renders as nothing) and must stay
-- distinguishable from a missing ID, so the map stores `""` and simply omits
-- unknown IDs.
-- ---------------------------------------------------------------------------

local function load_font_table(font, who)
  local path = TABLES_DIR .. "/" .. font .. ".tbl"
  local fh, openError = io.open(path, "rb")
  if not fh then
    error(who .. ": cannot open font table '" .. path .. "': "
          .. tostring(openError), 0)
  end
  local raw = fh:read("*a")
  fh:close()

  local glyphs, widths = {}, {}
  local count = 0
  for line in raw:gmatch("[^\r\n]+") do
    local key, rest = line:match("^([0-9A-Fa-f]+)=(.*)$")
    if key then
      local width, glyph = rest:match("^(%d+)=(.*)$")
      if width then
        width = tonumber(width)
      else
        glyph = rest
        width = DEFAULT_GLYPH_WIDTH
      end
      local id = tonumber(key, 16)
      glyphs[id] = glyph
      widths[id] = width
      count = count + 1
    elseif line:match("^%s*$") == nil then
      error(who .. ": malformed line in '" .. path .. "': " .. line, 0)
    end
  end
  if count == 0 then
    error(who .. ": font table '" .. path .. "' is empty", 0)
  end
  return { glyphs = glyphs, widths = widths, path = path, count = count }
end

-- ---------------------------------------------------------------------------
-- Binary framing
--
-- Returns the ordered entry list, or `nil, message` when the bytes cannot be a
-- Sakura Taisen TBL/MES table.  Used by `can_handle`, `decode` and `encode`, so
-- the three never disagree about what is well-formed.
-- ---------------------------------------------------------------------------

local function analyze(data)
  if type(data) ~= "string" then
    return nil, "expected a binary string, got " .. type(data)
  end
  if #data < 8 then
    return nil, "file too small (" .. #data .. " bytes)"
  end

  local rawHeader = u16be(data, 0)
  local rawTiming = u16be(data, 2)
  if rawHeader == nil or rawTiming == nil then
    return nil, "truncated header"
  end

  local headerEnd = rawHeader * 2
  local timing    = rawTiming * 2

  if rawHeader % 2 ~= 0 then
    return nil, "header size " .. headerEnd .. " is not a multiple of 4"
  end
  if headerEnd < 8 then
    return nil, "header size " .. headerEnd .. " is too small"
  end
  if timing < headerEnd then
    return nil, "timing offset " .. timing .. " precedes header end " .. headerEnd
  end
  if timing > #data then
    return nil, "timing offset " .. timing .. " is past end of file (" .. #data .. ")"
  end

  local count = headerEnd // 4 - 1
  if count < 1 then
    return nil, "no dialogue entries"
  end

  local entries = {}
  local previousStart = -1
  for i = 0, count - 1 do
    local id  = u16be(data, 4 + i * 4)
    local off = u16be(data, 4 + i * 4 + 2)
    local start = headerEnd + off * 2

    if start < headerEnd then
      return nil, "entry " .. (i + 1) .. " starts before the header"
    end
    if start < previousStart then
      return nil, "entry " .. (i + 1) .. " offsets are not monotonic"
    end
    previousStart = start
    entries[i + 1] = { id = id, start = start, finish = nil }
  end

  for i = 1, count do
    local finish = entries[i + 1] and entries[i + 1].start or timing
    entries[i].finish = finish

    if finish > timing then
      return nil, "entry " .. i .. " runs past the timing footer"
    end
    if finish - entries[i].start < PREFIX_BYTES + 2 then
      return nil, "entry " .. i .. " is too short to hold a prefix and terminator"
    end

    -- Every entry's payload is exactly [start+4, finish-2) with a 0x0000
    -- terminator as its last word.  Verified on all 69 disc-1 TBL/MES files;
    -- anything else (no terminator, bytes after it) is malformed.
    local pos = entries[i].start + PREFIX_BYTES
    local terminated = false
    while pos + 2 <= finish do
      if u16be(data, pos) == TERMINATOR then
        terminated = true
        break
      end
      pos = pos + 2
    end
    if not terminated then
      return nil, "entry " .. i .. " has no 0x0000 terminator"
    end
    if pos + 2 ~= finish then
      return nil, "entry " .. i .. " has " .. (finish - pos - 2)
             .. " byte(s) after its 0x0000 terminator"
    end
  end

  return { entries = entries, headerEnd = headerEnd, timing = timing }
end

-- ---------------------------------------------------------------------------
-- Artifact naming
-- ---------------------------------------------------------------------------

local function check_args(args)
  if type(args) ~= "string" or args == "" then
    error("expected a font identifier as args (e.g. \"0101KNJ\" or \"M01MES\")", 0)
  end
  -- Letters, digits and underscore.  A font identifier doubles as a file stem
  -- (workspace/tables/<args>.tbl), so separators and dots stay banned; the
  -- underscore only keeps names like "I18N_FONT" usable.
  if not args:match("^[%w_]+$") then
    error("invalid font identifier args '" .. args
          .. "' (expected letters, digits and underscores only)", 0)
  end
end

-- The decoded artifact is named after the dialogue table, not after the font.
-- Ludared hands `decode` the bytes and `args` and nothing else -- the virtual
-- path of the artifact being decoded, i.e. the file name, is not passed and no
-- codec can reach it -- so the table's name can only be derived from the font's.
--
-- The derivation is exact for this game: a dialogue bank and its font are named
-- together.  Across the whole of disc 1, all 56 NNNNTBL.BIN tables have a
-- same-stem NNNNKNJ.BIN font and table, and the 13 M##MES.BIN tables share
-- their stem with their M##MES.FNT font already.  Swapping the font suffix
-- therefore lands on the table for both families, and leaves the MES names
-- alone:
--
--     "0100KNJ" -> "0100TBL.TXT"
--     "M01MES"  -> "M01MES.TXT"
local function artifact_name(args)
  -- The parentheses take only the first result; gsub returns the count too.
  return (args:gsub("KNJ$", "TBL")) .. ".TXT"
end

-- ---------------------------------------------------------------------------
-- Text -> glyphs
--
-- The table is matched longest-first because the Japanese tables contain
-- multi-character tiles (0217=マー, 0218=ザー, ...).  Should two tiles ever
-- share the same characters the lowest ID wins, deterministically.  Empty
-- values cannot be matched and are skipped.
-- ---------------------------------------------------------------------------

local function build_reverse(tbl)
  local reverse = {}
  local maxLength = 0
  for id, glyph in pairs(tbl.glyphs) do
    if glyph ~= "" then
      local current = reverse[glyph]
      if current == nil or id < current then
        reverse[glyph] = id
      end
      if #glyph > maxLength then
        maxLength = #glyph
      end
    end
  end
  return reverse, maxLength
end

local function encode_dialogue(line, index, id, reverse, maxLength, tbl, args, vwf)
  local codes = {}
  local lineCount = 1
  local width = 0
  local newlineCode = vwf and VWF_NEWLINE or NEWLINE_CODE

  -- Append one glyph.  Legacy: its plain u16 ID.  VWF: the packed word
  -- (id << 8) | width, which requires both fields to fit in one byte.
  local function emit(glyphId, glyphWidth)
    if not vwf then
      codes[#codes + 1] = glyphId
      return
    end
    if glyphId < 1 or glyphId > 0xFF then
      error(string.format(
        "encode(%s): dialogue #%d (id=0x%04X) uses glyph ID 0x%X, which does "
        .. "not fit the VWF packed word (needs 0x01..0xFF); this font has more "
        .. "than 255 glyphs and cannot use the VWF format",
        args, index, id, glyphId), 0)
    end
    if glyphWidth < 1 or glyphWidth > 0xFF then
      error(string.format(
        "encode(%s): dialogue #%d (id=0x%04X) glyph ID 0x%X has width %d, "
        .. "which does not fit the VWF packed word low byte",
        args, index, id, glyphId, glyphWidth), 0)
    end
    codes[#codes + 1] = glyphId * 256 + glyphWidth
  end

  -- Split on the explicit <br> marker first: it forces a break that the 240px
  -- rule must not remove.
  local segments = {}
  do
    local pos = 1
    while true do
      local at = line:find(NEWLINE_TEXT, pos, true)
      if not at then
        segments[#segments + 1] = line:sub(pos)
        break
      end
      segments[#segments + 1] = line:sub(pos, at - 1)
      pos = at + #NEWLINE_TEXT
    end
  end

  for s = 1, #segments do
    if s > 1 then
      codes[#codes + 1] = newlineCode
      width = 0
      lineCount = lineCount + 1
    end

    local segment = segments[s]
    local i = 1
    local n = #segment
    while i <= n do
      local glyphId, matchedLength
      local limit = math.min(maxLength, n - i + 1)
      for length = limit, 1, -1 do
        local candidateId = reverse[segment:sub(i, i + length - 1)]
        if candidateId then
          glyphId, matchedLength = candidateId, length
          break
        end
      end
      if not glyphId then
        error(string.format(
          "encode(%s): dialogue #%d (id=0x%04X) has no glyph for '%s' at text "
          .. "byte offset %d; not in %s",
          args, index, id, next_char(segment, i), i - 1, tbl.path), 0)
      end

      local glyphWidth = tbl.widths[glyphId] or DEFAULT_GLYPH_WIDTH
      if width > 0 and width + glyphWidth > LINE_WIDTH_PX then
        codes[#codes + 1] = newlineCode
        width = 0
        lineCount = lineCount + 1
      end
      emit(glyphId, glyphWidth)
      width = width + glyphWidth
      i = i + matchedLength
    end
  end

  if lineCount > MAX_LINES then
    error(string.format(
      "encode(%s): dialogue #%d (id=0x%04X) needs %d line(s), over MAX_LINES=%d",
      args, index, id, lineCount, MAX_LINES), 0)
  end

  return codes
end

-- ---------------------------------------------------------------------------
-- Codec
-- ---------------------------------------------------------------------------

local codec = {}

codec.name        = "Sakura Taisen Dialogues"
codec.description = "Decode Sakura Taisen Saturn dialogue tables (NNNNTBL.BIN / " ..
                    "M##MES.BIN) into editable text, one dialogue per line, " ..
                    "using workspace/tables/<font>.tbl. Patch encoder rebuilds " ..
                    "each entry from its line while preserving the original " ..
                    "string IDs, per-entry metadata and timing footer."
codec.version     = 1
codec.kind        = "patch"

-- Both original TBL and MES files share one framing, so this only checks the
-- bytes.  `analyze` runs the whole framing: header alignment and bounds, a
-- strictly increasing offset table, and an exactly-terminated payload for every
-- entry.  Across the 1869 blobs in the disc-1 decode cache exactly 69 pass, and
-- they are precisely the 69 dialogue tables (no false positives, no false
-- negatives), so "all signs point to yes" -- but not "certain": there is no
-- magic number, and `args` (the font whose table would confirm the glyph codes)
-- is not visible to `can_handle`.
function codec.can_handle(data)
  local ok = analyze(data)
  if ok then return "likely" end
  return "no"
end

function codec.decode_name(args)
  check_args(args)
  return artifact_name(args)
end

-- Read every entry under one format.  Returns the line table, or nil plus a
-- message when the bytes do not fit that format (an unknown glyph, a missing
-- terminator), so decode() can fall through to the other format.
local function decode_entries(data, tbl, parsed, vwf)
  local newlineCode = vwf and VWF_NEWLINE or NEWLINE_CODE
  local lines = {}

  for i, entry in ipairs(parsed.entries) do
    local parts = {}
    local pos   = entry.start + PREFIX_BYTES
    local done  = false

    while pos + 2 <= entry.finish do
      local code = u16be(data, pos)
      local at   = pos
      pos = pos + 2

      if code == TERMINATOR then
        done = true
        break
      elseif code == newlineCode then
        parts[#parts + 1] = NEWLINE_TEXT
      else
        -- VWF packs the glyph ID in the high byte and the advance in the low.
        local glyphId = vwf and (code >> 8) or code
        local glyph = tbl.glyphs[glyphId]
        if glyph == nil then
          return nil, string.format(
            "unknown glyph 0x%04X in dialogue #%d (id=0x%04X) at byte offset "
            .. "0x%X; no ID 0x%04X in %s (%d entries)",
            code, i, entry.id, at, glyphId, tbl.path, tbl.count)
        end
        -- An empty mapping is a real glyph that renders as nothing; keep it.
        parts[#parts + 1] = glyph
      end
    end

    if not done then
      return nil, string.format(
        "dialogue #%d (id=0x%04X) is not terminated before byte 0x%X",
        i, entry.id, entry.finish)
    end

    lines[i] = table.concat(parts)
  end

  return lines
end

function codec.decode(data, args)
  check_args(args)

  -- Framing first, so a malformed file is reported as such even when there is
  -- also no font table for `args`.
  local parsed, why = analyze(data)
  if not parsed then
    error("decode(" .. args .. "): not a Sakura Taisen dialogue table: "
          .. tostring(why), 0)
  end

  local tbl = load_font_table(args, "decode(" .. args .. ")")

  -- The bytes on disc are either the historical plain-ID format or the packed
  -- one a VWF build writes, and only one of the two decodes cleanly: a legacy
  -- file carries the 0x0A0D newline and IDs below 0x0100 that a packed read
  -- rejects.  So decode reads whatever the file actually is, trying the format
  -- the current configuration targets first so the build's own output is the
  -- fast path.  This is what lets `unpack` keep reading the pristine source
  -- while `build` writes the packed one.
  local preferred = uses_vwf(args)
  local lines, firstError
  for _, vwf in ipairs(preferred and { true, false } or { false, true }) do
    local attempt, failure = decode_entries(data, tbl, parsed, vwf)
    if attempt then lines = attempt; break end
    firstError = firstError or failure
  end
  if not lines then
    error("decode(" .. args .. "): " .. firstError, 0)
  end

  -- Prefix each dialogue with its stable, 1-based entry index.
  for i, line in ipairs(lines) do
    lines[i] = string.format("%04d:%s", i, line)
  end

  local text = table.concat(lines, "\n") .. "\n"

  return {
    { name = artifact_name(args), data = text },
  }
end

function codec.encode(original, artifacts, args)
  check_args(args)

  if type(original) ~= "string" or original == "" then
    error("encode(" .. args .. "): patch encoding needs the original file bytes",
          0)
  end

  local parsed, why = analyze(original)
  if not parsed then
    error("encode(" .. args .. "): input is not a Sakura Taisen dialogue table: "
          .. tostring(why), 0)
  end

  local text
  for _, artifact in ipairs(artifacts or {}) do
    if type(artifact) == "table" and type(artifact.name) == "string"
       and type(artifact.data) == "string" and artifact.name:sub(-4) == ".TXT" then
      text = artifact.data
      break
    end
  end
  if text == nil then
    error("encode(" .. args .. "): expected a " .. artifact_name(args)
          .. " artifact", 0)
  end

  -- The decoder ends every line, including the last, with "\n"; drop the empty
  -- piece that leaves behind.
  local lines = {}
  do
    local pos = 1
    while true do
      local at = text:find("\n", pos, true)
      if not at then
        lines[#lines + 1] = text:sub(pos)
        break
      end
      lines[#lines + 1] = text:sub(pos, at - 1)
      pos = at + 1
    end
    if #lines > 0 and lines[#lines] == "" and text:sub(-1) == "\n" then
      lines[#lines] = nil
    end
  end

  local entries = parsed.entries

  local entries = parsed.entries
  local ordered = {}
  local expectedIndex = 1

  -- Blank lines and full-line # comments are editorial only.
  -- Dialogue indices must remain in their original order.
  for physicalLine, line in ipairs(lines) do
    if line:match("^%s*$") or line:match("^%s*#") then
      -- Ignore blank lines and comments.
    else
      local digits, dialogue = line:match("^(%d%d%d%d):(.*)$")

      if not digits then
        error(string.format(
          "encode(%s): TXT line %d must start with NNNN: (or be blank / a # comment)",
          args, physicalLine), 0)
      end

      local index = tonumber(digits)

      if index ~= expectedIndex then
        error(string.format(
          "encode(%s): TXT line %d has dialogue index %04d (expected %04d)",
          args, physicalLine, index, expectedIndex), 0)
      end

      ordered[index] = dialogue
      expectedIndex = expectedIndex + 1
    end
  end

  if expectedIndex - 1 ~= #entries then
    error(string.format(
      "encode(%s): %s has %d dialogue(s), but the table has %d entries",
      args, artifact_name(args), expectedIndex - 1, #entries), 0)
  end

  lines = ordered

  local tbl = load_font_table(ENCODE_FONT, "encode(" .. args .. ")")
  local reverse, maxLength = build_reverse(tbl)
  local vwf = uses_vwf(args)

  local footer = original:sub(parsed.timing + 1)

  local chunks  = {}
  local offsets = {}
  local cursor  = 0
  for i, entry in ipairs(entries) do
    local prefix = original:sub(entry.start + 1, entry.start + PREFIX_BYTES)
    local codes  = encode_dialogue(lines[i], i, entry.id, reverse, maxLength,
                                   tbl, args, vwf)

    offsets[i] = cursor // 2
    if offsets[i] > 0xFFFF then
      error(string.format(
        "encode(%s): offset of dialogue #%d overflows a u16", args, i), 0)
    end

    local parts = { prefix }
    for _, code in ipairs(codes) do
      if code < 0 or code > 0xFFFF then
        error(string.format(
          "encode(%s): glyph ID %d in dialogue #%d is not a u16",
          args, code, i), 0)
      end
      parts[#parts + 1] = char_u16be(code)
    end
    parts[#parts + 1] = char_u16be(TERMINATOR)
    local chunk = table.concat(parts)
    chunks[#chunks + 1] = chunk
    cursor = cursor + #chunk
  end

  local body      = table.concat(chunks)
  local rawTiming = (parsed.headerEnd + #body) // 2
  if rawTiming > 0xFFFF then
    error(string.format(
      "encode(%s): timing offset %d overflows a u16 (file would exceed 128 KiB)",
      args, rawTiming), 0)
  end

  local header = { char_u16be(parsed.headerEnd // 2), char_u16be(rawTiming) }
  for i, entry in ipairs(entries) do
    header[#header + 1] = char_u16be(entry.id)
    header[#header + 1] = char_u16be(offsets[i])
  end

  return table.concat(header) .. body .. footer
end

return codec
