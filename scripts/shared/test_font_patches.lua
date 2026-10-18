--[[
  Dependency-free test harness for the font patch codecs:

      scripts/SAKURA/patch_8px_font.lua       ADV glyph layout
      scripts/SAKURA/patch_font_palette.lua   ADV text palettes
      scripts/SLG/patch_8px_font.lua          SLG glyph layout
      scripts/SLG/patch_palette.lua           SLG text palettes

  Run:  lua test_font_patches.lua

  The pristine SAKURA / SLG.BIN / 0SLG.BIN are the inputs under test; when they
  are absent the real-file section is skipped (not failed), so the harness
  still runs on a bare checkout.  The shipped US-patched executables, when
  present under ../RomHackingTools, confirm that every byte written is the byte
  the US build holds.

  Every codec is also asked about the *other* engine's file: each one has to
  say "no" and refuse to encode, which is what keeps the four codecs from
  overlapping.
]]

local function script_dir()
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then
    return src:sub(2):match("^(.*)[/\\][^/\\]*$") or "."
  end
  return "."
end

-- ---------------------------------------------------------------------------

local PROJECT_ROOT = "/Users/red/Projects/Hashire/re.sakurataisen"
local US_ROOT      = "/Users/red/Projects/Hashire/RomHackingTools/SakuraTaisen/Data/FromTrekkies"

local scriptDir = script_dir()
local sakuraLayout  = dofile(scriptDir .. "/../SAKURA/patch_8px_font.lua")
local sakuraPalette = dofile(scriptDir .. "/../SAKURA/patch_font_palette.lua")
local slgLayout     = dofile(scriptDir .. "/../SLG/patch_8px_font.lua")
local slgPalette    = dofile(scriptDir .. "/../SLG/patch_palette.lua")

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

local function diff_outside(a, b, windows)
  local n = 0
  for i = 0, #a - 1 do
    local inside = false
    for _, w in ipairs(windows) do
      if i >= w[1] and i < w[1] + w[2] then inside = true break end
    end
    if not inside and a:byte(i + 1) ~= b:byte(i + 1) then n = n + 1 end
  end
  return n
end

local function bytes(hex)
  local out = {}
  for i = 1, #hex, 2 do out[#out + 1] = string.char(tonumber(hex:sub(i, i + 1), 16)) end
  return table.concat(out)
end

