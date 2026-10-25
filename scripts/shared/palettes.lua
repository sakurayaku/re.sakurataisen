--[[
  Named 16-entry BGR555 palettes for Sakura Taisen's ADV text engine.

  Each value is 32 bytes of big-endian BGR555 pairs -- 7FFF is white, 0842 is
  near-black -- exactly as the game stores them.  Nothing here is computed.

  Two roles per site, and two sites:

      dialogue   the text of a conversation line
      lips       the choice window (the "<LIPS>" lines)

  The *_jp values are what a Japanese executable holds; the *_i18n values are
  what the patched build writes over them.  Both sides are needed: the palette
  codec compares each site against its pristine and its patched value to decide
  what it is looking at, so the JP bytes are data, not documentation.  Drop one
  and a pristine Japanese executable stops being recognised.

  Consumers:

    scripts/SAKURA/patch_font_palette.lua   both roles, both sides
    scripts/main_menu_gfx.lua               adv_dialogue_i18n, as the display
                                            palette for the MAINMENU/*.bmp
                                            labels only

  There is no dependency tracking in Ludared: editing a value here does not
  change any codec's version, so bump the consumers that read it.  It also
  changes what those codecs accept as pristine, and their site checks will then
  refuse real executables until the new value is what the disc holds.
]]

local M = {}

-- Used in:
--  - game dialogue text, the pristine site of a Japanese build
--    (SAKURA 0x53954 on disc 1, 0x53A8C on disc 2)
--  - recognised only; never written
M.adv_dialogue_jp = "7fff0842108418c62108294a318c39ce42104a5252945ad663186b5a739c7fff"

-- Used in:
--  - choice (LIPS) window text, the pristine site of a Japanese build
--    (SAKURA 0x53974 on disc 1, 0x53AAC on disc 2)
--  - recognised only; never written
M.adv_lips_jp = "7fff08420842108418c62108294a318c39ce3dd041d245d449d64dd851da55dd"

-- Used in:
--  - game dialogue text after patching (the i18n font sheet's ink is index 15)
--  - the MAINMENU/nn_*.bmp labels, as a display palette: it colours the index
--    values in the editor and never reaches any file
M.adv_dialogue_i18n = "7fff14a51ce72529294a318c35ad4210463152945ad65ef767396f7b77bd0c63"

-- Used in:
--  - choice (LIPS) window text after patching
--  - provisional: the translated build writes one palette to both sites, so
--    this currently repeats adv_dialogue_i18n.  Give it its own value only if a
--    build ever needs the choice window to differ from the dialogue text.
M.adv_lips_i18n = "7fff14a51ce72529294a318c35ad4210463152945ad65ef767396f7b77bd0c63"

-- The SLG engine keeps its own text palettes (SLG.BIN / 0SLG.BIN), and they are
-- separate entries even where the bytes currently match the ADV ones: the two
-- engines are patched by different codecs and may diverge.

-- Used in:
--  - SLG dialogue text, pristine (0x0158A4)
M.slg_dialogue_jp = "7fff0842108418c62108294a318c39ce42104a5252945ad663186b5a739c7fff"

-- Used in:
--  - SLG choice window text, pristine (0x0158C4)
M.slg_lips_jp = "7fff08420842108418c62108294a318c39ce3dd041d245d449d64dd851da55dd"

-- Used in:
--  - SLG dialogue text after patching.  The SLG loader masks every byte with
--    0x7F, so its codec applies mask_7f() to this value before writing.
M.slg_dialogue_i18n = "7fff14a51ce72529294a318c35ad4210463152945ad65ef767396f7b77bd0c63"

-- Used in:
--  - SLG choice window text after patching (masked the same way)
--  - provisional: the translated build writes one palette to both sites, so
--    this currently repeats slg_dialogue_i18n.
M.slg_lips_i18n = "7fff14a51ce72529294a318c35ad4210463152945ad65ef767396f7b77bd0c63"

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
