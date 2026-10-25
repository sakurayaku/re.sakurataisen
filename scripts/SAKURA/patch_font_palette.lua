--[[
  Sakura Taisen (Saturn) — font palette patch for the ADV dialogue engine.

  Standalone Lua codec for Ludared.  No external dependencies.

  WHY THIS EXISTS
  ---------------
  Every text engine in the game draws its glyphs from a 16-entry BGR555
  palette that lives inside the executable, not in the font file:

      index  0        background
      index  1..14    the glyph ramp
      index 15        the ink

  The Japanese font sheet is 16x16 art whose background is index 0 and whose
  ink is a *dark* index; the Japanese palette matches that, and leaves index 15
  = 0x7FFF (white) unused.

  The English font sheet (SAKURA1/0100KNJ.BIN, taken from the US release) was
  authored as dark glyphs on a white background, and the conversion tool moves
  the sheet's background colour into palette index 0 so the engine's
  background convention still holds.  That remaps the tiles: the background
  becomes index 0 and **the ink becomes index 15** (tile value 0xF is about 17%
  of all ink pixels — letter bodies, not highlights).

  With the Japanese palette still in place index 15 is white, so letter bodies
  render white with grey edges and the text looks hollow, thin and fragmented
  even though the glyph data is perfect.  It is a palette bug, not a font bug.
  The shipped US build replaces both text palettes with the one that belongs to
  the sheet:

      7FFF 14A5 1CE7 2529 294A 318C 35AD 4210 4631 5294 5AD6 5EF7 6739 6F7B 77BD 0C63
      (index 15 = 0x0C63, near black)

  Confirmed two independent ways: it is what the US-patched executable holds at
  these offsets, and it is byte for byte the palette stored in the tool's own
  Data/8x12_SLG.bmp, the sheet its font conversion is built from.

  These values are not free parameters.  If the font sheet ever changes, this
  palette has to be regenerated from it.

  WHERE
  -----
  Two palettes, 32 bytes each, always adjacent:

      dialogue text palette, then choice (LIPS) text palette

  They sit at one of two known placements in the file:

      0x53954 / 0x53974
      0x53A8C / 0x53AAC      (the first + 0x138; where the disc-2 build keeps
                              the same pair, alongside every other disc-2
                              offset shift the original tool uses)

  The Japanese choice palette is a pink ramp — choices were drawn in pink.  The
  US build overwrites it with the same grey palette as the dialogue text, so
  choice text uses the same solid font.  That is reproduced here deliberately.

  IDENTIFICATION
  --------------
  The codec keys on the bytes at those windows and nothing else: no file name,
  no file size, no disc flag.  It scores each placement by how many of its two
  windows read a value it knows (pristine or already patched) and takes the
  better one; the placement is decided by content, so a disc-2 image is
  recognised by where the palettes are, not by what the file is called.

  PATCH CODEC SHAPE
  -----------------
  `decode` emits no artifacts; `encode` rewrites the buffer it is handed, so
  `encode(original, decode(original))` is the *patched* file, not the original.
  Intentional, and non-reversible in the CODEC_CONTRACT.md §5 sense.

  Both windows must be exactly the known pristine ramp or exactly the patched
  palette.  Anything else is a hard error rather than an overwrite, so a wrong
  revision or an already-differently-patched executable is reported instead of
  corrupted.  Running twice is safe.

  The SLG engine's palettes are scripts/SLG/patch_palette.lua.
]]

local codec = {}

codec.name        = "Sakura Taisen Font Palette (ADV)"
codec.description = "Replaces the ADV dialogue and choice text palettes in the "
                 .. "Sakura Taisen (Saturn) executable with the palette of the "
                 .. "US 8x12 font sheet, whose ink is palette index 15. Emits "
                 .. "no artifacts."
codec.version     = 1
codec.kind        = "patch"

local LABEL = "font palette (ADV)"

local function script_dir()
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then
    return src:sub(2):match("^(.*)[/\\][^/\\]*$") or "."
  end
  return "."
end

local function load_shared(name)
  if LUDARED and LUDARED.SCRIPTS then
    return dofile(LUDARED.SCRIPTS .. "/shared/" .. name .. ".lua")
  end
  return dofile(script_dir() .. "/../shared/" .. name .. ".lua")
end

local palettes = load_shared("palettes")
local args     = load_shared("args_parser")

-- ---------------------------------------------------------------------------
-- Palettes, as hex byte strings (Saturn BGR555, big endian per entry)
-- ---------------------------------------------------------------------------

-- What the translated sheet needs: index 0 = 0x7FFF (white background), a grey
-- ramp, index 15 = 0x0C63 (near-black ink).  Both sites get the same colours
-- today; the two names keep the doors open for a separate choice palette.
local I18N_DIALOGUE = palettes.hex("adv_dialogue_i18n")
local I18N_LIPS     = palettes.hex("adv_lips_i18n")