local function splice(data, offset, repl)
  return data:sub(1, offset) .. repl .. data:sub(offset + #repl + 1)
end

-- ---------------------------------------------------------------------------
-- Write lists, spelled out independently of the codecs so a silent change to
-- either one is caught here.
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

local JP_DIALOGUE = "7fff0842108418c62108294a318c39ce42104a5252945ad663186b5a739c7fff"
local JP_LIPS     = "7fff08420842108418c62108294a318c39ce3dd041d245d449d64dd851da55dd"
local US_PALETTE  = "7fff14a51ce72529294a318c35ad4210463152945ad65ef767396f7b77bd0c63"

-- SAKURA tiles one palette pair per placement; the disc-2 build shifts the pair
-- by 0x138 and both are decided by content, so both bases are listed here.
local SAKURA_PLACEMENTS = { 0x53954, 0x53A8C }

local function sakura_palette_sites(base, patched)
  return {
    { base,         bytes(JP_DIALOGUE), patched, "dialogue text palette" },
    { base + 0x20,  bytes(JP_LIPS),     patched, "choice (LIPS) text palette" },
  }
end

local function mask_7f(data)
  local out = {}
  for i = 1, #data do out[i] = string.char(data:byte(i) & 0x7F) end
  return table.concat(out)
end

local SLG_PALETTE = mask_7f(bytes(US_PALETTE))
local SLG_PALETTE_SITES = {
  { 0x158A4, bytes(JP_DIALOGUE), SLG_PALETTE },
  { 0x158C4, bytes(JP_LIPS),     SLG_PALETTE },
}

-- ---------------------------------------------------------------------------
-- Shared checks
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

  local patched = codec.encode(data, {}, nil)

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

local function test_palette(label, codec, data, sites, usData)
  print("")
  print("palette: " .. label)

  local patched = codec.encode(data, {}, nil)

  for _, site in ipairs(sites) do
    local offset, pristine, want = site[1], site[2], site[3]
    check(string.format("0x%06X pristine ramp", offset),
          data:sub(offset + 1, offset + 32) == pristine)
    check(string.format("0x%06X patched palette", offset),
          patched:sub(offset + 1, offset + 32) == want)
    if usData then
      check(string.format("0x%06X matches the US build", offset),
            usData:sub(offset + 1, offset + 32) == want)
    end
  end

  local windows = {}
  for _, site in ipairs(sites) do windows[#windows + 1] = { site[1], 32 } end
  check("only the palette windows change", diff_outside(patched, data, windows) == 0)
  check("re-running is a no-op", codec.encode(patched, {}, nil) == patched)
  check("decode emits no artifacts", #codec.decode(data, nil) == 0)
  check("can_handle: pristine is certain", codec.can_handle(data) == "certain",
        codec.can_handle(data))
  check("can_handle: patched is certain", codec.can_handle(patched) == "certain",
        codec.can_handle(patched))
  check("can_handle: junk is no", codec.can_handle("not a binary") == "no")
  check_takes_no_args(label, codec, data)
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
  test_palette("SAKURA placement A", sakuraPalette, sakura,
               sakura_palette_sites(0x53954, bytes(US_PALETTE)), usSakura)

  -- The palette pair sits at two possible placements.  Build a copy whose
  -- placement-A windows are gone and whose placement-B windows hold the
  -- Japanese ramps, and the codec must find B without being told anything.
  local moved = splice(sakura, 0x53954, string.rep("\0", 0x40))
  moved = splice(moved, 0x53A8C, bytes(JP_DIALOGUE))
  moved = splice(moved, 0x53AAC, bytes(JP_LIPS))

  print("")
  print("palette: SAKURA placement B (content, not size)")
  check("placement B is recognised", sakuraPalette.can_handle(moved) == "certain",
        sakuraPalette.can_handle(moved))
  local outB = sakuraPalette.encode(moved, {}, nil)
  check("placement B patched",
        outB:sub(0x53A8C + 1, 0x53A8C + 32) == bytes(US_PALETTE))
  check("vacated placement A left alone",
        outB:sub(0x53954 + 1, 0x53954 + 32) == string.rep("\0", 32))

  if usSakura2 then
    check("US disc-2 build: palette recognised", sakuraPalette.can_handle(usSakura2) == "certain")
    check("US disc-2 build: palette already applied",
          sakuraPalette.encode(usSakura2, {}, nil) == usSakura2)
  end
end

if not slg then
  check_skip("SLG codecs", PROJECT_ROOT .. "/SLG.BIN not found")
else
  test_layout("SLG.BIN", slgLayout, slg, SLG_LAYOUT, usSlg)
  test_palette("SLG.BIN", slgPalette, slg, SLG_PALETTE_SITES, usSlg)

  if slg0 then
    print("")
    print("second copy: 0SLG.BIN")
    check("layout patches identically",
          slgLayout.encode(slg0, {}, nil) == slgLayout.encode(slg, {}, nil))
    check("palette patches identically",
          slgPalette.encode(slg0, {}, nil) == slgPalette.encode(slg, {}, nil))
  else
    check_skip("second copy: 0SLG.BIN", "0SLG.BIN not found")
  end
end

-- Each codec must be blind to the other engine's file.
if sakura and slg then
  print("")
  print("cross-engine: a codec only knows its own bytes")
  check_not_this_codec("ADV layout vs SLG.BIN", sakuraLayout, slg)
  check_not_this_codec("ADV palette vs SLG.BIN", sakuraPalette, slg)
  check_not_this_codec("SLG layout vs SAKURA", slgLayout, sakura)
  check_not_this_codec("SLG palette vs SAKURA", slgPalette, sakura)
end

if sakura and not usSakura then
  check_skip("US build comparison", US_ROOT .. "/Disc1/SAKURA not found")
end

print("")
print(string.format("%d passed, %d failed, %d skipped", pass, fail, skipped))
if fail > 0 then os.exit(1) end
