-- Shared constants for the retail Sakura Taisen files that more than one codec
-- identifies.  Hashes are the whole file's SHA-256 as lowercase hex, exactly
-- what LUDARED.sha256() returns.
--
-- Disc 2 of SAKURA is the disc-1 build with 24 bytes inserted early and 288
-- more between 0x23140 and 0x52D40, so file offsets move by +0x18 up to that
-- point and by +0x138 from 0x52E00 on.  Both discs hold byte-identical payloads
-- (the load-screen block and its palette match exactly), so a hash only says
-- which disc -- and therefore which offsets -- a file is.

return {
  -- Disc 1, 391,712 bytes: load-screen block 0x5E190, options atlas 0x5B320.
  CD1_SAKURA_SHA256 = "1729cd8701fa8da30b203d0bf97e47e2dc9cf06b50ca91589ea760fe0cb8ff87",
  CD1_SAKURA_BYTES  = 391712,

  -- Disc 2, 392,024 bytes: the same blocks at +0x138.
  CD2_SAKURA_SHA256 = "ecbcbda739362745daac4a334e3d3d26ae8ac327ca6a66d52763416d22cdba93",
  CD2_SAKURA_BYTES  = 392024,

  -- Disc 1 main-menu module, 243,200 bytes.
  CD1_LOGO_SH2_SHA256 = "dbe0c2e777ddbc47a46856e79ee7ccf06b546d3e4a7d7be7dc10d9bb3c32cf1d",
  CD1_LOGO_SH2_BYTES  = 243200,

  -- Disc 2 main-menu module, 243,200 bytes.
  CD2_LOGO_SH2_SHA256 = "084dac119534d151c86c3b48619bf553f93f161089a8f52a40bf30fa0bc87064",
  CD2_LOGO_SH2_BYTES  = 243200,

  -- The theater-map archives are byte-identical between CDs.
  CD1_TMAPSP_SHA256 = "edf78c12dae5ac0e9e3d9c634a3d157c7ef2f66c7c52fa221f3c41b0dbb9d369",
  CD1_TMAPSP_BYTES  = 53088,
  CD2_TMAPSP_SHA256 = "edf78c12dae5ac0e9e3d9c634a3d157c7ef2f66c7c52fa221f3c41b0dbb9d369",
  CD2_TMAPSP_BYTES  = 53088,
  CD1_FUKAGAWA_SHA256 = "53e73da1af8119333061cd11e6ef0a7841686c2c4997ed73204dc66b43f7f714",
  CD1_FUKAGAWA_BYTES  = 27968,
  CD2_FUKAGAWA_SHA256 = "53e73da1af8119333061cd11e6ef0a7841686c2c4997ed73204dc66b43f7f714",
  CD2_FUKAGAWA_BYTES  = 27968,

  -- Status screen / intermission screen container, 114,688 bytes.  Byte-identical
  -- on both discs: status background 0x8800, status font 0x13800 and the
  -- intermission-screen label atlas 0x2800 live at the same offsets.
  CD1_ICATALL_SHA256 = "2f74b63152d2b83f6f647d937602daba00092afb16ee9f37d484008a287213ef",
  CD1_ICATALL_BYTES  = 114688,

  -- Disc 1 strategy-game executable, 309,844 bytes.  SLG.BIN and 0SLG.BIN are
  -- byte-identical on the disc, so one hash covers both names; the font, VWF
  -- and battle-menu codecs all patch them.
  CD1_SLG_SHA256 = "2954133afe85035792763f3a51f7868f22d727170661a47ab40e270f5ab506b8",
  CD1_SLG_BYTES  = 309844,

  -- BGRA palette table from the canonical theater-map BMP Data/TMapSP/51.bmp.
  THEATER_MAP_PALETTE_BGRA = "525231ffd6efffffbdc5deffadadceffa59cb5ff9c84a5ff946b8cff845273ff733a52ff631931ff5a0021ff630019ff5a0019ff000000ff000000ff000000ff",
}
