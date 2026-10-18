--[[
  Sakura Taisen (Saturn) — 8px glyph layout patch for the SLG text engine.

  Standalone Lua codec for Ludared.  No external dependencies.

  WHAT IT CHANGES
  ---------------
  The SLG engine (battle and menu text) lays out glyphs the same way the ADV
  engine does: 16 px advance, 16 px line pitch, 240 px of line, a 48 px box.
  The English release redrew the font sheet as 8x12 art and patched the engine:

      glyph advance X   16 -> 8 px   (dialogue, scrolling and choice menu)
      line pitch    Y   16 -> 12 px
      line capacity     15 -> 30 characters (240 px / 8), with the buffer
                              constants one below it at 14 -> 29
      line count         3 -> 4 lines (48 px / 12), stored as maxLines - 1

  The advanced-ADV layout is a separate codec (scripts/SAKURA/patch_8px_font.lua)
  and the glyph *appearance* — the palette — is
  scripts/SLG/patch_palette.lua.  Each codec patches one thing in one engine.

  DELIBERATELY NOT APPLIED
  ------------------------
  The English build also patches bytes in these routines that belong to its
  one-byte-per-glyph string ABI (USE_SINGLE_BYTE_LOOKUPS / USE_4_BYTE_OFFSETS
  in the original tool):

      0x021765, 0x021799   shll2 r1 -> shll r1, the choice menu string stride.
                           Two characters are 4 bytes when a code is 2 bytes
                           and 2 bytes when it is 1 byte, so this pair follows
                           the ABI switch, not the layout.

  This project writes glyph codes as the u16 the original Japanese files use,
  so a 2-byte stride is the correct one here and those writes must stay
  untouched.  Applying them would desynchronise choice (LIPS) text.

  IDENTIFICATION
  --------------
  The codec keys on the bytes at its own sites and nothing else: no file name,
  no file size, no container knowledge.  Each disc ships two byte-identical
  copies of this engine; nothing here distinguishes them, because bytes are
  bytes.

  PATCH CODEC SHAPE
  -----------------
  `decode` emits no artifacts; `encode` rewrites the buffer it is handed, so
  `encode(original, decode(original))` is the *patched* file, not the original.
  That is intentional, and is why this codec is non-reversible in the
  CODEC_CONTRACT.md §5 sense.  `decode` still validates the input, so a node
  registered against the wrong artifact fails at decode time.

  Running twice is safe: a site already holding its patched value is left
  alone.  A site holding any third value is a hard error naming the offset, so
  an already-differently-modified executable is reported rather than
  overwritten.

  Verified byte for byte against the pristine SLG.BIN (all seventeen sites read
  their expected 0x10/0x0F/0x0E/0x02/0xCC) and against the shipped US-patched
  executable (all seventeen hold exactly the values written here).
]]

local codec = {}

codec.name        = "Sakura Taisen 8px Layout (SLG)"
codec.description = "Patches the Sakura Taisen (Saturn) SLG text engine so "
                 .. "glyphs advance 8px with a 12px line pitch instead of "
                 .. "16px, and widens the line/buffer constants to match. "
                 .. "Emits no artifacts."
codec.version     = 1
codec.kind        = "patch"

local LABEL = "8px layout (SLG)"

-- ---------------------------------------------------------------------------
-- The write list.  { file offset, pristine, patched, what }.  Values may be
-- written as byte numbers or as byte strings.
-- ---------------------------------------------------------------------------

local SITES = {
  { 0x021655, 0x0F, 0x1E, "line capacity, 240px / 8px" },
  { 0x02165D, 0x10, 0x0C, "line pitch, dialogue text" },
  { 0x02167B, 0x10, 0x08, "glyph advance, dialogue text" },
  { 0x02173D, 0xCC, 0xCE, "choice menu start row" },
  { 0x021755, 0x0F, 0x1E, "choice menu line capacity (a)" },
  { 0x02178B, 0x0F, 0x1E, "choice menu line capacity (b)" },
  { 0x0217B9, 0x0F, 0x1E, "choice menu characters per line (a)" },
  { 0x0217BF, 0x0F, 0x1E, "choice menu characters per line (b)" },
  { 0x021809, 0x10, 0x08, "choice menu glyph advance" },
  { 0x0218E1, 0x10, 0x0C, "line pitch, scrolling text" },
  { 0x0218EB, 0x0F, 0x1E, "line capacity, scrolling text" },
  { 0x021903, 0x10, 0x08, "glyph advance, scrolling text" },
  { 0x021963, 0x0E, 0x1D, "scroll buffer line capacity (a)" },
  { 0x02196B, 0x0E, 0x1D, "scroll buffer line capacity (b)" },
  { 0x02196D, 0x02, 0x03, "scroll buffer line count (a)" },
  { 0x021975, 0x02, 0x03, "scroll buffer line count (b)" },
  { 0x021981, 0x0F, 0x1E, "scroll buffer characters per line" },
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
