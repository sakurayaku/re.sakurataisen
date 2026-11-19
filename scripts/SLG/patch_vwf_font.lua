--[[
  Sakura Taisen (Saturn) — packed-u16 variable-width layout for SLG.BIN.

  Each text glyph remains one big-endian u16: (glyph_id << 8) | advance.
  The SLG renderer still receives a sequential cache-tile index; the cache
  loader extracts the glyph ID, while dialogue, LIPS and scrolling loops use
  the low byte to move their X cursor.

  The text box is 240 px wide with a 12 px pitch and four lines.  The cache
  supports 60 glyphs per line, enough for the 4 px minimum advance in the font
  tables.  Narrower advances are still capped at 60 glyphs by the producer.
  The cache therefore occupies 60 * 4 * 0x80 bytes from 0x25C43600.  This is
  an experimental reuse of transient attack-effect VRAM: do not draw text while
  an attack animation still needs that data.  The old base at 0x25C16480
  overlaps persistent battle graphics.

  This replaces the fixed 8 px layout codec; do not apply both.
]]

local codec = {}

codec.name        = "Sakura Taisen VWF Layout (SLG)"
codec.description = "Patches the SLG engine for packed-u16 variable-width glyphs, "
                 .. "240px lines and four 12px rows. Emits no artifacts."
codec.version     = 1
codec.kind        = "patch"

local LABEL = "VWF layout (SLG)"
local OLD_CACHE_BASE = "25C16480"
local CACHE_BASE = "25C43600"

-- { file offset, pristine bytes, patched bytes, description }
local SITES = {
  -- Keep renderer reads and cache-loader writes on the same cache allocation.
  { 0x021590, OLD_CACHE_BASE, CACHE_BASE, "renderer cache base" },
  { 0x0219C4, OLD_CACHE_BASE, CACHE_BASE, "glyph-loader cache destination" },

  -- The ADV renderer shifts every glyph left by 4 px. Apply the same bias to
  -- SLG after its X coordinate is prepared, while retaining both descriptor
  -- stores by folding the old +0x0E Y offset into the X-field pointer update.
  { 0x02153A, "2141", "74FC", "shared glyph renderer X -= 4px" },
  { 0x02153C, "61E3", "2141", "shared glyph renderer store biased X" },
  { 0x02153E, "710E", "7102", "shared glyph renderer advance to Y field" },

  -- Dialogue: preserve the packed u16 for newline comparison, extract advance,
  -- and use the JSR delay slot after X has been latched by the glyph caller.
  { 0x021654, "E10F", "E13C", "dialogue cache-row stride, 60 glyphs", "E11E" },
  { 0x02165C, "7C10", "7C0C", "dialogue line pitch, 12px" },
  { 0x02164E, "611D", "601C", "dialogue advance = low byte" },
  { 0x021676, "666D", "390C", "dialogue X += advance in call delay slot" },
  { 0x02167A, "7910", "0009", "dialogue remove fixed X advance", "7908" },
  { 0x0216A4, "0A0D", "000D", "dialogue packed-format newline" },

  -- LIPS pass 1 sums pixel advances in its per-line u16 counters.
  { 0x0216F6, "611D", "601C", "LIPS measure advance = low byte" },
  { 0x021708, "7101", "310C", "LIPS width counter += advance" },

  -- Initialize four width counters in the existing 0x18-byte stack frame.
  { 0x0216D2, "2EA1", "2EA2", "LIPS clear first two width counters" },
  { 0x0216D6, "7102", "7104", "LIPS address next pair of counters" },
  { 0x0216D8, "E300", "21A2", "LIPS clear final two width counters" },
  { 0x0216DA, "2131", "0009", "LIPS counter initialization nop" },
  { 0x0216DC, "61E3", "0009", "LIPS counter initialization nop" },
  { 0x0216DE, "7104", "0009", "LIPS counter initialization nop" },
  { 0x0216E0, "21A1", "0009", "LIPS counter initialization nop" },

  -- Center each LIPS row from its measured pixel width. The glyph routine
  -- shifts -4px, so X = 12 - width / 2 keeps the visible row centered.
  { 0x021754, "E20F", "EA0C", "LIPS first-row centering base", "E21E" },
  { 0x021756, "6A23", "61E1", "LIPS load first-row pixel width" },
  { 0x021758, "E316", "611D", "LIPS zero-extend first-row width" },
  { 0x02175A, "61E1", "4101", "LIPS halve first-row width" },
  { 0x02175C, "33EC", "E316", "LIPS first-row cursor address" },
  { 0x02175E, "611D", "33EC", "LIPS first-row cursor address" },
  { 0x021762, "61A3", "23A1", "LIPS store centered first-row X" },
  { 0x021764, "4108", "0009", "LIPS first-row centering nop" },
  { 0x021766, "311C", "0009", "LIPS first-row centering nop" },
  { 0x021768, "7190", "0009", "LIPS first-row centering nop" },
  { 0x02176A, "2311", "0009", "LIPS replace old first-row X store" },

  { 0x02178A, "EA0F", "0009", "LIPS next-row centering nop", "EA1E" },
  { 0x021794, "3A18", "4101", "LIPS halve next-row width" },
  { 0x021796, "61A3", "E20C", "LIPS next-row centering base" },
  { 0x021798, "4108", "3218", "LIPS subtract half-width from base" },
  { 0x02179A, "311C", "2321", "LIPS store centered next-row X" },
  { 0x02179C, "7190", "0009", "LIPS next-row centering nop" },
  { 0x02179E, "2311", "0009", "LIPS next-row centering nop" },

  -- Keep the row stride live through the glyph-index calculation, move the
  -- renderer pointer to r3, and retain the advance in callee-saved r10.
  { 0x0217B8, "EA0F", "EA3C", "LIPS first draw-path cache-row stride", "EA1E" },
  { 0x0217BE, "E30F", "E33C", "LIPS second draw-path cache-row stride", "E31E" },
  { 0x021778, "9230", "9030", "LIPS newline literal destination" },
  { 0x02177A, "611D", "621C", "LIPS retain packed u16 and extract advance" },
  { 0x02177C, "3120", "3100", "LIPS compare packed u16 with newline" },
  { 0x0217D2, "DA04", "D304", "LIPS renderer pointer in r3" },
  { 0x0217D4, "4A0B", "430B", "LIPS call renderer through r3" },
  { 0x0217D6, "666D", "6A23", "LIPS preserve advance in r10" },
  { 0x0217FE, "666D", "6A23", "LIPS preserve advance in r10" },
  { 0x021802, "EA16", "E316", "LIPS cursor address after draw" },
  { 0x021804, "3AEC", "33EC", "LIPS cursor address after draw" },
  { 0x021806, "63A1", "6131", "LIPS load current X after draw" },
  { 0x021808, "7310", "31AC", "LIPS X += advance", "7308" },
  { 0x02180A, "2A31", "2311", "LIPS store updated X" },
  { 0x0217DC, "0A0D", "000D", "LIPS packed-format newline" },

  -- Scrolling renderer: keep the packed u16 for controls and advance X in the
  -- JSR delay slot after the current X has been copied to r4.
  { 0x0218D0, "011D", "021D", "scroll read packed u16 into r2" },
  { 0x0218D2, "621D", "602C", "scroll advance = low byte" },
  { 0x0218E0, "7C10", "7C0C", "scroll line pitch, 12px" },
  { 0x0218EA, "E10F", "E13C", "scroll cache-row stride, 60 glyphs", "E11E" },
  { 0x0218F6, "D00D", "D30D", "scroll renderer pointer in r3" },
  { 0x0218FC, "400B", "430B", "scroll call renderer through r3" },
  { 0x0218FE, "666D", "390C", "scroll X += advance in call delay slot" },
  { 0x021902, "7910", "0009", "scroll remove fixed X advance", "7908" },
  { 0x021926, "0A0D", "000D", "scroll packed-format newline" },

  -- Cache population decodes the high byte as glyph ID.  Four rows of 60
  -- glyphs use a linear 240-tile cache.
  { 0x021962, "E10E", "E13B", "cache glyph comparison limit, 60 per row", "E11D" },
  { 0x02196A, "E80E", "E83B", "cache glyph clamp value, 60 per row", "E81D" },
  { 0x02196C, "E102", "E103", "cache line clamp comparison, four rows" },
  { 0x021972, "6133", "4319", "cache glyph ID = packed u16 >> 8" },
  { 0x021974, "E902", "E903", "cache line clamp value, four rows" },
  { 0x021976, "71FF", "6133", "cache glyph ID without subtract-one" },
  { 0x021980, "E10F", "E13C", "cache row stride, 60 glyphs", "E11E" },
  { 0x0219B8, "0A0D", "000D", "cache packed-format newline" },
  { 0x0219C0, "002CE800", "002CE780", "cache source base for 1-based glyph IDs" },
}

