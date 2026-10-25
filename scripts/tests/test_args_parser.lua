--[[ Test harness for shared/args_parser.lua — run from the project root:
     ludared codecs test tests/test_args_parser.lua ]]

local args_parser = dofile(LUDARED.SCRIPTS .. "/shared/args_parser.lua")

local pass, fail = 0, 0
local function check(name, ok, detail)
  if ok then pass = pass + 1; print("  ok    " .. name)
  else fail = fail + 1; print("  FAIL  " .. name .. (detail and ("  -- " .. detail) or "")) end
end

local SPEC = {
  cd       = { values = { "1", "2" }, required = true },
  grow_dma = { values = { "none", "safe" }, default = "none", lower = true },
  layers   = { values = { "bg", "fg", "sprites" }, list = true, lower = true },
}

local function parse(raw)
  return args_parser.parse(raw, SPEC, "test")
end

local function err_of(raw)
  local ok, message = pcall(parse, raw)
  if ok then return nil end
  return tostring(message)
end

local function refused(name, raw, expected)
  local message = err_of(raw)
  check(name, message ~= nil and message:find(expected, 1, true) ~= nil,
    message or "parsed without error")
end

local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

print("args_parser.lua test harness")
print("")

print("single pair")
check("a required scalar parses", parse("cd=2").cd == "2")
check("an absent optional key takes its default", parse("cd=1").grow_dma == "none")
local optional = { grow_dma = SPEC.grow_dma }
check("nil arguments leave the defaults",
  args_parser.parse(nil, optional, "test").grow_dma == "none")
check("an empty string is the same as nil",
  args_parser.parse("", optional, "test").grow_dma == "none")
check("whitespace around a pair is ignored", parse("  cd = 2  ").cd == "2")
check("a value is matched case-insensitively when asked",
  parse("cd=1;grow_dma=SAFE").grow_dma == "safe")

print("")
print("pairs")
local two = parse("cd=2;grow_dma=safe")
check("two pairs split on ';'", two.cd == "2" and two.grow_dma == "safe")
check("a trailing ';' is tolerated", parse("cd=2;").cd == "2")
check("whitespace around ';' is ignored", parse(" cd=2 ; grow_dma=safe ").grow_dma == "safe")

print("")
print("lists")
check("',' separates list values", same(parse("cd=1;layers=bg,fg").layers, { "bg", "fg" }))
check("a one-item list is a list", same(parse("cd=1;layers=fg").layers, { "fg" }))
check("list items accept whitespace", same(parse("cd=1;layers= bg , sprites ").layers, { "bg", "sprites" }))
check("list items are canonicalised", same(parse("cd=1;layers=BG,fg").layers, { "bg", "fg" }))
check("an undeclared list key stays absent", parse("cd=1").layers == nil)

print("")
print("refusals")
-- A comma is not special for a scalar key: the whole token is the value, and
-- it fails the ordinary membership check rather than a bespoke list error.
refused("a list given to a single-valued key", "cd=1,2", "must be 1|2, got \"1,2\"")
refused("an empty list item", "cd=1;layers=bg,,fg", "empty list item")
refused("an empty list", "cd=1;layers=,", "empty list item")
refused("an unknown list item", "cd=1;layers=bg,hud", "must be bg|fg|sprites")
refused("an unknown key", "cd=2;dma=0x5000", "unknown argument")
refused("a duplicate key", "cd=1;cd=2", "given twice")
refused("a bare token", "cd", "key=value")
refused("an empty value", "cd=", "key=value")
refused("a value outside the list", "cd=3", "must be 1|2")
refused("a missing required key", "grow_dma=safe", "missing required argument")
refused("a table instead of a string", { cd = "1" }, "must be a string")

print("")
local message = err_of("cd=1;nope=1") or ""
check("the error lists the accepted set", message:find("layers=bg|fg|sprites (list)", 1, true) ~= nil,
  message)
local bare = err_of("cd=1;oops") or ""
check("the error names ';' as the pair separator", bare:find("semicolon-separated", 1, true) ~= nil,
  bare)

print("")
print(string.format("%d passed, %d failed", pass, fail))
assert(fail == 0, string.format("%d tests failed", fail))
