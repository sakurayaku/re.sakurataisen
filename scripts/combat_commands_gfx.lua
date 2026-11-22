--[[
  Sakura Taisen (Saturn) — Combat commands

  PATCH plugin for SAKURA2/WKL*.BIN — both halves of ExtractWKLFiles
  (SakuraTaisen.cpp:7685) and PatchWKLFiles (:6668):

    * COMBAT  the battle-menu command art: frame, cursor, command labels,
              number glyphs (the uncompressed "Misc_*" blocks).
    * NAMES   character names and special-move names, in the 64 PRS-compressed
              blocks (the "<index>_<offset>" images).

  ## Layout it reads

      0x000  Entry[98] of { u32 BE offset; u32 BE size }  the file's block list
      0x0E8  u32 BE -> battle-menu block table, inside this file
      0x0EC  u32 BE -> that table's total byte size (table + blocks)
      0x100  u32 BE -> the 64-entry compressed table, inside this file
             the size of that table's section is the header entry at 0x100

  Battle-menu table, { u32 BE offsetFromTable; u32 BE size } per block, offsets
  relative to the table address.  A block is

      u16 BE count
      6 bytes, zero at retail
      count x { u32 offsetFromHeader; u32 offsetFromPreviousImage;
                u16 width; u16 height; u32 unknown }
      u32 lastImageOffsetFromHeader; u32 lastImageSize
      4bpp pixels at dataStart + offsetFromHeader + offsetFromPreviousImage,
      dataStart = block + 8 + 16*count + 8

  offsetFromHeader is where the *previous* image starts (0 for the first two),
  offsetFromPreviousImage is its byte length, so the two sum to the image's own
  offset.  The trailing pair describes the last image the same way.  `unknown`
  is a per-image flag (0x560, 0x570, 0x30 in the shipping files) and is kept.

  Compressed table: 64 x { u32 BE offsetFromTable; u32 BE size }, offsets
  relative to the table address, which is followed immediately by the streams.
  An empty entry carries the running offset and a zero size.  Each stream
  decompresses to

      u16 BE count
      14 bytes
      count x { u16 width; u16 height; u16 u1; u2; u3;
                u16 offsetFromData; u16 u4; u16 byteCount }
      4bpp pixels at 0x10*(count+1) + offsetFromData

  The reserved fields (the 14 bytes, u1..u4) are preserved verbatim.

  ## The pool

  decode() is a NOP: nothing is extracted from a WKL.  The art is one pool for
  the whole disc, and encode() reads it:

      <workspace>/combat/commands/*.bmp    the command art and both sheets
      <workspace>/combat/names/*.bmp       the special-move names

  Command art is keyed by slot, because every WKL ships the same command art.
  Name art is not: the same slot holds different pictures in different WKLs, so
  each pristine image is hashed and the pool file is named for that sha256.
  NAME_FILES in this file points a hash at any file instead:

      ["f98df303...c80"] = "NAME_KANNA.bmp",

  A command image is looked up under its descriptive name first (MENU.bmp,
  SUBMENU_1_UN.bmp, UNIT_INFO.bmp, ...; see COMMAND_FILES) and under
  command_<block>_<image>.bmp second, so an older folder still reads.  A move
  name with no BMP in the pool keeps the untranslated art of the file being
  encoded, so a partial translation is fine.

  ## Sheets

  Some command images are drawn as one file instead of one BMP each, because
  they are text of the same kind and are easier to edit together.  A sheet is a
  plain BMP split into `cols` x `rows` equal cells; the cell size is the sheet
  size divided by the grid, and that cell becomes both the art and the size of
  every slot the sheet names.  A sheet wins over the individual BMP of the
  slots it names; slots it does not name keep their own BMP.

      CMD_MAIN.bmp        2 x 6 cells   the battle-menu main commands
      CMD_NAMES.bmp       2 x 12 cells  the commands behind them
      STATUS_NUMBERS.bmp  2 x 12 cells  block 9's digits and symbols
      BOTTOM_ARROW.bmp    1 x 12 cells  block 11's arrows
      NUMBERS_BIG.bmp     1 x 13 cells  block 7 images 0-12
      NUMBERS_SMALL.bmp   1 x 14 cells  block 7 images 13-26

  The sheet is one authored file for the whole disc and lives in the pool with
  the rest of the command art, so every WKL is rebuilt from the same cells and
  the metadata plugin can size the anchors from them.  Growing a cell therefore
  resizes the art everywhere, and the region grows once.

  WKL01 holds 206 images: 162 commands in 16 blocks and 44 move names in 11
  blocks.  Names are the C++ prefixes ("Misc_<block>_<image>",
  "<index>_<offset>") reindexed by block and image.

  ## Palette

  The 16 colours are 0SLG.BIN + 0x11B78, the palette PatchWKLFiles builds
  (`SakuraPalette(&slg[0x11B78], 32)`).  They are carried in the BMPs as a
  display ramp and never read back: the indices are what the game uploads.
  A palette-only edit is not a change.

  ## Dimensions

  Both groups may be resized — that is the point of this plugin, since French is
  wider than Japanese.  Width must be a multiple of 8 (VDP1 addresses the art in
  8-pixel columns and 4bpp rows are width/2 bytes), height at most 255 (one
  sprite),   and a compressed image's bytes at most 0xFFFF (the header's u16
  byteCount).  PatchWKLFiles enforces the same.

  A command image's byte size does not have to be a multiple of 8.  VDP1 names a
  texture by an 8-byte character address, so every image has to start on one; an
  image whose art is not a whole number of characters is padded with blank bytes
  to the next multiple of 8 when it is written.  Every retail image already lands
  on the boundary (16x16 = 128 bytes, 24x16 = 192, 40x48 = 960), while a 56x15
  label is 420 and takes four blank bytes.

  The padding is stored after the last row, and the sprite's height comes from
  the block header, so it is never drawn: the image still appears as its width x
  height.  The block's size fields and the region size count the padded length,
  which is also what keeps every region delta a multiple of 8 (the SLG anchors
  are stored in eighths).

  A resize rebuilds the region it lives in, relocates everything after it, and
  rewrites the 98-entry header.  Blocks and streams that did not change are
  copied verbatim, so an untouched file round-trips byte for byte.

  ## Budget

  The battle-menu region is exactly 0x117A0 bytes — a 128-byte table plus 71,456
  bytes of blocks — in all thirteen WKL files, and it is completely full.  Any
  net growth therefore moves the compressed section and everything after it, and
  the VDP1 anchors SLG.BIN / 0SLG.BIN hold for the command art with it:
  scripts/combat_commands_metadata.lua reads the same BMPs and shifts them.

  Growth of the command region is bounded by the VDP1 block at 0x25C49100 that
  PatchWKLFiles deliberately does not move: the highest anchor it shifts is
  0x25C2B600, so the delta may not exceed 0x1DB00 bytes (121,600).

  The compressed section has no such bound: PatchWKLFiles applies its delta to
  the WKL header only, never to SLG, and the names are not uploaded to fixed
  VDP1 addresses.

  SLG.BIN holds one set of anchors for every WKL.  Every WKL is rebuilt from the
  same pool, so they cannot disagree on the command dimensions.

  ## Never grows past the disc's slot

  This codec only changes the file it is given.  A bigger WKL has to fit the
  space the ISO layout leaves it, which is a build-time property, not something
  this codec can check.

  ## Round-tripping

  If no pixel changes, encode() returns the parent byte for byte; unchanged
  blocks, streams and the header entries that describe them are copied, not
  re-serialised.
]]

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
  return dofile(script_dir() .. "/shared/" .. name .. ".lua")
end

local bmp = load_shared("bmp")
local can_handle = load_shared("can_handle")
local prs = LUDARED.codec("std/sega/compression/prs")

local codec = {}

codec.name        = "Sakura Taisen Combat Commands"
codec.description = "PATCH plugin for the battle-menu command art and the special-move "
                 .. "names in SAKURA2/*.WKL, with dimension changes and region relocation"
codec.version     = 8
codec.kind        = "patch"

local LABEL = "combat_commands_gfx"

local MENU_POINTER   = 0x000E8
local MENU_SIZE      = 0x000EC
local MOVES_POINTER  = 0x00100
local HEADER_BYTES   = 0x00310
local HEADER_ENTRIES = HEADER_BYTES // 8            -- 98
local MOVES_ENTRIES  = 64

local MENU_PREFIX = 8
local MENU_INFO   = 16
local MENU_SUFFIX = 8
local MOVES_INFO  = 16

-- The command region's size at retail, identical in every WKL on the disc.
local RETAIL_REGION = 0x117A0
-- PatchWKLFiles shifts anchors as high as 0x25C2B600 and leaves the block at
-- 0x25C49100 where it is, so a larger delta would run the command art into it.
local MAX_GROWTH = 0x1DB00

-- 0SLG.BIN + 0x11B78; 16 BGR555 colours, copied from the retail file.
local PALETTE_HEX =
  "fef7eb5ace73a4e7a8a594a58000ad08c1d0c1eeb9b0b5adb98cad4bb98cb16b"

-- The retail command layout, used by scripts/combat_commands_metadata.lua to
-- size a rebuild from the BMPs alone.  Order: block 0 image 0, block 0 image 1,
-- ...  Verified identical in all thirteen WKL files.
local BLOCK_COUNTS = {
  34, 1, 1, 22, 8, 1, 8, 27, 5, 24, 4, 12, 1, 4, 6, 4,
}
local IMAGE_BYTES = {
  1536, 1920, 960, 1280, 1600, 128, 128, 192, 128, 128, 192, 192,
  192, 192, 192, 192, 128, 128, 192, 192, 192, 192, 192, 192,
  128, 192, 192, 192, 128, 192, 128, 128, 192, 192, 192, 576,
  3072, 13984, 64, 320, 128, 32, 64, 96, 128, 160, 192, 224,
  256, 32, 64, 96, 128, 160, 192, 224, 256, 320, 32, 64,
  96, 128, 160, 192, 224, 256, 576, 32, 64, 96, 128, 160,
  192, 224, 256, 64, 64, 64, 64, 64, 64, 64, 64, 64,
  64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64,
  64, 64, 64, 64, 64, 64, 576, 576, 576, 576, 576, 64,
  64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64,
  64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 256,
  256, 640, 64, 128, 128, 128, 128, 128, 128, 128, 128, 128,
  128, 128, 128, 11232, 576, 576, 2464, 576, 2912, 704, 704, 320,
  320, 320, 1792, 384, 384, 384,
}

local function hex_bytes(hex)
  local out = {}
  for i = 1, #hex, 2 do
    out[#out + 1] = string.char(tonumber(hex:sub(i, i + 1), 16))
  end
  return table.concat(out)
end

local PALETTE = bmp.from_bgr555(hex_bytes(PALETTE_HEX), 16)

local function u16(data, offset)
  if offset < 0 or offset + 2 > #data then
    error(string.format("%s: u16 at 0x%X is outside the file", LABEL, offset), 0)
  end
  return string.unpack(">I2", data, offset + 1)
end

local function u32(data, offset)
  if offset < 0 or offset + 4 > #data then
    error(string.format("%s: u32 at 0x%X is outside the file", LABEL, offset), 0)
  end
  return string.unpack(">I4", data, offset + 1)
end

-- The 98-entry header lists every block as { offset, size }.  A block that is
-- not the header itself has its size in the entry that shares its offset.
local function declared_size(data, base)
  local size
  for i = 0, HEADER_ENTRIES - 1 do
    local offset = u32(data, i * 8)
    local entry_size = u32(data, i * 8 + 4)
    if offset == base and entry_size ~= 0 then
      if size and size ~= entry_size then
        error(string.format("%s: two header entries give 0x%X different sizes", LABEL, base), 0)
      end
      size = entry_size
    end
  end
  return size
end

-- One authored BMP standing in for several command images.  `slots[row][col]`
-- is { block, image } or false for a cell the game has no art for.
local SHEETS = {
  {
    file = "CMD_MAIN.bmp",
    cols = 2,
    rows = 6,
    -- Column 1 is the ACTIVE label and column 2 the INACTIVE one.  Rows 4 and
    -- 5 name 情報 and 終, whose inactive cells have no retail counterpart.
    slots = {
      { { 0,  5 }, { 0,  6 } },     -- 移動
      { { 0,  8 }, { 0,  9 } },     -- 攻撃
      { { 0, 16 }, { 0, 17 } },     -- 防御
      { { 0, 24 }, false      },    -- 情報
      { { 0, 28 }, false      },    -- 終
      { { 0, 30 }, { 0, 31 } },     -- 特
    },
  },
  {
    -- The status-screen digits and their symbols: column 1 is the active form,
    -- column 2 the greyed-out one.
    file = "STATUS_NUMBERS.bmp",
    cols = 2,
    rows = 12,
    slots = {
      { { 9,  0 }, { 9, 12 } },
      { { 9,  1 }, { 9, 13 } },
      { { 9,  2 }, { 9, 14 } },
      { { 9,  3 }, { 9, 15 } },
      { { 9,  4 }, { 9, 16 } },
      { { 9,  5 }, { 9, 17 } },
      { { 9,  6 }, { 9, 18 } },
      { { 9,  7 }, { 9, 19 } },
      { { 9,  8 }, { 9, 20 } },
      { { 9,  9 }, { 9, 21 } },
      { { 9, 10 }, { 9, 22 } },
      { { 9, 11 }, { 9, 23 } },
    },
  },
  {
    -- The bottom-screen arrows, one per row.
    file = "BOTTOM_ARROW.bmp",
    cols = 1,
    rows = 12,
    slots = {
      { { 11,  0 } },
      { { 11,  1 } },
      { { 11,  2 } },
      { { 11,  3 } },
      { { 11,  4 } },
      { { 11,  5 } },
      { { 11,  6 } },
      { { 11,  7 } },
      { { 11,  8 } },
      { { 11,  9 } },
      { { 11, 10 } },
      { { 11, 11 } },
    },
  },
  {
    -- The large number glyphs, one per row.
    file = "NUMBERS_BIG.bmp",
    cols = 1,
    rows = 13,
    slots = {
      { { 7,  0 } },
      { { 7,  1 } },
      { { 7,  2 } },
      { { 7,  3 } },
      { { 7,  4 } },
      { { 7,  5 } },
      { { 7,  6 } },
      { { 7,  7 } },
      { { 7,  8 } },
      { { 7,  9 } },
      { { 7, 10 } },
      { { 7, 11 } },
      { { 7, 12 } },
    },
  },
  {
    -- The small number glyphs, one per row.
    file = "NUMBERS_SMALL.bmp",
    cols = 1,
    rows = 14,
    slots = {
      { { 7, 13 } },
      { { 7, 14 } },
      { { 7, 15 } },
      { { 7, 16 } },
      { { 7, 17 } },
      { { 7, 18 } },
      { { 7, 19 } },
      { { 7, 20 } },
      { { 7, 21 } },
      { { 7, 22 } },
      { { 7, 23 } },
      { { 7, 24 } },
      { { 7, 25 } },
      { { 7, 26 } },
    },
  },
  {
    -- The words behind the main commands, one row per command: column 1 is the
    -- label and column 2 the greyed-out one.  Déplacer, Statut, Carte,
    -- Stratégie, Terminer and Protéger have no inactive art at retail, so their
    -- second cells are drawn for alignment only.
    file = "CMD_NAMES.bmp",
    cols = 2,
    rows = 12,
    slots = {
      { { 0,  7 }, false      },   -- 移動      Déplacer
      { { 0, 10 }, { 0, 11 } },    -- 通常      Attaque
      { { 0, 12 }, { 0, 13 } },    -- 必殺      Spéciale
      { { 0, 14 }, { 0, 15 } },    -- 連携      Combo
      { { 0, 18 }, { 0, 19 } },    -- ため      Charger
      { { 0, 20 }, { 0, 21 } },    -- 防御      Défendre
      { { 0, 22 }, { 0, 23 } },    -- 回復      Réparer
      { { 0, 25 }, false      },   -- 情報      Statut
      { { 0, 26 }, false      },   -- 全図      Carte
      { { 0, 27 }, false      },   -- 相談      Stratégie
      { { 0, 29 }, false      },   -- 待機      Terminer
      { { 0, 32 }, false      },   -- 加護      Protéger
    },
  },
}

local function command_name(block, image)
  return string.format("COMBAT/command_%02d_%02d.bmp", block, image)
end

-- Descriptive workspace names for the command images that have one.  The rest
-- keep command_<block>_<image>.bmp; see codec.command_files.
local COMMAND_FILES = {
  ["00_00"] = "MAIN_MENU_GIRLS.bmp",        -- the command bar
  ["00_01"] = "MAIN_MENU_OGAMI.bmp",        -- the bar's Ogami variant
  ["00_02"] = "SUBMENU_1_UN.bmp",           -- submenu box, 2 rows
  ["00_03"] = "SUBMENU_2_DEUX.bmp",         -- submenu box, 3 rows
  ["00_04"] = "SUBMENU_3_TROIS.bmp",        -- submenu box, 4 rows
  ["01_00"] = "SUBMENU_HOVER.bmp",          -- submenu hover effect
  ["03_00"] = "UNIT_INFO.bmp",
  ["03_01"] = "UNIT_STATUT.bmp",
  ["03_04"] = "TURN_ICON.bmp",
  ["12_00"] = "MESSAGE.bmp",
  -- Failure screen.  Retail is 5 transparent columns, 3 of frame, 72 of label,
  -- 3 of frame, 5 transparent (an 88-wide background); these files are 8 pixels
  -- wider with the background grown by the same 8 (96 = 5+3+80+3+5), so the
  -- labels keep their 3-pixel frame margins.  Checked in game: the title text's
  -- centre lands on the panel's centre and the highlight bar has the same gap on
  -- each side, so this panel fills its slot correctly.
  --
  -- Every one of these panels is drawn at a fixed x, never centred: the engine
  -- places the background at a fixed left edge and puts a label 8 pixels right of
  -- it without ever looking at the label's width.  Widening art therefore grows
  -- the panel to the right of retail's position, and no art change can pull it
  -- back left of the sprite's own origin.
  --
  -- The x values themselves were originally *inferred from screenshots*, not
  -- read out of SLG.BIN: the backgrounds come out at about 116, 108 and 128 for
  -- blocks 13, 14 and 15, each of which is (320 - retail width)/2 to within the
  -- +/-2 pixels the measurement is good for.  Blocks 13 and 14 are still only
  -- known that way.
  --
  -- Block 15 is not: its panel is placed by code at 0x25F36 in SLG.BIN (and the
  -- identical 0SLG.BIN), `mov #-32,r10 / mov.w r10,@r14` for xa and `mov #-28`
  -- for ya -- half of the retail 64x56 panel -- while the sprite's size comes
  -- from this file's battle-menu image header (width, height).  Widening
  -- MENU_START_00_BG therefore leaves xa at -32 and grows the panel to the right.
  -- combat_commands_metadata.lua rewrites that immediate to -(width/2).
  ["13_00"] = "MENU_GAMEOVER_00_TITLE.bmp",
  ["13_01"] = "MENU_GAMEOVER_01_RETRY.bmp",
  ["13_02"] = "MENU_GAMEOVER_02_BG.bmp",
  ["13_03"] = "MENU_GAMEOVER_03_HOVER.bmp",
  -- Confirm choices for start menu
  ["14_00"] = "MENU_CONFIRM_00_BG.bmp",
  ["14_01"] = "MENU_CONFIRM_01_RETRY.bmp",
  ["14_02"] = "MENU_CONFIRM_02_QUIT.bmp",
  ["14_03"] = "MENU_CONFIRM_03_YES.bmp",
  ["14_04"] = "MENU_CONFIRM_04_NO.bmp",
  ["14_05"] = "MENU_CONFIRM_05_HOVER.bmp",
  -- Start menu.  Retail is 64 wide and these files are 112.  The draw x is an
  -- instruction immediate (see above), so the codec pair keeps the panel
  -- centred: the metadata codec writes -(width/2) for whatever width this file
  -- ends up carrying.
  ["15_00"] = "MENU_START_00_BG.bmp",
  ["15_01"] = "MENU_START_01_RETRY.bmp",
  ["15_02"] = "MENU_START_02_OPTIONS.bmp",
  ["15_03"] = "MENU_START_03_HOVER.bmp",
}

-- The workspace file names to try for one command image: the descriptive one
-- first, then the numbered name, so a folder written before the renaming still
-- reads.
function codec.command_files(block, image)
  local key = string.format("%02d_%02d", block, image)
  local names = {}
  if COMMAND_FILES[key] then names[#names + 1] = COMMAND_FILES[key] end
  names[#names + 1] = "command_" .. key .. ".bmp"
  return names
end

local function move_name(block, image)
  return string.format("NAMES/special_move_%02d_%02d.bmp", block, image)
end

-- Hash -> file for the special-move names.  A name image is identified by the
-- sha256 of the pristine art it replaces, not by its slot: the same slot holds
-- different pictures in different WKLs.  A line here names the file in
-- <workspace>/combat/names that carries the art for that hash; a hash listed
-- here with no such file is an error, and a hash with no line falls back to
-- <hash>.bmp.
local NAME_FILES = {
  -- Main character name labels
  ["f98df30369e7d714c49de3dfc80f54d47471c80e9cba3b981060807b25938fc0"] = "NAME_CHAR_IRIS.bmp",
  ["b824340888ca24251037e5a28f3855940a30c9a698d16636669069606676298e"] = "NAME_CHAR_KANNA.bmp",
  ["099e2e2c0df8995c4d9b56dc37fa34057abd6d2467d11a16e209441ee7864444"] = "NAME_CHAR_KORAN.bmp",
  ["d8634507842049aeda2b95172c9770dfca60edcf8ee28a63cf0e7fa879512699"] = "NAME_CHAR_MARIA.bmp",
  ["affc18aefc236f6ce8b1d44f6d3e6f236233197bc5ba070799ae5c01994358ed"] = "NAME_CHAR_OGAMI.bmp",
  ["2070e5e073b07568667b4c2f8235a72ed26051b552eacde4dfa986e494a1da47"] = "NAME_CHAR_SAKURA.bmp",
  ["a4a60f7829584a5584bcff1a59c8b1d9bf4dc4f632a785ebd06613932eb7b8dd"] = "NAME_CHAR_SUMIRE.bmp",

  -- Unit name
  ["0e4692e3db45d9c486c7323996c903d1d3d5357fd6a90415c2537bf3e01d3c1b"] = "NAME_UNIT_KAMUI.bmp",
  ["4a9af00c1b1981c8d30393175c42d66580a034411761230b6bf20050988e6795"] = "NAME_UNIT_KOBU.bmp",
  ["d3adf866191a80d006cf599e7c374e734891d43cf5fd5bfc26741922a624d92a"] = "NAME_UNIT_WAKIJI.bmp",
  -- Enemy name labels
  ["5dcf0fab615f23e1c1b4e1b0dbffdb9353bc83f51d7deb28f0aa6d182efb18f5"] = "NAME_ENEMY_ASHIGARU.bmp",
  ["d66d803b78095af50d3382a4095737e7347a604fb44744318a5cf0e24786e68e"] = "NAME_ENEMY_MIROKU.bmp",
  ["f301d14628fcc08abc91f25760154d840c1895a99e9479130e4f05360a191d23"] = "NAME_ENEMY_RASETSU.bmp",
  ["3e5f7c8259cd1cbc6379a41a6f7ad2a9650793a503fa1adc4f909773f384d4f5"] = "NAME_ENEMY_SATAN.bmp",
  ["31e887e4fae8d566a453a97542063f640887befaee6e4ab351e8c367feebdd8a"] = "NAME_ENEMY_TENKAI.bmp",

  ["78200b2106e666aee5b7d681c4c70cc2d0b39dffb509603e4578aa1191812231"] = "SUPER_EMPTY.bmp",
  ["3a9989b25db62ea412db5a03c95b8b57269c5f060e6923ee718f5f57467dbda2"] = "SUPER_IRIS_1.bmp",
  ["14e3341602cbfc082dca41c22e157c5053ed343f40320eb842918bff6e79e985"] = "SUPER_IRIS_2.bmp",
  ["73039558dbe641ab772ee53bddf783f4fb37ce66759ac50f6624adbabf7bdc77"] = "SUPER_MARIA_1.bmp",
  ["aa9aa76d9a328b485279f319297a64ec5dd0f93ba65a1ab8c7e4138659fcf70d"] = "SUPER_MARIA_2.bmp",
  ["bae73798d73fc92b532591bbc2b1631745015f78283108a5bc211a53fe51a1d8"] = "SUPER_OGAMI_1.bmp",
  ["b8175a554015f7ed3d767781c7da50167f65588c2fb0e83932d994ead6a532ce"] = "SUPER_OGAMI_2.bmp",
  ["2f1616f0c3eff582b0e7436b630cb90b080a7657be0927c9796c62da2674720b"] = "SUPER_SAKURA_1.bmp",
  ["4715c82326e384e6bcc355c8f8868aa5916c61c1717772fd15e0976e4f4eaa76"] = "SUPER_SAKURA_2.bmp",
  ["35f7d1c7151550bf95d25ffd4e9b0c8216dd691b9a25cc8d113975c829fc6eba"] = "SUPER_SUMIRE_1.bmp",
  ["80457b7a4ffc63903c9c93a23d308aa6bbf55c66ab2d8b3786491ca2046b08a0"] = "SUPER_SUMIRE_2.bmp",
}

-----------------------------------------------------------------------------
-- Dimensions
-----------------------------------------------------------------------------

local function check_dimensions(width, height, stage)
  if width == 0 or height == 0 then
    error(stage .. ": an empty image", 0)
  end
  if width % 8 ~= 0 then
    error(string.format("%s: width %d is not a multiple of 8, which VDP1 needs", stage, width), 0)
  end
  if width > 2040 then
    error(string.format("%s: width %d is past the 2040 pixels VDP1 can address", stage, width), 0)
  end
  if height > 255 then
    error(string.format("%s: height %d is past the 255 a sprite can be", stage, height), 0)
  end
end

-- The art of one command image: width * height pixels at 4bpp.
local function pixel_bytes(width, height)
  return (width * height) // 2
end

-- What the block stores for one image.  VDP1 names a texture by an 8-byte
-- character address, so the next image has to start on a multiple of 8: 56x15
-- is 420 bytes and is padded to 424.  The blank bytes follow the last row and
-- no sprite reads them, because width and height still come from the header.
local function slot_bytes(width, height)
  local bytes = pixel_bytes(width, height)
  return (bytes + 7) // 8 * 8
end

-- The compressed blocks store each image's byte length and offset in u16s.
local function check_move_size(width, height, total, stage)
  local bytes = (width * height) // 2
  if bytes > 0xFFFF then
    error(string.format("%s is %dx%d, %d bytes; the block's byteCount is 16-bit",
      stage, width, height, bytes), 0)
  end
  if total + bytes > 0xFFFF then
    error(string.format("%s pushes its block past the 65535 bytes a u16 offset can address",
      stage), 0)
  end
end

-- The dimensions and pixels of an edited BMP.  bmp.parse does the validation;
-- only the header read is added so a resized image is accepted.
local function read_bmp(data, name)
  if type(data) ~= "string" or #data < 54 then
    error(name .. ": BMP too short", 0)
  end
  if data:sub(1, 2) ~= "BM" then
    error(name .. ": not a BMP file", 0)
  end
  local width, height = string.unpack("<i4i4", data, 19)
  height = math.abs(height)
  local pixels = bmp.parse(data, width, height, 4)
  return pixels, width, height
end

-----------------------------------------------------------------------------
-- Sheets
-----------------------------------------------------------------------------

-- The slots a sheet names, keyed "block:image".
local function sheet_slots(sheet)
  if not sheet.slot_set then
    local set = {}
    for _, row in ipairs(sheet.slots) do
      for _, slot in ipairs(row) do
        if slot then set[slot[1] .. ":" .. slot[2]] = true end
      end
    end
    sheet.slot_set = set
  end
  return sheet.slot_set
end

-- The pixels of one cell, top-down rows, 4bpp.
local function sheet_cell(pixels, width, col, row, cell_width, cell_height)
  local stride = width // 2
  local bytes  = cell_width // 2
  local parts  = {}
  for y = 0, cell_height - 1 do
    local start = (row * cell_height + y) * stride + col * bytes
    parts[#parts + 1] = pixels:sub(start + 1, start + bytes)
  end
  return table.concat(parts)
end

local function pool_leaf(name)
  return name:match("[^/\\]+$") or name
end

local function parse_sheet(data, name, sheet)
  local pixels, width, height = read_bmp(data, name)
  if width % sheet.cols ~= 0 or height % sheet.rows ~= 0 then
    error(string.format(
      "%s: %s is %dx%d, which does not split into %d x %d equal cells",
      LABEL, name, width, height, sheet.cols, sheet.rows), 0)
  end

  local cell_width, cell_height = width // sheet.cols, height // sheet.rows
  check_dimensions(cell_width, cell_height, name .. " cells")

  return {
    name = name,
    pixels = pixels,
    width = width,
    height = height,
    cell_width = cell_width,
    cell_height = cell_height,
  }
end

-- One sheet from a workspace directory, or nil when it is not there.
local function read_sheet(path, sheet)
  local file = io.open(path, "rb")
  if not file then return nil end
  local data = file:read("a")
  file:close()
  return parse_sheet(data, path, sheet)
end

-- The sheets one workspace directory supplies, keyed by artifact name.
function codec.read_sheets(directory)
  local found = {}
  for _, sheet in ipairs(SHEETS) do
    local cell = read_sheet(directory .. "/" .. pool_leaf(sheet.file), sheet)
    if cell then found[sheet.file] = cell end
  end
  return found
end

-- The cells of the sheets in hand, keyed "block:image".
local function sheet_overrides(sheets)
  local cells = {}
  for _, sheet in ipairs(SHEETS) do
    local found = sheets[sheet.file]
    if found then
      for r, row in ipairs(sheet.slots) do
        for c, slot in ipairs(row) do
          if slot then
            cells[slot[1] .. ":" .. slot[2]] = {
              pixels = sheet_cell(found.pixels, found.width, c - 1, r - 1,
                found.cell_width, found.cell_height),
              width = found.cell_width,
              height = found.cell_height,
              sheet = sheet.file,
              column = c - 1,
              row = r - 1,
            }
          end
        end
      end
    end
  end
  return cells
end

-----------------------------------------------------------------------------
-- Battle-menu region (COMBAT)
-----------------------------------------------------------------------------

local function parse_command_block(data, absolute, index, size)
  local count = u16(data, absolute)
  if count == 0 or count > 2048 then
    error(string.format("%s: command block %d has an invalid image count", LABEL, index), 0)
  end

  local headers_end = absolute + MENU_PREFIX + count * MENU_INFO
  local data_start  = headers_end + MENU_SUFFIX
  if data_start > absolute + size then
    error(string.format("%s: command block %d is truncated", LABEL, index), 0)
  end

  local images = {}
  local cumulative = 0
  for j = 0, count - 1 do
    local pos = absolute + MENU_PREFIX + j * MENU_INFO
    local from_header   = u32(data, pos)
    local from_previous = u32(data, pos + 4)
    local width  = u16(data, pos + 8)
    local height = u16(data, pos + 10)
    local unknown = u32(data, pos + 12)

    if width == 0 or height == 0 or width % 8 ~= 0 then
      error(string.format("%s: command block %d image %d has invalid dimensions",
        LABEL, index, j), 0)
    end
    if from_header + from_previous ~= cumulative then
      error(string.format("%s: command block %d image %d has an invalid layout",
        LABEL, index, j), 0)
    end

    local bytes = pixel_bytes(width, height)
    local slot  = slot_bytes(width, height)
    if data_start + cumulative + slot > absolute + size then
      error(string.format("%s: command block %d image %d is truncated",
        LABEL, index, j), 0)
    end

    images[#images + 1] = {
      width = width,
      height = height,
      unknown = unknown,
      offset = cumulative,
      bytes = bytes,
      abs = data_start + cumulative,
    }
    cumulative = cumulative + slot
  end

  local last_offset = u32(data, headers_end)
  local last_size   = u32(data, headers_end + 4)
  if last_offset + last_size ~= cumulative then
    error(string.format("%s: command block %d has inconsistent size fields", LABEL, index), 0)
  end

  local needed = MENU_PREFIX + count * MENU_INFO + MENU_SUFFIX + cumulative
  if needed ~= size then
    error(string.format(
      "%s: command block %d is %d bytes, but its headers and images need %d",
      LABEL, index, size, needed), 0)
  end

  return { index = index, absolute = absolute, size = size, count = count, images = images }
end

-- The command table and the blocks it describes.  Blocks are stored
-- contiguously after the table, which is how PatchWKLFiles writes them and how
-- every retail WKL is laid out.
local function parse_commands(data)
  if type(data) ~= "string" then error(LABEL .. ": expected a binary string", 0) end
  if #data < HEADER_BYTES + 8 then error(LABEL .. ": file too short for a WKL header", 0) end

  local base     = u32(data, MENU_POINTER)
  local declared = u32(data, MENU_SIZE)
  if base < HEADER_BYTES or base + 8 > #data then
    error(string.format("%s: command table address 0x%X is outside the file", LABEL, base), 0)
  end

  local table_bytes = u32(data, base)
  if table_bytes < 8 or table_bytes % 8 ~= 0 or table_bytes > 256 * 8 then
    error(string.format("%s: invalid command table size %d", LABEL, table_bytes), 0)
  end
  if base + table_bytes > #data then
    error(LABEL .. ": command table runs past the end of the file", 0)
  end
  if declared < table_bytes or base + declared > #data then
    error(string.format("%s: command region of %d bytes does not fit the file",
      LABEL, declared), 0)
  end

  local header_size = declared_size(data, base)
  if header_size and header_size ~= declared then
    error(string.format("%s: command region is %d bytes at 0xEC but %d in the header",
      LABEL, declared, header_size), 0)
  end

  local blocks = {}
  local cursor = table_bytes
  for i = 0, table_bytes // 8 - 1 do
    local offset = u32(data, base + i * 8)
    local size   = u32(data, base + i * 8 + 4)
    if size == 0 then
      if offset ~= 0 then
        error(string.format("%s: command block %d has no size but offset 0x%X",
          LABEL, i, offset), 0)
      end
      blocks[#blocks + 1] = { index = i, size = 0, images = {}, empty = true }
    else
      if offset ~= cursor then
        error(string.format(
          "%s: command block %d starts at 0x%X, expected 0x%X", LABEL, i, offset, cursor), 0)
      end
      if base + offset + size > base + declared then
        error(string.format("%s: command block %d runs past the region", LABEL, i), 0)
      end
      blocks[#blocks + 1] = parse_command_block(data, base + offset, i, size)
      cursor = offset + size
    end
  end

  return { base = base, size = declared, table_bytes = table_bytes, blocks = blocks }
end

-- Re-serialise one command block from its images.  Sizes follow the
-- dimensions, so an image may be larger or smaller than it was, and each one is
-- padded to a whole number of 8-byte VDP1 characters.
local function build_command_block(images)
  local count = #images
  local sizes = {}
  for j, image in ipairs(images) do
    sizes[j] = slot_bytes(image.width, image.height)
  end

  local parts = { string.pack(">I2", count) .. string.rep("\0", 6) }
  for j, image in ipairs(images) do
    local from_header = 0
    for k = 1, j - 2 do from_header = from_header + sizes[k] end
    local from_previous = j == 1 and 0 or sizes[j - 1]
    parts[#parts + 1] = string.pack(">I4I4I2I2I4",
      from_header, from_previous, image.width, image.height, image.unknown)
  end

  local last_offset = 0
  for k = 1, count - 1 do last_offset = last_offset + sizes[k] end
  parts[#parts + 1] = string.pack(">I4I4", last_offset, sizes[count])

  for _, image in ipairs(images) do
    local pad = slot_bytes(image.width, image.height) - pixel_bytes(image.width, image.height)
    parts[#parts + 1] = pad > 0 and image.pixels .. string.rep("\0", pad) or image.pixels
  end
  return table.concat(parts)
end

-----------------------------------------------------------------------------
-- Compressed names region (NAMES)
-----------------------------------------------------------------------------

local function parse_move_block(data, absolute, index, entry_size)
  if entry_size < 2 then
    error(string.format("%s: move block %d is too short", LABEL, index), 0)
  end

  local ok, unpacked = pcall(function()
    return prs:decode(data:sub(absolute + 1, absolute + entry_size))[1].data
  end)
  if not ok or type(unpacked) ~= "string" then
    error(string.format("%s: move block %d does not decompress: %s",
      LABEL, index, tostring(unpacked)), 0)
  end
  if #unpacked < 16 then
    error(string.format("%s: move block %d is too short", LABEL, index), 0)
  end

  local count = u16(unpacked, 0)
  if count == 0 or count > 256 then
    error(string.format("%s: move block %d has an invalid image count", LABEL, index), 0)
  end

  local header = 16 * (count + 1)
  if header > #unpacked then
    error(string.format("%s: move block %d has an invalid header", LABEL, index), 0)
  end

  local images = {}
  local cumulative = 0
  for j = 0, count - 1 do
    local pos = 16 + j * MOVES_INFO
    local width  = u16(unpacked, pos)
    local height = u16(unpacked, pos + 2)
    local offset = u16(unpacked, pos + 10)
    local bytes  = u16(unpacked, pos + 14)

    if width == 0 or height == 0 or width % 8 ~= 0 then
      error(string.format("%s: move block %d image %d has invalid dimensions",
        LABEL, index, j), 0)
    end
    if bytes ~= (width * height) // 2 or offset ~= cumulative then
      error(string.format("%s: move block %d image %d has an invalid layout",
        LABEL, index, j), 0)
    end
    if header + offset + bytes > #unpacked then
      error(string.format("%s: move block %d image %d is truncated", LABEL, index, j), 0)
    end

    images[#images + 1] = {
      width = width,
      height = height,
      head = unpacked:sub(pos + 5, pos + 10),      -- u1, u2, u3
      tail = unpacked:sub(pos + 13, pos + 14),     -- u4
      offset = offset,
      bytes = bytes,
      abs = header + offset,
    }
    cumulative = cumulative + bytes
  end

  return {
    index = index,
    absolute = absolute,
    size = entry_size,
    unpacked = unpacked,
    reserved = unpacked:sub(3, 16),
    images = images,
  }
end

local function parse_moves(data)
  local base = u32(data, MOVES_POINTER)
  if base < HEADER_BYTES or base + MOVES_ENTRIES * 8 > #data then
    error(string.format("%s: move table address 0x%X is outside the file", LABEL, base), 0)
  end

  local declared = declared_size(data, base)
  if not declared then
    error(string.format("%s: no header entry sizes the move section at 0x%X", LABEL, base), 0)
  end
  if base + declared > #data then
    error(string.format("%s: move section of %d bytes does not fit the file", LABEL, declared), 0)
  end

  local entries = {}
  local cursor = MOVES_ENTRIES * 8
  for i = 0, MOVES_ENTRIES - 1 do
    local offset = u32(data, base + i * 8)
    local size   = u32(data, base + i * 8 + 4)
    if offset ~= cursor then
      error(string.format("%s: move block %d starts at 0x%X, expected 0x%X",
        LABEL, i, offset, cursor), 0)
    end
    if size == 0 then
      entries[#entries + 1] = { index = i, size = 0, images = {}, empty = true }
    else
      if cursor + size > declared then
        error(string.format("%s: move block %d runs past the section", LABEL, i), 0)
      end
      entries[#entries + 1] = parse_move_block(data, base + cursor, i, size)
      cursor = cursor + size
    end
  end

  return { base = base, size = declared, entries = entries }
end

local function build_move_block(block, images)
  local count = #images
  local parts = { string.pack(">I2", count) .. block.reserved }
  local cumulative = 0
  for _, image in ipairs(images) do
    local bytes = (image.width * image.height) // 2
    parts[#parts + 1] = string.pack(">I2I2", image.width, image.height)
      .. image.head
      .. string.pack(">I2", cumulative)
      .. image.tail
      .. string.pack(">I2", bytes)
    cumulative = cumulative + bytes
  end
  for _, image in ipairs(images) do parts[#parts + 1] = image.pixels end
  return table.concat(parts)
end

-----------------------------------------------------------------------------
-- Relocation
-----------------------------------------------------------------------------

-- Replace the regions listed and shift every header entry after them.  An entry
-- that starts a region keeps its address and takes the new size; entries that
-- point inside a region would be describing data that no longer exists.
local function relocate(original, regions)
  table.sort(regions, function(a, b) return a.base < b.base end)

  for i = 2, #regions do
    if regions[i - 1].base + regions[i - 1].size > regions[i].base then
      error(string.format("%s: two rebuilt regions overlap", LABEL), 0)
    end
  end

  local running = 0
  for _, region in ipairs(regions) do
    region.delta = #region.bytes - region.size
    running = running + region.delta
  end

  local parts = {}
  local cursor = 0
  for _, region in ipairs(regions) do
    parts[#parts + 1] = original:sub(cursor + 1, region.base)
    parts[#parts + 1] = region.bytes
    cursor = region.base + region.size
  end
  parts[#parts + 1] = original:sub(cursor + 1)
  local body = table.concat(parts)

  local entries = {}
  for i = 0, HEADER_ENTRIES - 1 do
    local offset = u32(original, i * 8)
    local size   = u32(original, i * 8 + 4)
    local shift  = 0

    for _, region in ipairs(regions) do
      if region.base < offset then
        shift = shift + region.delta
      elseif region.base == offset then
        if size ~= 0 then size = #region.bytes end
        break
      else
        break
      end
    end

    for _, region in ipairs(regions) do
      if offset > region.base and offset < region.base + region.size then
        error(string.format("%s: WKL header entry %d points inside a rebuilt region",
          LABEL, i), 0)
      end
    end

    if offset + shift > 0xFFFFFFFF then
      error(string.format("%s: WKL header entry %d no longer fits", LABEL, i), 0)
    end
    entries[#entries + 1] = string.pack(">I4I4", offset + shift, size)
  end

  return table.concat(entries) .. body:sub(HEADER_BYTES + 1)
end

-----------------------------------------------------------------------------
-- The retail layout, for scripts/combat_commands_metadata.lua
-----------------------------------------------------------------------------

local function region_size_from(bytes)
  local size = #BLOCK_COUNTS * 8                    -- the table
  local at = 1
  for _, count in ipairs(BLOCK_COUNTS) do
    size = size + MENU_PREFIX + count * MENU_INFO + MENU_SUFFIX
    for _ = 1, count do
      size = size + bytes[at]
      at = at + 1
    end
  end
  return size
end

-- The size the command region takes from the BMPs and sheets in one WKL's
-- workspace directory, falling back to retail dimensions for images with no
-- override.  `sheets` defaults to the sheets that directory carries; the
-- metadata plugin passes the disc-wide set instead.
function codec.region_size(directory, sheets)
  sheets = sheets or codec.read_sheets(directory)

  local sizes = {}
  for i = 1, #IMAGE_BYTES do sizes[i] = IMAGE_BYTES[i] end

  local at = 1
  for block = 0, #BLOCK_COUNTS - 1 do
    for image = 0, BLOCK_COUNTS[block + 1] - 1 do
      local path, file
      for _, candidate in ipairs(codec.command_files(block, image)) do
        file = io.open(directory .. "/" .. candidate, "rb")
        if file then path = directory .. "/" .. candidate break end
      end
      if file then
        local data = file:read("a")
        file:close()
        if not data or #data < 54 or data:sub(1, 2) ~= "BM" then
          error(string.format("%s: unreadable BMP %s", LABEL, path), 0)
        end
        local width, height = string.unpack("<i4i4", data, 19)
        height = math.abs(height)
        check_dimensions(width, height, path)
        sizes[at] = slot_bytes(width, height)
      end

      local key = block .. ":" .. image
      for _, sheet in ipairs(SHEETS) do
        local found = sheets[sheet.file]
        if found and sheet_slots(sheet)[key] then
          sizes[at] = slot_bytes(found.cell_width, found.cell_height)
        end
      end

      at = at + 1
    end
  end

  return region_size_from(sizes)
end

codec.retail_region     = RETAIL_REGION
codec.max_growth        = MAX_GROWTH
codec.retail_image_bytes = IMAGE_BYTES
codec.block_counts      = BLOCK_COUNTS
codec.sheets            = SHEETS

-----------------------------------------------------------------------------
-- Codec
-----------------------------------------------------------------------------

function codec.can_handle(data)
  return can_handle.can_handle_combat_commands(data)
end

function codec.decode_name()
  return "COMBAT"
end

-- Nothing is extracted: the battle-menu art is the workspace pool, and a WKL is
-- only ever written.  decode_artifacts below still reads one, for the move
-- names the pool does not translate.
function codec.decode(data, args)
  return {}
end

-- The artifacts a WKL carries.  Used internally by encode() for the move
-- names that the workspace pool does not translate; decode() itself is a NOP.
local function decode_artifacts(data)
  local commands = parse_commands(data)
  local moves = parse_moves(data)
  local artifacts = {}

  for _, block in ipairs(commands.blocks) do
    for j, image in ipairs(block.images) do
      artifacts[#artifacts + 1] = {
        name = command_name(block.index, j - 1),
        data = bmp.build(data:sub(image.abs + 1, image.abs + image.bytes),
          image.width, image.height, 4, PALETTE),
      }
    end
  end

  for _, block in ipairs(moves.entries) do
    for j, image in ipairs(block.images) do
      artifacts[#artifacts + 1] = {
        name = move_name(block.index, j - 1),
        data = bmp.build(block.unpacked:sub(image.abs + 1, image.abs + image.bytes),
          image.width, image.height, 4, PALETTE),
      }
    end
  end

  return artifacts
end

-- The battle-menu art is one disc-wide pool instead of one copy per WKL:
-- decode() produces nothing, and every encode reads the pool.
local COMMANDS_POOL = "combat/commands"
local NAMES_POOL    = "combat/names"

local function pool_dir(name)
  local workspace = LUDARED and LUDARED.WORKSPACE
  if not workspace then return nil end
  return workspace .. "/" .. name
end

-- A sheet is one authored file for the whole disc, and it lives in the pool.
-- Every WKL is rebuilt on its own from it, so no WKL folder is consulted.
function codec.pool_sheets()
  local directory = pool_dir(COMMANDS_POOL)
  if not directory then return nil end
  local sheets = codec.read_sheets(directory)
  if next(sheets) == nil then return nil end
  return sheets
end

local function pool_file(directory, name)
  if not directory then return nil end
  local file = io.open(directory .. "/" .. pool_leaf(name), "rb")
  if not file then return nil end
  local data = file:read("a")
  file:close()
  return data
end

-- Open a pool file for writing, creating the folder if the pool has never been
-- materialised.  Returns nil when the folder cannot be made.
local function factory(directory, name, mode)
  os.execute("mkdir -p '" .. directory .. "'")
  return io.open(directory .. "/" .. pool_leaf(name), mode or "wb")
end

-- A name-pool file is identified by the sha256 of the untranslated art it
-- replaces, not by its slot: the same slot holds different pictures in
-- different WKLs, so the slot is not an identity and the art is.
local function pool_key(data)
  local sha256 = LUDARED and LUDARED.sha256
  if not sha256 then
    error(LABEL .. ": LUDARED.sha256 is missing; the name pool is keyed by it", 0)
  end
  return sha256(data)
end

-- Everything the pool carries, named the way this codec knows it.
local function pool_artifacts(original)
  local artifacts = {}
  local commands = pool_dir(COMMANDS_POOL)

  if commands then
    for _, sheet in ipairs(SHEETS) do
      local data = pool_file(commands, sheet.file)
      if data then artifacts[#artifacts + 1] = { name = sheet.file, data = data } end
    end
    for block = 0, #BLOCK_COUNTS - 1 do
      for image = 0, BLOCK_COUNTS[block + 1] - 1 do
        local name = command_name(block, image)
        for _, candidate in ipairs(codec.command_files(block, image)) do
          local data = pool_file(commands, candidate)
          if data then
            artifacts[#artifacts + 1] = { name = name, data = data }
            break
          end
        end
      end
    end
  end

  -- The move names: each pristine image is hashed, and the pool supplies
  -- NAME_FILES' file for that hash, else <hash>.bmp, else the untranslated art
  -- itself — written into the pool first, so deleting a name reconstructs it.
  local names = pool_dir(NAMES_POOL)
  for _, artifact in ipairs(decode_artifacts(original)) do
    if artifact.name:sub(1, 6) == "NAMES/" then
      local key = pool_key(artifact.data)
      local data, mapped = nil, NAME_FILES[key]

      if mapped then
        data = pool_file(names, mapped)
        if not data then
          error(string.format("%s: NAME_FILES maps %s to %s, but %s holds no such file",
            LABEL, key, mapped, NAMES_POOL), 0)
        end
      else
        data = pool_file(names, key .. ".bmp")
        if not data and names then
          local file = factory(names, key .. ".bmp")
          if file then file:write(artifact.data) file:close() end
          data = artifact.data
        end
      end

      artifacts[#artifacts + 1] = { name = artifact.name, data = data }
    end
  end

  return artifacts
end

function codec.encode(original, artifacts, args)
  if args ~= nil and args ~= "" then
    error(LABEL .. ": this codec takes no arguments, got '" .. tostring(args) .. "'", 0)
  end

  local commands = parse_commands(original)
  local moves = parse_moves(original)

  local by_name = {}
  for _, artifact in ipairs(artifacts or {}) do
    if type(artifact) == "table" and type(artifact.name) == "string" then
      by_name[artifact.name] = artifact.data
    end
  end
  for _, artifact in ipairs(pool_artifacts(original)) do
    by_name[artifact.name] = artifact.data
  end

  -- Sheets, disc-wide from the pool unless an artifact declares one.
  local sheets = codec.pool_sheets() or {}
  for _, sheet in ipairs(SHEETS) do
    local data = by_name[sheet.file]
    if data then sheets[sheet.file] = parse_sheet(data, sheet.file, sheet) end
  end
  local cells = sheet_overrides(sheets)

  -- COMBAT ---------------------------------------------------------------
  local commands_changed = false
  local command_parts = {}
  local command_table = {}

  local offset = commands.table_bytes
  for _, block in ipairs(commands.blocks) do
    if block.empty then
      command_table[#command_table + 1] = string.pack(">I4I4", 0, 0)
    else
      local images = {}
      local changed = false

      for j, image in ipairs(block.images) do
        local name = command_name(block.index, j - 1)
        local edited = by_name[name]
        local pixels = original:sub(image.abs + 1, image.abs + image.bytes)
        local width, height = image.width, image.height

        if edited then
          local edited_pixels, edited_width, edited_height = read_bmp(edited, name)
          check_dimensions(edited_width, edited_height, name)
          if edited_width ~= width or edited_height ~= height or edited_pixels ~= pixels then
            changed = true
          end
          pixels, width, height = edited_pixels, edited_width, edited_height
        end

        -- A sheet's cell is the art and the size of the slot it names.
        local cell = cells[block.index .. ":" .. (j - 1)]
        if cell then
          if cell.width ~= width or cell.height ~= height or cell.pixels ~= pixels then
            changed = true
          end
          pixels, width, height = cell.pixels, cell.width, cell.height
        end

        images[j] = { width = width, height = height, unknown = image.unknown, pixels = pixels }
      end

      local bytes
      if changed then
        commands_changed = true
        bytes = build_command_block(images)
      else
        bytes = original:sub(block.absolute + 1, block.absolute + block.size)
      end
      command_table[#command_table + 1] = string.pack(">I4I4", offset, #bytes)
      command_parts[#command_parts + 1] = bytes
      offset = offset + #bytes
    end
  end

  -- NAMES ---------------------------------------------------------------
  local moves_changed = false
  local move_table = {}
  local move_parts = {}

  offset = MOVES_ENTRIES * 8
  for _, block in ipairs(moves.entries) do
    if block.empty then
      move_table[#move_table + 1] = string.pack(">I4I4", offset, 0)
    else
      local images = {}
      local changed = false
      local total = 0

      for j, image in ipairs(block.images) do
        local name = move_name(block.index, j - 1)
        local edited = by_name[name]
        local pixels = block.unpacked:sub(image.abs + 1, image.abs + image.bytes)
        local width, height = image.width, image.height

        if edited then
          local edited_pixels, edited_width, edited_height = read_bmp(edited, name)
          check_dimensions(edited_width, edited_height, name)
          if edited_width ~= width or edited_height ~= height or edited_pixels ~= pixels then
            changed = true
          end
          pixels, width, height = edited_pixels, edited_width, edited_height
        end

        check_move_size(width, height, total, name)
        total = total + (width * height) // 2
        images[j] = {
          width = width,
          height = height,
          head = image.head,
          tail = image.tail,
          pixels = pixels,
        }
      end

      if changed then
        moves_changed = true
        local compressed = prs:encode("", {
          { name = "DECOMPRESSED", data = build_move_block(block, images) },
        })
        move_table[#move_table + 1] = string.pack(">I4I4", offset, #compressed)
        move_parts[#move_parts + 1] = compressed
        offset = offset + #compressed
      else
        move_table[#move_table + 1] = string.pack(">I4I4", offset, block.size)
        move_parts[#move_parts + 1] =
          original:sub(block.absolute + 1, block.absolute + block.size)
        offset = offset + block.size
      end
    end
  end

  if not commands_changed and not moves_changed then return original end

  local regions = {}
  if commands_changed then
    local bytes = table.concat(command_table) .. table.concat(command_parts)
    local delta = #bytes - commands.size
    if delta > MAX_GROWTH then
      error(string.format(
        "%s: the command region would grow by %d bytes, past the %d VDP1 has "
        .. "before the block at 0x25C49100.  Shed %d byte%s",
        LABEL, delta, MAX_GROWTH, delta - MAX_GROWTH,
        delta - MAX_GROWTH == 1 and "" or "s"), 0)
    end
    regions[#regions + 1] = { base = commands.base, size = commands.size, bytes = bytes }
  end
  if moves_changed then
    local bytes = table.concat(move_table) .. table.concat(move_parts)
    regions[#regions + 1] = { base = moves.base, size = moves.size, bytes = bytes }
  end

  return relocate(original, regions)
end

return codec