local function fromhex(value)
  return (value:gsub("%x%x", function(byte)
    return string.char(tonumber(byte, 16))
  end))
end

for _, site in ipairs(SITES) do
  site[2], site[3] = fromhex(site[2]), fromhex(site[3])
  if site[5] then site[5] = fromhex(site[5]) end
end

local function hex(data)
  local bytes = {}
  for i = 1, #data do bytes[i] = string.format("%02x", data:byte(i)) end
  return table.concat(bytes)
end

local function state(data, site)
  local current = data:sub(site[1] + 1, site[1] + #site[2])
  if current == site[2] then return "pristine" end
  if current == site[3] then return "patched" end
  if site[5] and current == site[5] then return "fixed-8px" end
end

local function detect(data)
  local score = 0
  for _, site in ipairs(SITES) do
    if state(data, site) then score = score + 1 end
  end
  return score
end

local function apply(data, stage)
  local out = data
  for _, site in ipairs(SITES) do
    local offset, before, after, description = site[1], site[2], site[3], site[4]
    local current = out:sub(offset + 1, offset + #before)
    if current == before or (site[5] and current == site[5]) then
      out = out:sub(1, offset) .. after .. out:sub(offset + #before + 1)
    elseif current ~= after then
      error(string.format(
        "%s: %s: 0x%06X (%s) found %s; expected %s, %s%s",
        LABEL, stage, offset, description, hex(current), hex(before), hex(after),
        site[5] and (", or " .. hex(site[5])) or ""), 0)
    end
  end
  return out
end

function codec.can_handle(data)
  if type(data) ~= "string" then return "no" end
  local score = detect(data)
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
  if args ~= nil and args ~= "" then
    error(LABEL .. ": this codec takes no arguments", 0)
  end
  if type(data) ~= "string" or detect(data) == 0 then
    error(LABEL .. ": decode: input does not match SLG.BIN", 0)
  end
  apply(data, "decode")
  return {}
end

function codec.encode(original, artifacts, args)
  if args ~= nil and args ~= "" then
    error(LABEL .. ": this codec takes no arguments", 0)
  end
  if type(original) ~= "string" or detect(original) == 0 then
    error(LABEL .. ": encode: input does not match SLG.BIN", 0)
  end
  return apply(original, "encode")
end

return codec
