--[[
  Dependency-free test harness for re.sakurataisen/scripts/dialogues.lua

  Run:  lua test_dialogues.lua                     (synthetic + real-table tests)
        lua test_dialogues.lua <list-file>         (also round-trip a corpus)

  <list-file> has one table per line, "<stem><TAB><path>" (a third leading
  column is tolerated), where <path> is a real NNNNTBL.BIN / M##MES.BIN.

  Framing tests use synthetic TBL/MES bytes.  Glyph tests need the real
  workspace/tables/0100KNJ.tbl; they are skipped (not failed) when it is
  absent, so the harness runs on a bare checkout.
]]

local function script_dir()
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then
    return src:sub(2):match("^(.*)[/\\\\][^/\\\\]*$") or "."
  end
  return "."
end

local scriptDir = script_dir()
local codecPath = scriptDir .. "/../dialogues.lua"
local codec = dofile(codecPath)

-- ---------------------------------------------------------------------------

local pass, fail, skipped = 0, 0, 0

local function check(name, ok, detail)
  if ok then
    pass = pass + 1
    print("  ok    " .. name)
  else
    fail = fail + 1
    print("  FAIL  " .. name .. (detail and ("  -- " .. detail) or ""))
  end
end

local function check_eq(name, got, want)
  check(name, got == want, "got " .. tostring(got) .. ", want " .. tostring(want))
end

local function check_err(name, fn, pattern)
  local ok, err = pcall(fn)
  if ok then
    fail = fail + 1
    print("  FAIL  " .. name .. "  -- expected an error, none raised")
  elseif pattern and not tostring(err):find(pattern, 1, true) then
    fail = fail + 1
    print("  FAIL  " .. name .. "  -- wrong error: " .. tostring(err))
  else
    pass = pass + 1
    print("  ok    " .. name)
  end
end

local function check_skip(name, reason)
  skipped = skipped + 1
  print("  SKIP  " .. name .. "  -- " .. reason)
end

-- ---------------------------------------------------------------------------
-- Synthetic dialogue table
--
-- entries: { { id=<u16>, prefix0=<u16>, prefix1=<u16>, codes={...} }, ... }
-- ---------------------------------------------------------------------------

local function u16be_char(value)
  return string.char(math.floor(value / 256) % 256, value % 256)
end

local function u16be_at(data, off)
  return data:byte(off + 1) * 256 + data:byte(off + 2)
end

