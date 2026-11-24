--[[
  Dependency-free test harness for the font layout patch codecs:

      scripts/SAKURA/patch_8px_font.lua       ADV glyph layout
      scripts/SLG/patch_8px_font.lua          SLG glyph layout

  Run:  ludared scripts test tests/test_font_patches.lua

  The pristine SAKURA / SLG.BIN / 0SLG.BIN are the inputs under test; when they
  are absent the real-file section is skipped (not failed), so the harness
  still runs on a bare checkout.  The shipped US-patched executables, when
  present under ../RomHackingTools, are the expected layout result.

  Each codec is also asked about the *other* engine's file: it has to say "no"
  and refuse to encode, which keeps the two codecs from overlapping.
]]

-- ---------------------------------------------------------------------------

-- Project paths are provided by the Ludared test runner.

local PROJECT_ROOT = LUDARED.PROJECT_ROOT
local US_ROOT      = "/Users/red/Projects/Hashire/RomHackingTools/SakuraTaisen/Data/FromTrekkies"

local sakuraLayout = dofile(LUDARED.SCRIPTS .. "/SAKURA/patch_8px_font.lua")
local slgLayout    = dofile(LUDARED.SCRIPTS .. "/SLG/patch_8px_font.lua")

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

local function check_skip(name, reason)
  skipped = skipped + 1
  print("  skip  " .. name .. "  -- " .. reason)
end

local function slurp(path)
  local fh = io.open(path, "rb")
  if not fh then return nil end
  local data = fh:read("*a")
  fh:close()
  return data
end

local function diff_count(a, b)
  local n = 0
  for i = 1, #a do
    if a:byte(i) ~= b:byte(i) then n = n + 1 end
  end
  return n
end

-- ---------------------------------------------------------------------------

local SAKURA_LAYOUT = {
  { 0x0104D7, 0x10, 0x0C }, { 0x0104E5, 0x10, 0x08 }, { 0x0105FB, 0xCC, 0xCE },
  { 0x010603, 0xC4, 0xC6 }, { 0x01066B, 0x10, 0x08 }, { 0x010733, 0x10, 0x0C },
  { 0x010747, 0x10, 0x08 },
}

local SLG_LAYOUT = {
  { 0x021655, 0x0F, 0x1E }, { 0x02165D, 0x10, 0x0C }, { 0x02167B, 0x10, 0x08 },
  { 0x02173D, 0xCC, 0xCE }, { 0x021755, 0x0F, 0x1E }, { 0x02178B, 0x0F, 0x1E },
  { 0x0217B9, 0x0F, 0x1E }, { 0x0217BF, 0x0F, 0x1E }, { 0x021809, 0x10, 0x08 },
  { 0x0218E1, 0x10, 0x0C }, { 0x0218EB, 0x0F, 0x1E }, { 0x021903, 0x10, 0x08 },
  { 0x021963, 0x0E, 0x1D }, { 0x02196B, 0x0E, 0x1D }, { 0x02196D, 0x02, 0x03 },
  { 0x021975, 0x02, 0x03 }, { 0x021981, 0x0F, 0x1E },
}

-- ---------------------------------------------------------------------------

local function check_takes_no_args(label, codec, data)
  check(label .. ": refuses an unexpected args string",
        not pcall(codec.encode, data, {}, "surprise"))
end

local function check_not_this_codec(label, codec, data)
  check(label .. ": can_handle is no", codec.can_handle(data) == "no",
        codec.can_handle(data))
  local ok, err = pcall(codec.encode, data, {}, nil)
  check(label .. ": encode refuses", not ok, err)
end

-- ---------------------------------------------------------------------------

