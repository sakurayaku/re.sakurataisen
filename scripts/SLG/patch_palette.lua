--[[
  Sakura Taisen (Saturn) — font palette patch for the SLG text engine.

  Standalone Lua codec for Ludared.  No external dependencies.

  WHY THIS EXISTS
  ---------------
  The SLG engine draws its glyphs from its own 16-entry BGR555 palette inside
  the executable:

      index  0        background
      index  1..14    the glyph ramp
      index 15        the ink

  The English font sheet (taken from the US release) was authored as dark
  glyphs on a white background, and the conversion tool moves the sheet's
  background colour into palette index 0, which remaps the tiles so the ink
  lands at index 15.  The Japanese palette has index 15 = 0x7FFF (white), the
  same as the background, so letter bodies render white with grey edges and the
  text looks hollow, thin and fragmented even though the glyph data is perfect.

  The US build replaces both SLG text palettes with the palette of the sheet
  it draws from — byte for byte the palette stored in the tool's own
  Data/8x12_SLG.bmp:

      7FFF 14A5 1CE7 2529 294A 318C 35AD 4210 4631 5294 5AD6 5EF7 6739 6F7B 77BD 0C63

  The engine stores it with every byte AND 0x7F (the original tool's stats-menu
  palette path does the same), so the bytes written here are the palette above
  masked — including the two entries that mask cannot represent exactly.  That
  is deliberate: it is what the US build holds, byte for byte.

  These values are not free parameters.  If the font sheet ever changes, this
  palette has to be regenerated from it.

  WHERE
  -----
      dialogue text palette   0x0158A4
      choice (LIPS) palette   0x0158C4

  32 bytes each.  The Japanese choice palette is a pink ramp; the US build
  overwrites it with the same grey palette as the dialogue text, so choice text
  uses the same solid font.  Reproduced here deliberately.

  IDENTIFICATION
  --------------
  The codec keys on the bytes at those two windows and nothing else: no file
  name, no file size, no container knowledge.  Each disc ships two
  byte-identical copies of this engine; nothing here distinguishes them,
  because bytes are bytes.

  PATCH CODEC SHAPE
  -----------------
  `decode` emits no artifacts; `encode` rewrites the buffer it is handed, so
  `encode(original, decode(original))` is the *patched* file, not the original.
  Intentional, and non-reversible in the CODEC_CONTRACT.md §5 sense.

  Both windows must be exactly the known pristine ramp or exactly the patched
  palette.  Anything else is a hard error rather than an overwrite, so a wrong
  revision or an already-differently-patched executable is reported instead of
  corrupted.  Running twice is safe.

  The ADV engine's palettes are scripts/SAKURA/patch_font_palette.lua.
]]

local codec = {}

codec.name        = "Sakura Taisen Font Palette (SLG)"
codec.description = "Replaces the SLG dialogue and choice text palettes in the "
                 .. "Sakura Taisen (Saturn) executable with the palette of the "
                 .. "US 8x12 font sheet, whose ink is palette index 15, stored "
                 .. "byte-masked with 0x7F as the engine does. Emits no "
                 .. "artifacts."
codec.version     = 1
codec.kind        = "patch"

local LABEL = "font palette (SLG)"

local function script_dir()
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then
    return src:sub(2):match("^(.*)[/\\][^/\\]*$") or "."
  end
  return "."
end

local palettes
if LUDARED and LUDARED.SCRIPTS then
  palettes = dofile(LUDARED.SCRIPTS .. "/shared/palettes.lua")
else
  palettes = dofile(script_dir() .. "/../shared/palettes.lua")
end

-- ---------------------------------------------------------------------------
-- Palettes, as hex byte strings (Saturn BGR555, big endian per entry)
-- ---------------------------------------------------------------------------

-- What the translated 8x12 sheet needs: index 0 = 0x7FFF (white background), a
-- grey ramp, index 15 = 0x0C63 (near-black ink).  Both sites get the same
-- colours today; the two names keep them independently replaceable.
local I18N_DIALOGUE = palettes.hex("slg_dialogue_i18n")
local I18N_LIPS     = palettes.hex("slg_lips_i18n")

-- The Japanese dialogue palette: a grey ramp whose last entry is white.
local JP_DIALOGUE = palettes.hex("slg_dialogue_jp")

-- The Japanese choice (LIPS) palette: pink, sharing the low half of the ramp.
local JP_LIPS = palettes.hex("slg_lips_jp")

local PALETTE_BYTES = 32

local function bytes(hex)
  local out = {}
  for i = 1, #hex, 2 do out[#out + 1] = string.char(tonumber(hex:sub(i, i + 1), 16)) end
  return table.concat(out)
end

-- The engine stores the palette with every byte masked: p[i] = palette[i] & 0x7F.
local function mask_7f(data)
  local out = {}
  for i = 1, #data do out[i] = string.char(data:byte(i) & 0x7F) end
  return table.concat(out)
end

local SITES = {
  { 0x0158A4, bytes(JP_DIALOGUE), mask_7f(bytes(I18N_DIALOGUE)), "dialogue text palette" },
  { 0x0158C4, bytes(JP_LIPS),     mask_7f(bytes(I18N_LIPS)),     "choice (LIPS) text palette" },
}

-- ---------------------------------------------------------------------------
-- Site machinery
-- ---------------------------------------------------------------------------

local function hex(data)
  local out = {}
  for i = 1, #data do out[i] = string.format("%02x", data:byte(i)) end
  return table.concat(out)
end

-- "patched", "pristine" or nil when the window holds a value this codec does
-- not know.
local function site_state(data, site)
  local current = data:sub(site[1] + 1, site[1] + #site[2])
  if current == site[3] then return "patched" end
  if current == site[2] then return "pristine" end
  return nil
end

local function report(data, sites)
  local lines = {}
  for _, site in ipairs(sites) do
    if not site_state(data, site) then
      lines[#lines + 1] = string.format("  0x%06X (%s) wants %s or %s, found %s",
        site[1], site[4], hex(site[2]), hex(site[3]),
        hex(data:sub(site[1] + 1, site[1] + #site[2])))
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
  if score == 0 then return nil, 0, "0 of " .. #SITES .. " palettes match" end
  return SITES, score, score .. " of " .. #SITES .. " palettes match"
end

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
  error(string.format("%s: %s: no SLG palette here (%s)\n%s",
    LABEL, stage, detail, report(data, sites or SITES)), 0)
end

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
  return "possible"
end

function codec.decode_name(args)
  if type(args) == "string" and #args > 0 then return args end
  return "palette"
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