local function build_tbl(entries, footer, mutate)
  footer = footer or ""
  local headerBytes = 4 * (#entries + 1)
  local payload = {}
  local offsets = {}
  local cursor = 0

  for i, entry in ipairs(entries) do
    offsets[i] = cursor // 2    -- halfwords from the header end
    local bytes = { u16be_char(entry.prefix0 or 0), u16be_char(entry.prefix1 or 0) }
    for _, code in ipairs(entry.codes or {}) do
      bytes[#bytes + 1] = u16be_char(code)
    end
    bytes[#bytes + 1] = u16be_char(0)   -- terminator
    local chunk = table.concat(bytes)
    payload[#payload + 1] = chunk
    cursor = cursor + #chunk
  end

  local body = table.concat(payload)
  local header = {
    u16be_char(headerBytes // 2),
    u16be_char((headerBytes + #body) // 2),
  }
  for i, entry in ipairs(entries) do
    header[#header + 1] = u16be_char(entry.id)
    header[#header + 1] = u16be_char(offsets[i])
  end

  local data = table.concat(header) .. body .. footer
  if mutate then data = mutate(data) end
  return data
end

-- Glyph codes of entry `index` (1-based) in a well-formed dialogue table.
local function entry_codes(data, index)
  local headerEnd = u16be_at(data, 0) * 2
  local timing    = u16be_at(data, 2) * 2
  local count     = headerEnd // 4 - 1
  local start = headerEnd + u16be_at(data, 4 + (index - 1) * 4 + 2) * 2
  local finish = index < count
    and (headerEnd + u16be_at(data, 4 + index * 4 + 2) * 2) or timing
  local codes = {}
  local pos = start + 4
  while pos + 2 <= finish do
    local code = u16be_at(data, pos)
    pos = pos + 2
    if code == 0 then break end
    codes[#codes + 1] = code
  end
  return codes
end

local function codes_equal(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    if a[i] ~= b[i] then return false end
  end
  return true
end

local function codes_to_string(codes)
  local out = {}
  for _, code in ipairs(codes) do
    out[#out + 1] = string.format("0x%04X", code)
  end
  return "{" .. table.concat(out, ",") .. "}"
end

-- ---------------------------------------------------------------------------

local PROJECT_ROOT = "/Users/red/Projects/Hashire/re.sakurataisen"
local TABLE_0100 = PROJECT_ROOT .. "/workspace/tables/0100KNJ.tbl"

local function file_exists(path)
  local fh = io.open(path, "rb")
  if fh then fh:close() return true end
  return false
end

local HAVE_TABLE = file_exists(TABLE_0100)

-- ---------------------------------------------------------------------------

print("dialogues.lua test harness")
print("")

print("module shape")
check_eq("name", codec.name, "Sakura Taisen Dialogues")
check_eq("kind", codec.kind, "patch")
check_eq("version", codec.version, 1)
check("can_handle is a function", type(codec.can_handle) == "function")
check("decode_name is a function", type(codec.decode_name) == "function")
check("decode is a function", type(codec.decode) == "function")
check("encode is a function", type(codec.encode) == "function")
check("description mentions dialogue",
      type(codec.description) == "string" and codec.description:find("ialogue") ~= nil)

print("")
print("overridable globals")
do
  local saved = ENCODE_FONT
  ENCODE_FONT = nil
  local reloaded = dofile(codecPath)
  check_eq("ENCODE_FONT defaults to I18N_FONT", _G.ENCODE_FONT, "I18N_FONT")
  check_eq("MAX_LINES defaults to 99", _G.MAX_LINES, 99)
  check_eq("LINE_WIDTH_PX defaults to 240", _G.LINE_WIDTH_PX, 240)
  check_eq("DEFAULT_GLYPH_WIDTH defaults to 16", _G.DEFAULT_GLYPH_WIDTH, 16)
  ENCODE_FONT = "0100KNJ"
  reloaded = dofile(codecPath)
  check_eq("externally defined ENCODE_FONT survives a reload", _G.ENCODE_FONT, "0100KNJ")
  ENCODE_FONT = saved
  codec = dofile(codecPath)
end

print("")
print("can_handle")
local good = build_tbl({
  { id = 0x9C41, prefix0 = 0, prefix1 = 0, codes = { 0x000A, 0x000B, 0x0A0D, 0x000C } },
  { id = 0x9C42, prefix0 = 0x0004, prefix1 = 0, codes = { 0x0001 } },
}, string.rep("\x2E", 8))
check_eq("structurally valid -> likely", codec.can_handle(good), "likely")
check_eq("nil -> no", codec.can_handle(nil), "no")
check_eq("number -> no", codec.can_handle(42), "no")
check_eq("empty -> no", codec.can_handle(""), "no")
check_eq("short -> no", codec.can_handle(good:sub(1, 7)), "no")

check_eq("header not a multiple of 4 -> no",
         codec.can_handle(build_tbl({ { id = 1 } }, "", function(d)
           return string.char(0x00, 0x03) .. d:sub(3)   -- rawHeader = 3
         end)), "no")

check_eq("timing before header -> no",
         codec.can_handle(build_tbl({ { id = 1 } }, "", function(d)
           return d:sub(1, 1) .. string.char(0, 0) .. d:sub(4)  -- rawTiming = 0
         end)), "no")

check_eq("timing past EOF -> no",
         codec.can_handle(build_tbl({ { id = 1 } }, "", function(d)
           return d:sub(1, 1) .. string.char(0xFF, 0xFF) .. d:sub(4)
         end)), "no")

check_eq("non-monotonic offsets -> no",
         codec.can_handle(build_tbl({
           { id = 1, codes = { 0x0001 } },
           { id = 2, codes = { 0x0002 } },
         }, "", function(d)
           -- bytes: 1-2 header, 3-4 timing, 5-6 id0, 7-8 off0, 9-10 id1, 11-12 off1
           local o0a, o0b = d:byte(7), d:byte(8)
           local o1a, o1b = d:byte(11), d:byte(12)
           return d:sub(1, 6) .. string.char(o1a, o1b) .. d:sub(9, 10)
                  .. string.char(o0a, o0b) .. d:sub(13)
         end)), "no")

check_eq("entry without terminator -> no",
         codec.can_handle(build_tbl({ { id = 1, codes = { 0x0001 } } }, "", function(d)
           return d:sub(1, #d - 2) .. string.char(0x00, 0x01)
         end)), "no")

check_eq("bytes after the terminator -> no",
         codec.can_handle(build_tbl({ { id = 1, codes = { 0x0001, 0x0000, 0x0002 } } }, "")), "no")

check_eq("trailing footer outside entry spans -> likely", codec.can_handle(good), "likely")

print("")
print("decode_name")
check_eq("TBL table name", codec.decode_name("0100KNJ"), "0100TBL.TXT")
check_eq("MES table name", codec.decode_name("M01MES"), "M01MES.TXT")
check_err("nil args", function() codec.decode_name(nil) end, "font identifier")
check_err("empty args", function() codec.decode_name("") end, "font identifier")
check_err("path-like args", function() codec.decode_name("../x") end, "invalid font identifier")
check_eq("underscore font name", codec.decode_name("I18N_FONT"), "I18N_FONT.TXT")

print("")
print("decode framing")
check_err("malformed input is rejected", function()
  codec.decode(build_tbl({ { id = 1 } }, ""):sub(1, 6), "0100KNJ")
end, "not a Sakura Taisen dialogue table")

if not HAVE_TABLE then
  check_skip("empty entries keep their index", "workspace/tables/0100KNJ.tbl not found")
else
  local structured = build_tbl({
    { id = 0x9C41, prefix0 = 0, prefix1 = 0 },
    { id = 0x9C42, prefix0 = 0, prefix1 = 0 },
  }, "")
  local arts = codec.decode(structured, "0100KNJ")
  check_eq("one artifact", #arts, 1)
  check_eq("artifact name", arts[1].name, "0100TBL.TXT")
  check_eq("two empty lines, stable indices", arts[1].data, "\n\n")
end

print("")
print("decode glyph lookup")
if not HAVE_TABLE then
  check_skip("glyph decoding", "workspace/tables/0100KNJ.tbl not found")
  check_skip("unknown glyph reporting", "workspace/tables/0100KNJ.tbl not found")
else
  -- 0x000A='さ' 0x000B='く' 0x000C='ら' 0x0001='、' (stable kana).
  -- Multi-char tiles and empty values are covered by the controlled table in
  -- the "font table widths" section, since the real tables' special tiles are
  -- re-exported as they are identified.
  local data = build_tbl({
    { id = 0x9C41, codes = { 0x000A, 0x000B, 0x0A0D, 0x000C, 0x0001 } },
    { id = 0x9C42, codes = { 0x000C } },
    { id = 0x9C43, codes = {} },
  }, string.rep("\x2E", 4))

  local arts = codec.decode(data, "0100KNJ")
  check_eq("artifact name", arts[1].name, "0100TBL.TXT")
  local lines = {}
  for line in arts[1].data:gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
  check_eq("one line per entry", #lines, 3)
  check_eq("glyphs + <br> newline", lines[1], "さく<br>ら、")
  check_eq("plain glyph", lines[2], "ら")
  check_eq("empty entry keeps its index", lines[3], "")

  check_err("unknown glyph is reported with context", function()
    codec.decode(build_tbl({
      { id = 0x9C41, codes = { 0x000A } },
      { id = 0x9C42, codes = { 0xFFFF } },
    }, ""), "0100KNJ")
  end, "dialogue #2")
  check_err("unknown glyph reports the code", function()
    codec.decode(build_tbl({ { id = 1, codes = { 0x7FFE } } }, ""), "0100KNJ")
  end, "0x7FFE")
  check_err("unknown glyph reports a byte offset", function()
    codec.decode(build_tbl({ { id = 1, codes = { 0x7FFE } } }, ""), "0100KNJ")
  end, "byte offset 0x")
end

print("")
print("table loading")
check_err("missing font table is reported", function()
  codec.decode(build_tbl({ { id = 1, codes = { 0x0001 } } }, ""), "ZZZZZZ")
end, "cannot open font table")

print("")
print("encode (patch contract)")
if not HAVE_TABLE then
  check_skip("round-trip and insertion", "workspace/tables/0100KNJ.tbl not found")
else
  ENCODE_FONT = "0100KNJ"

  -- Bit-exact round-trip: unchanged text re-encodes to the same bytes.
  local rt = build_tbl({
    { id = 0x9C41, prefix0 = 0x1234, prefix1 = 0x0007,
      codes = { 0x000A, 0x000B, 0x0A0D, 0x000C, 0x0001 } },
    { id = 0x9C42, prefix0 = 0x0000, prefix1 = 0x0002, codes = { 0x0217 } },
    { id = 0x9C43, prefix0 = 0, prefix1 = 0, codes = {} },
  }, string.rep("\x2E", 12))
  local rtArts = codec.decode(rt, "0100KNJ")
  check("synthetic file round-trips bit-exact",
        codec.encode(rt, rtArts, "0100KNJ") == rt)

  -- Metadata is preserved; only the payload changes.
  local preserved = build_tbl({
    { id = 0x9C41, prefix0 = 0xABCD, prefix1 = 0x0009, codes = { 0x000A } },
  }, "FOOTERBYTES")
  local pArts = codec.decode(preserved, "0100KNJ")
  pArts[1].data = "ら\n"                -- 0x000C
  local pOut = codec.encode(preserved, pArts, "0100KNJ")
  check_eq("id preserved", u16be_at(pOut, 4), 0x9C41)
  local headerEnd = u16be_at(pOut, 0) * 2
  check_eq("prefix preserved", pOut:sub(headerEnd + 1, headerEnd + 4),
           string.char(0xAB, 0xCD, 0x00, 0x09))
  check("footer preserved", pOut:sub(-#("FOOTERBYTES")) == "FOOTERBYTES")
  check("payload rebuilt", codes_equal(entry_codes(pOut, 1), { 0x000C }))

  -- <br> is an explicit break and is re-encoded as 0x0A0D.
  local br = build_tbl({ { id = 1, codes = { 0x000A } } }, "")
  local brArts = { { name = "0100TBL.TXT", data = "さ<br>ら\n" } }
  check("explicit <br> becomes 0x0A0D",
        codes_equal(entry_codes(codec.encode(br, brArts, "0100KNJ"), 1),
                    { 0x000A, 0x0A0D, 0x000C }))

  -- 240px at the default 16px per glyph -> 15 glyphs per line.
  local wrap = build_tbl({ { id = 1, codes = { 0x000A } } }, "")
  local wrapArts = { { name = "0100TBL.TXT", data = string.rep("さ", 16) .. "\n" } }
  local want = {}
  for _ = 1, 15 do want[#want + 1] = 0x000A end
  want[#want + 1] = 0x0A0D
  want[#want + 1] = 0x000A
  check_eq("wraps at 240px / 16px = 15 glyphs",
           codes_to_string(entry_codes(codec.encode(wrap, wrapArts, "0100KNJ"), 1)),
           codes_to_string(want))

  -- MAX_LINES is a global guard.
  do
    local savedMax = MAX_LINES
    MAX_LINES = 1
    check_err("MAX_LINES is enforced", function()
      codec.encode(wrap, wrapArts, "0100KNJ")
    end, "over MAX_LINES")
    MAX_LINES = savedMax
  end

  check_err("unknown text character is reported", function()
    local arts = { { name = "0100TBL.TXT", data = "€\n" } }
    codec.encode(wrap, arts, "0100KNJ")
  end, "has no glyph for")
  check_err("line/entry count mismatch is reported", function()
    local arts = { { name = "0100TBL.TXT", data = "さ\nら\n" } }
    codec.encode(wrap, arts, "0100KNJ")
  end, "stable line-to-entry mapping")
end

print("")
print("encode input validation")
check_err("encode needs the original bytes", function()
  codec.encode("", { { name = "0100TBL.TXT", data = "x\n" } }, "0100KNJ")
end, "needs the original file bytes")
check_err("encode requires the TXT artifact", function()
  codec.encode(build_tbl({ { id = 1 } }, ""), {}, "0100KNJ")
end, ".TXT artifact")
check_err("encode rejects malformed input", function()
  codec.encode(build_tbl({ { id = 1 } }, ""):sub(1, 6),
               { { name = "0100TBL.TXT", data = "\n" } }, "0100KNJ")
end, "not a Sakura Taisen dialogue table")

print("")
print("font table widths")
do
  local WIDTH_FONT = "ZZWIDTHTEST"
  local widthPath = PROJECT_ROOT .. "/workspace/tables/" .. WIDTH_FONT .. ".tbl"
  local created = false
  if not file_exists(widthPath) then
    local fh = io.open(widthPath, "wb")
    if fh then
      fh:write("0001=5=A\n0002=B\n0003=10=C\n0004=\n0005=XY\n0006=8=Z\n")
      fh:close()
      created = true
    end
  end

  if not created then
    check_skip("HEX=WIDTH=GLYPH parsing", widthPath .. " already exists")
  else
    -- Decode side, on a table whose values we control: multi-character tiles
    -- survive, an empty value is a real glyph (not a missing one), and a value
    -- after an explicit width is read correctly.
    local probe = build_tbl({
      { id = 1, codes = { 1, 2, 3 } },   -- ABC
      { id = 2, codes = { 4 } },         -- "" (empty value)
      { id = 3, codes = { 5 } },         -- XY (multi-character)
      { id = 4, codes = { 6 } },         -- Z  (value after an explicit width)
    }, "")
    local probeLines = {}
    for line in codec.decode(probe, WIDTH_FONT)[1].data:gmatch("([^\n]*)\n") do
      probeLines[#probeLines + 1] = line
    end
    check_eq("explicit-width glyph decodes", probeLines[1], "ABC")
    check_eq("empty value is valid, not missing", probeLines[2], "")
    check_eq("multi-character tile decodes whole", probeLines[3], "XY")
    check_eq("value after an explicit width decodes", probeLines[4], "Z")
    check_err("id absent from the table is an error", function()
      codec.decode(build_tbl({ { id = 1, codes = { 0x9999 } } }, ""), WIDTH_FONT)
    end, "unknown glyph")

    local function wrap_codes(text)
      local data = build_tbl({ { id = 1, codes = { 1 } } }, "")
      local arts = { { name = "0100TBL.TXT", data = text .. "\n" } }
      return entry_codes(codec.encode(data, arts, "0100KNJ"), 1)
    end

    local savedFont, savedWidth = ENCODE_FONT, DEFAULT_GLYPH_WIDTH
    ENCODE_FONT = WIDTH_FONT

    -- A = 5px  -> 240/5 = 48 per line
    local a = wrap_codes(string.rep("A", 49))
    check_eq("explicit width 5 wraps at 48", #a, 50)   -- 48 + 0x0A0D + 1
    check_eq("  wrap point is exact", a[49], 0x0A0D)

    -- C = 10px -> 24 per line
    local c = wrap_codes(string.rep("C", 25))
    check_eq("explicit width 10 wraps at 24", #c, 26)

    -- B has no width -> DEFAULT_GLYPH_WIDTH
    DEFAULT_GLYPH_WIDTH = 8
    local b8 = wrap_codes(string.rep("B", 31))
    check_eq("default 8px wraps at 30", #b8, 32)

    DEFAULT_GLYPH_WIDTH = 16
    local b16 = wrap_codes(string.rep("B", 16))
    check_eq("default 16px wraps at 15", #b16, 17)

    DEFAULT_GLYPH_WIDTH, ENCODE_FONT = savedWidth, savedFont
    os.remove(widthPath)
    check("temporary width table removed", not file_exists(widthPath))
  end
end

print("")
print("encode font selection")
if not file_exists(PROJECT_ROOT .. "/workspace/tables/I18N_FONT.tbl") then
  check_skip("default ENCODE_FONT is the French table",
             "workspace/tables/I18N_FONT.tbl not found")
else
  ENCODE_FONT = "I18N_FONT"

  -- The US font is a CP1252 identity table: 'A' is glyph 0x0041, ' ' is 0x0020.
  local data = build_tbl({ { id = 0x1234, codes = { 0x0041, 0x0020, 0x00E9, 0x0085 } } }, "")
  local arts = codec.decode(data, "I18N_FONT")
  check_eq("default font decodes", arts[1].data, "A \195\169\226\128\166\n")
  local ok, out = pcall(codec.encode, data, arts, "I18N_FONT")
  check("default font round-trips", ok and out == data,
        ok and "bytes differ" or tostring(out))

  check_err("missing font table is still an error", function()
    local saved = ENCODE_FONT
    ENCODE_FONT = "NO_SUCH_FONT"
    local d = build_tbl({ { id = 1, codes = { 0x0041 } } }, "")
    local a = codec.decode(d, "I18N_FONT")
    codec.encode(d, a, "I18N_FONT")
    ENCODE_FONT = saved
  end, "cannot open font table")
end

-- ---------------------------------------------------------------------------
-- Optional corpus round-trip.
-- ---------------------------------------------------------------------------

local listFile = arg and arg[1]
if listFile then
  print("")
  print("corpus round-trip (" .. listFile .. ")")
  if not HAVE_TABLE then
    check_skip("corpus round-trip", "workspace/tables/0100KNJ.tbl not found")
  else
    local fh = io.open(listFile, "r")
    if not fh then
      check("corpus list opens", false, "cannot open " .. listFile)
    else
      local files, exact, differing = 0, 0, {}
      for line in fh:lines() do
        local col = {}
        for field in line:gmatch("[^\t]+") do col[#col + 1] = field end
        local stem, path
        if #col >= 3 then stem, path = col[2], col[3]
        elseif #col == 2 then stem, path = col[1], col[2] end
        if stem and path then
          local handle = io.open(path, "rb")
          if handle then
            local data = handle:read("*a")
            handle:close()
            local arts = codec.decode(data, stem)
            ENCODE_FONT = stem
            if codec.encode(data, arts, stem) == data then
              exact = exact + 1
            else
              differing[#differing + 1] = stem
            end
            files = files + 1
          end
        end
      end
      fh:close()
      print(string.format("  %d file(s): %d bit-exact, %d differing",
                          files, exact, #differing))

      -- One known gap.  0904KNJ #221 centres text on a 16-tile line, which is
      -- 256px at the 16px default, so the encoder re-wraps it.  It clears as
      -- soon as the U+3000 tile is tagged "=8=" (see the codec header); every
      -- other entry, and every other file, is bit-exact.  Anything beyond this
      -- list is a regression.
      local KNOWN_GAPS = { ["0904KNJ"] = true }
      local unexpected = {}
      for _, stem in ipairs(differing) do
        if not KNOWN_GAPS[stem] then unexpected[#unexpected + 1] = stem end
      end
      if #unexpected > 0 then
        print("  UNEXPECTED differing: " .. table.concat(unexpected, ", "))
      end
      check("corpus round-trip ran", files > 0)
      check("no unexpected round-trip gaps", #unexpected == 0)
    end
  end
end

print("")
print(string.format("%d passed, %d failed, %d skipped", pass, fail, skipped))
if fail > 0 then os.exit(1) end
