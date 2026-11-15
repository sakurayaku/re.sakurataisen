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
}
