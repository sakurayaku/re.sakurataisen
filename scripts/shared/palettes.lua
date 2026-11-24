--[[
  Named 16-entry BGR555 palettes for Sakura Taisen's ADV and SLG text engines.

  Each value is 32 bytes of big-endian BGR555 pairs -- 7FFF is white, 0842 is
  near-black -- exactly as the game stores them.  Nothing here is computed.

  Two roles per site, and two sites:

      dialogue   the text of a conversation line
      lips       the choice window (the "<LIPS>" lines)

  adv_dialogue_jp appears at all of these offsets:

      SAKURA CD1 0x53954 / CD2 0x53A8C     dialogue text
      SAKURA CD1 0x5ADB8 / CD2 0x5AEF0     load/options label bank
      SLG.BIN + 0SLG.BIN 0x158A4           dialogue text
      SLG.BIN + 0SLG.BIN 0x4A1D8           load/options label bank
      LOGO.SH2 0xFE80                      main-menu module text

  The six 16-colour BMP codecs have no file offset for it: they all display
  adv_dialogue_jp_for_bmp, this ramp with index 15 forced red.  None writes it
  back.

  Each value below lists the file offsets where it is found.  No codec patches
  these bytes: edit the hex string here to change the palette.  Ludared does not
  track dependencies, so bump the version of any codec whose display changes.
]]

local M = {}

-- Used at every adv_dialogue_jp offset listed above; reference only, never
-- written.
M.adv_dialogue_jp = "7fff0842108418c62108294a318c39ce42104a5252945ad663186b5a739c7fff"

-- Used in:
--  - choice (LIPS) window text, the pristine site of a Japanese build
--    (SAKURA 0x53974 on disc 1, 0x53AAC on disc 2)
--  - reference only; never written
M.adv_lips_jp = "7fff08420842108418c62108294a318c39ce3dd041d245d449d64dd851da55dd"

-- Display-only BMP copy of adv_dialogue_jp: index 15 is bright red (BGR555
-- 0x001F) instead of retail white.  BMP codecs convert it with bmp.from_bgr555.
M.adv_dialogue_jp_for_bmp = "7fff0842108418c62108294a318c39ce42104a5252945ad663186b5a739c001f"

-- The SLG engine keeps its own text palettes (SLG.BIN / 0SLG.BIN), and they are
-- separate entries even where the bytes currently match the ADV ones: the two
-- engines' sites are recorded separately and may diverge.

-- Used in:
--  - SLG dialogue text, pristine (0x0158A4)
M.slg_dialogue_jp = "7fff0842108418c62108294a318c39ce42104a5252945ad663186b5a739c7fff"

-- Used in:
--  - SLG choice window text, pristine (0x0158C4)
M.slg_lips_jp = "7fff08420842108418c62108294a318c39ce3dd041d245d449d64dd851da55dd"

local raw_cache = {}

local function hex_of(name)
  local value = M[name]
  if type(value) ~= "string" then
    error("palettes: unknown palette '" .. tostring(name) .. "'", 2)
  end
  if #value ~= 64 then
    error(string.format("palettes: '%s' is %d hex digits, expected 64", name, #value), 2)
  end
  return value
end

-- The palette as a hex string, the form the executable patch compares against.
function M.hex(name)
  return hex_of(name)
end

-- The palette as a 32-byte binary string.
function M.raw(name)
  local cached = raw_cache[name]
  if cached then return cached end

  local value = hex_of(name)
  local out = {}
  for i = 1, #value, 2 do
    out[#out + 1] = string.char(tonumber(value:sub(i, i + 1), 16))
  end
  cached = table.concat(out)
  raw_cache[name] = cached
  return cached
end

return M
