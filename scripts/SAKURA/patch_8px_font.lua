--[[
  Sakura Taisen (Saturn) — 8px glyph layout patch for the ADV dialogue engine.

  Standalone Lua codec for Ludared.  No external dependencies.

  WHAT IT CHANGES
  ---------------
  The Japanese release draws ADV text with 16x16 font tiles and steps the text
  cursor 16 px per glyph, so a 48 px box holds three 16 px lines of 15
  characters (240 px / 16).  The English release redrew the font sheet as 8x12
  art inside the same 16x16 tiles and patched the *engine* to step 8 px with a
  12 px line pitch:

      glyph advance X   16 -> 8 px
      line pitch    Y   16 -> 12 px
      line capacity     15 -> 30 characters (240 px / 8)
      box capacity       3 -> 4 lines (48 px / 12)

  Those numbers are immediates inside the SH-2 text routines, not anything the
  font file controls.  Swapping the font sheet alone therefore changes glyph
  shapes and leaves the layout — the gappy "A s  a  s p e c i a l" line, the
  fourth line falling out of the box — exactly as it was.

  Glyph *appearance* is a different concern with its own codec
  (scripts/SAKURA/patch_font_palette.lua), as is the SLG engine's layout
  (scripts/SLG/patch_8px_font.lua).  Each codec patches one thing in one
  engine.

  DELIBERATELY NOT APPLIED
  ------------------------
  The English build also patches bytes in these routines that belong to its
  one-byte-per-glyph string ABI (USE_SINGLE_BYTE_LOOKUPS / USE_4_BYTE_OFFSETS
  in the original tool):

      0x0104B6, 0x0104C6   mov.w -> mov.b character reads
      0x010612, 0x010646   shll2 r1 -> shll r1, the string stride.  Two
                           characters are 4 bytes when a code is 2 bytes and
                           2 bytes when it is 1 byte, so this pair follows the
                           ABI switch, not the layout.

  This project writes glyph codes as the u16 the original Japanese files use,
  so a 2-byte stride is the correct one here and those writes must stay
  untouched.  Applying them would desynchronise choice (LIPS) text.

  IDENTIFICATION
  --------------
  The codec keys on the bytes at its own seven sites and nothing else: no file
  name, no file size, no container knowledge.  A file is this codec's business
  when every site reads either its pristine or its already-patched value.

  PATCH CODEC SHAPE
  -----------------
  `decode` emits no artifacts; `encode` rewrites the buffer it is handed, so
  `encode(original, decode(original))` is the *patched* file, not the original.
  That is intentional, and is why this codec is non-reversible in the
  CODEC_CONTRACT.md §5 sense.  `decode` still validates the input, so a node
  registered against the wrong artifact fails at decode time.

  Running twice is safe: a site already holding its patched value is left
  alone.  A site holding any third value is a hard error naming the offset, so
  a wrong disc or an already-differently-modified executable is reported rather
  than overwritten.

  Verified byte for byte against the pristine disc-1 SAKURA (all seven sites
  read their expected 0x10/0xCC/0xC4) and against the shipped US-patched
  executable (all seven hold exactly the values written here).
]]

local codec = {}

codec.name        = "Sakura Taisen 8px Layout (ADV)"
codec.description = "Patches the Sakura Taisen (Saturn) ADV dialogue engine so "
                 .. "glyphs advance 8px with a 12px line pitch instead of "
                 .. "16px, matching the US 8x12 font sheet. Emits no artifacts."
codec.version     = 1
codec.kind        = "patch"

local LABEL = "8px layout (ADV)"

-- ---------------------------------------------------------------------------
-- The write list.  { file offset, pristine, patched, what }.  Values may be
-- written as byte numbers or as byte strings.
-- ---------------------------------------------------------------------------

local SITES = {
  { 0x0104D7, 0x10, 0x0C, "line pitch, dialogue text" },
  { 0x0104E5, 0x10, 0x08, "glyph advance, dialogue text" },
  { 0x0105FB, 0xCC, 0xCE, "choice menu start row, two-option list" },
  { 0x010603, 0xC4, 0xC6, "choice menu start row, three-option list" },
  { 0x01066B, 0x10, 0x08, "glyph advance, choice (LIPS) text" },
  { 0x010733, 0x10, 0x0C, "line pitch, secondary text renderer" },
  { 0x010747, 0x10, 0x08, "glyph advance, secondary text renderer" },
}

-- ---------------------------------------------------------------------------
-- Site machinery
-- ---------------------------------------------------------------------------

for _, site in ipairs(SITES) do
  if type(site[2]) == "number" then site[2] = string.char(site[2]) end
  if type(site[3]) == "number" then site[3] = string.char(site[3]) end
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
  return "8px_font"
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