local function test_layout(label, codec, data, sites, usData, usData2)
  print("")
  print("layout: " .. label)

  local patched = codec.encode(data, {})

  for _, site in ipairs(sites) do
    local offset, pristine, want = site[1], site[2], site[3]
    check(string.format("0x%06X pristine 0x%02X", offset, pristine),
          data:byte(offset + 1) == pristine)
    check(string.format("0x%06X patched 0x%02X", offset, want),
          patched:byte(offset + 1) == want)
    if usData then
      check(string.format("0x%06X matches the US build", offset),
            usData:byte(offset + 1) == want,
            string.format("us has 0x%02X", usData:byte(offset + 1)))
    end
  end

  check("only the listed bytes change", diff_count(patched, data) == #sites,
        "changed " .. diff_count(patched, data) .. " bytes, expected " .. #sites)
  check("length unchanged", #patched == #data)
  check("re-running is a no-op", codec.encode(patched, {}, nil) == patched)
  check("decode emits no artifacts", #codec.decode(data, nil) == 0)
  check("can_handle: pristine is certain", codec.can_handle(data) == "certain",
        codec.can_handle(data))
  check("can_handle: patched is certain", codec.can_handle(patched) == "certain",
        codec.can_handle(patched))
  check("can_handle: junk is no", codec.can_handle("not a binary") == "no")
  check_takes_no_args(label, codec, data)

  -- The US build's ABI-stride writes belong to its one-byte-per-glyph string
  -- representation and must stay untouched here.
  for _, offset in ipairs({ 0x010612, 0x010646, 0x021765, 0x021799 }) do
    if #data > offset + 1 then
      check(string.format("0x%06X (ABI stride) untouched", offset),
            patched:sub(offset + 1, offset + 2) == data:sub(offset + 1, offset + 2))
    end
  end

  -- A second executable of the same engine, already patched (disc 2), is
  -- recognised by content: same sites, no disc knowledge anywhere.
  if usData2 then
    check("already-patched second copy is recognised",
          codec.can_handle(usData2) == "certain", codec.can_handle(usData2))
    check("already-patched second copy is a no-op",
          codec.encode(usData2, {}, nil) == usData2)
  end
end

-- ---------------------------------------------------------------------------

local sakura   = slurp(PROJECT_ROOT .. "/SAKURA")
local slg      = slurp(PROJECT_ROOT .. "/SLG.BIN")
local slg0     = slurp(PROJECT_ROOT .. "/0SLG.BIN")
local usSakura = slurp(US_ROOT .. "/Disc1/SAKURA")
local usSakura2 = slurp(US_ROOT .. "/Disc2/SAKURA")
local usSlg    = slurp(US_ROOT .. "/Disc2/DontCopyOver/SLG.BIN")

if not sakura then
  check_skip("SAKURA codecs", PROJECT_ROOT .. "/SAKURA not found")
else
  test_layout("SAKURA", sakuraLayout, sakura, SAKURA_LAYOUT, usSakura, usSakura2)
end

if not slg then
  check_skip("SLG codecs", PROJECT_ROOT .. "/SLG.BIN not found")
else
  test_layout("SLG.BIN", slgLayout, slg, SLG_LAYOUT, usSlg)

  if slg0 then
    print("")
    print("second copy: 0SLG.BIN")
    check("layout patches identically",
          slgLayout.encode(slg0, {}, nil) == slgLayout.encode(slg, {}, nil))
  else
    check_skip("second copy: 0SLG.BIN", "0SLG.BIN not found")
  end
end

-- Each codec must be blind to the other engine's file.
if sakura and slg then
  print("")
  print("cross-engine: a codec only knows its own bytes")
  check_not_this_codec("ADV layout vs SLG.BIN", sakuraLayout, slg)
  check_not_this_codec("SLG layout vs SAKURA", slgLayout, sakura)
end

if sakura and not usSakura then
  check_skip("US build comparison", US_ROOT .. "/Disc1/SAKURA not found")
end

print("")
print(string.format("%d passed, %d failed, %d skipped", pass, fail, skipped))
assert(fail == 0, string.format("%d tests failed", fail))