-- The Japanese dialogue palette: a grey ramp whose last entry is white.
local JP_DIALOGUE = palettes.hex("adv_dialogue_jp")

-- The Japanese choice (LIPS) palette: pink, sharing the low half of the ramp.
local JP_LIPS = palettes.hex("adv_lips_jp")

local PALETTE_BYTES = 32
local STRIDE        = 0x20  -- the two palettes are adjacent

local function bytes(hex)
  local out = {}
  for i = 1, #hex, 2 do out[#out + 1] = string.char(tonumber(hex:sub(i, i + 1), 16)) end
  return table.concat(out)
end

-- The two placements, as bases.  { base, base + STRIDE }.  The offset shift is
-- SakuraTaisen.cpp's: FixupSakura picks 0x53954 on disc 1 and 0x53A8C on disc 2,
-- +0x138, and nothing in the file says which disc it came from -- hence the
-- required `cd` argument instead of a guess.
local PLACEMENTS = { ["1"] = 0x53954, ["2"] = 0x53A8C }
local PLACEMENT_ORDER = { "1", "2" }

local ARG_SPEC = {
  cd = { values = { "1", "2" }, required = true },
}

local function sites_for(base)
  return {
    { base,              bytes(JP_DIALOGUE), bytes(I18N_DIALOGUE), "dialogue text palette" },
    { base + STRIDE,     bytes(JP_LIPS),     bytes(I18N_LIPS),     "choice (LIPS) text palette" },
  }
end

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
  local lines, shown = {}, 0
  for _, site in ipairs(sites) do
    lines[#lines + 1] = string.format("  0x%06X (%s) %s",
      site[1], site[4],
      site_state(data, site) and "matches"
        or ("wants " .. hex(site[2]) .. " or " .. hex(site[3])
            .. ", found " .. hex(data:sub(site[1] + 1, site[1] + #site[2]))))
    shown = shown + 1
  end
  return table.concat(lines, "\n")
end

-- Scores each placement by how many of its windows read a known value, and
-- returns the better one.  score == 0 means no placement is this codec's
-- business, and the site list is nil.
local function detect(data)
  local bestSites, bestScore, bestDisc
  local scores = {}

  for _, disc in ipairs(PLACEMENT_ORDER) do
    local base = PLACEMENTS[disc]
    local sites = sites_for(base)
    local score = 0
    for _, site in ipairs(sites) do
      if site_state(data, site) then score = score + 1 end
    end
    scores[#scores + 1] = string.format("cd=%s 0x%06X %d/%d", disc, base, score, #sites)
    if not bestScore or score > bestScore then
      bestSites, bestScore, bestDisc = sites, score, disc
    end
  end

  local detail = table.concat(scores, ", ")
  if bestScore == 0 then return nil, 0, detail end
  return bestSites, bestScore, detail, bestDisc
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

local function fail_disc(stage, data, sites, disc)
  local _, _, detail, best = detect(data)
  local hint
  if best and best ~= disc then
    hint = string.format("\n  the file looks like cd=%s; check the cd argument", best)
  elseif not best then
    hint = "\n  neither placement holds a known palette"
  end
  error(string.format(
    "%s: %s: cd=%s expects the palettes at 0x%06X; found:\n%s%s\n  both placements: %s",
    LABEL, stage, disc, PLACEMENTS[disc], report(data, sites), hint, detail), 0)
end

local function parse_cd(raw, stage)
  local opts = args.parse(raw, ARG_SPEC, LABEL .. ": " .. stage)
  return opts.cd
end

-- ---------------------------------------------------------------------------
-- Codec
-- ---------------------------------------------------------------------------

function codec.can_handle(data)
  if type(data) ~= "string" then return "no" end

  local sites, score = detect(data)
  if score == 0 then return "no" end
  if score == #sites then return "certain" end
  return "possible"
end

function codec.decode_name(args)
  return "palette"
end

function codec.decode(data, args)
  if type(data) ~= "string" then error(LABEL .. ": decode: expected binary string", 0) end

  local disc = parse_cd(args, "decode")
  local sites = sites_for(PLACEMENTS[disc])
  for _, site in ipairs(sites) do
    if not site_state(data, site) then fail_disc("decode", data, sites, disc) end
  end

  apply(data, sites, "decode")
  return {}
end

function codec.encode(original, artifacts, args)
  if type(original) ~= "string" then
    error(LABEL .. ": encode: expected binary string for `original`", 0)
  end

  local disc = parse_cd(args, "encode")
  local sites = sites_for(PLACEMENTS[disc])
  for _, site in ipairs(sites) do
    if not site_state(original, site) then fail_disc("encode", original, sites, disc) end
  end

  return apply(original, sites, "encode")
end

return codec
