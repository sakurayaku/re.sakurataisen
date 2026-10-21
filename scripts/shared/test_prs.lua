--[[ Test harness for prs.lua — run from the project root: lua scripts/shared/test_prs.lua ]]

local function script_dir()
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then return src:sub(2):match("^(.*)[/\\][^/\\]*$") or "." end
  return "."
end

local prs = dofile(script_dir() .. "/prs.lua")

local pass, fail = 0, 0
local function check(name, ok, detail)
  if ok then pass = pass + 1; print("  ok    " .. name)
  else fail = fail + 1; print("  FAIL  " .. name .. (detail and ("  -- " .. detail) or "")) end
end

local function roundtrip(data)
  local packed = prs.compress(data)
  return prs.decompress(packed), packed
end

print("prs.lua test harness")
print("")

print("round trip")
for _, case in ipairs({
  { "empty input", "" },
  { "one byte", "A" },
  { "two bytes", "AB" },
  { "three bytes", "ABC" },
  { "a run of one byte", string.rep("\x00", 5000) },
  { "a periodic pattern", string.rep("AB", 5000) },
  { "text", string.rep("Sakura Taisen main menu 0123456789 ", 300) },
}) do
  local out, packed = roundtrip(case[2])
  check(case[1] .. " (" .. #case[2] .. " -> " .. #packed .. ")", out == case[2])
end

print("")
print("boundaries")
-- A match that ends on the last byte is the case a naive comparator gets wrong.
for _, len in ipairs({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 255, 256, 257, 511, 512, 1023 }) do
  local data = string.rep("Z", len)
  local out = roundtrip(data)
  check(string.format("a %d-byte run", len), out == data)
end

for _, len in ipairs({ 250, 255, 256, 257, 260, 300 }) do
  local data = string.rep("AB", len):sub(1, len)
  local out = roundtrip(data)
  check(string.format("a %d-byte periodic prefix", len), out == data)
end

-- Distances above the short-reference range have to use the long form.
local far = string.rep("Q", 300) .. string.rep("\x01\x02", 200) .. string.rep("Q", 300)
check("a repeat beyond 256 bytes back", roundtrip(far) == far)

print("")
print("incompressible data")
local parts = {}
local state = 12345
for i = 1, 4000 do
  state = (state * 1103515245 + 12345) & 0x7FFFFFFF
  parts[i] = string.char((state >> 16) & 0xFF)
end
local random = table.concat(parts)
local out, packed = roundtrip(random)
check("random bytes survive", out == random)
check("random bytes are not compressed away", #packed >= #random, string.format("%d -> %d", #random, #packed))

print("")
print("shipping LOGO.SH2 blocks")
-- Regression guard for the main-menu budget: these two blocks are reinserted
-- into fixed slots of 2,280 and 3,942 bytes, so the encoder must at least match
-- the original.  Only the ceiling is asserted, so a better parser still passes.
local function read_file(path)
  local handle = io.open(path, "rb")
  if not handle then return nil end
  local data = handle:read("*a")
  handle:close()
  return data
end

local root = script_dir() .. "/../.."
local logo = read_file(root .. "/LOGO.SH2") or read_file("LOGO.SH2")
if not logo then
  print("  (skipped: LOGO.SH2 not found)")
else
  local FONT_OFFSET, FONT_SLOT = 0x0000ff20, 2280
  local BGND_OFFSET, BGND_SLOT = 0x00010808, 3942

  local font = prs.decompress(logo:sub(FONT_OFFSET + 1, FONT_OFFSET + FONT_SLOT))
  local bgnd = prs.decompress(logo:sub(BGND_OFFSET + 1, BGND_OFFSET + BGND_SLOT))

  check("font block decompresses to a glyph sheet", #font == 5120, tostring(#font))
  check("background block decompresses to 304x208", #bgnd == 31616, tostring(#bgnd))

  local packed_font, packed_bgnd = prs.compress(font), prs.compress(bgnd)
  check("font fits its " .. FONT_SLOT .. "-byte slot", #packed_font <= FONT_SLOT,
    string.format("%d bytes", #packed_font))
  check("background fits its " .. BGND_SLOT .. "-byte slot", #packed_bgnd <= BGND_SLOT,
    string.format("%d bytes", #packed_bgnd))
  check("the two blocks together fit the 6222-byte budget",
    #packed_font + #packed_bgnd <= FONT_SLOT + BGND_SLOT,
    string.format("%d bytes", #packed_font + #packed_bgnd))
  check("font block round-trips", prs.decompress(packed_font) == font)
  check("background block round-trips", prs.decompress(packed_bgnd) == bgnd)
end

print("")
print("empty stream")
check("an empty input still produces a terminator", prs.decompress(prs.compress("")) == "")
check("decoding garbage does not throw",
  (function() local ok = pcall(prs.decompress, "\xFF\xFF\xFF") return ok end)())

print("")
print(string.format("%d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
