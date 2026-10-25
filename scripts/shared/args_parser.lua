--[[
  Shared parser for Ludared codec arguments.

  Ludared records one opaque string per decode and hands it to both passes, so
  the codec carries its own syntax.  The house syntax is semicolon-separated
  key=value pairs, and a key declared `list = true` takes a comma-separated
  list of values:

      cd=2
      grow_dma=safe
      cd=2;grow_dma=safe
      layers=bg,fg,sprites

  The two separators keep their jobs apart: ';' ends a pair, ',' keeps values
  together.  That way a value may never be confused with the next key.  Only a
  `list` key splits on ','; for every other key a comma is just part of the
  value, so `cd=1,2` is the single token "1,2" and fails the same value check
  any other wrong spelling would.  ';' needs quoting in a shell, which is the
  price of leaving ',' free for lists; single-pair arguments such as
  grow_dma=safe read the same as before.

  Unknown keys, duplicate keys, missing required keys, unknown values, empty
  list items and bare tokens are all errors: a typo in a manifest must fail the
  build, not quietly produce a disc with the wrong offset or transfer length.

  Usage:

      local args = load_shared("args_parser")
      local opts = args.parse(raw, {
        cd       = { values = { "1", "2" }, required = true },
        grow_dma = { values = { "none", "safe" }, default = "none" },
        layers   = { values = { "bg", "fg" }, list = true },
      }, "main menu gfx")
      -- opts.cd == "1" | "2", opts.grow_dma == "none" | "safe",
      -- opts.layers == nil or { "bg", "fg" }
]]

local M = {}

local function describe(spec)
  local names = {}
  for name, entry in pairs(spec) do
    local values = {}
    for _, value in ipairs(entry.values or {}) do values[#values + 1] = value end
    names[#names + 1] = string.format("%s=%s%s%s", name,
      #values > 0 and table.concat(values, "|") or "value",
      (entry.list and " (list)" or ""),
      (entry.required and " (required)" or ""))
  end
  table.sort(names)
  return table.concat(names, ", ")
end

local function trim(text)
  return (text:match("^%s*(.-)%s*$"))
end

-- Validates one value and returns the canonical spelling to store.
local function accept(entry, key, value, label)
  local compare = entry.lower and value:lower() or value
  if entry.values then
    for _, candidate in ipairs(entry.values) do
      if compare == candidate then
        return candidate
      end
    end
    error(string.format("%s: %s must be %s, got %q",
      label, key, table.concat(entry.values, "|"), value), 4)
  end
  if entry.validate and not entry.validate(value) then
    error(string.format("%s: %s got an invalid value %q", label, key, value), 4)
  end
  return value
end

-- `raw` is nil, "" or a string.  Returns a table with one entry per spec key
-- that has a value (`default` fills in the optional ones).  A `list` key holds
-- an array in pair order; every other key holds a single string.
function M.parse(raw, spec, label)
  label = label or "codec"

  if type(raw) == "table" then
    error(label .. ": arguments must be a string, got a table", 3)
  end
  if raw ~= nil and type(raw) ~= "string" then
    error(label .. ": arguments must be a string, got " .. type(raw), 3)
  end

  local opts, seen = {}, {}
  for name, entry in pairs(spec) do
    if entry.default ~= nil then opts[name] = entry.default end
  end

  if raw ~= nil and raw ~= "" then
    for pair in raw:gmatch("[^;]+") do
      local key, value = pair:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
      if not key or value == "" then
        error(string.format(
          "%s: cannot read argument %q; expected semicolon-separated key=value pairs (%s)",
          label, trim(pair), describe(spec)), 3)
      end

      local entry = spec[key]
      if not entry then
        error(string.format(
          "%s: unknown argument %q; supported: %s", label, key, describe(spec)), 3)
      end
      if seen[key] then
        error(string.format("%s: argument %q given twice", label, key), 3)
      end
      seen[key] = true

      if entry.list then
        local items = {}
        for raw_item in (value .. ","):gmatch("([^,]*),") do
          local item = trim(raw_item)
          if item == "" then
            error(string.format("%s: %s has an empty list item in %q",
              label, key, value), 3)
          end
          items[#items + 1] = accept(entry, key, item, label)
        end
        opts[key] = items
      else
        opts[key] = accept(entry, key, value, label)
      end
    end
  end

  for name, entry in pairs(spec) do
    if entry.required and opts[name] == nil then
      error(string.format("%s: missing required argument %q; supported: %s",
        label, name, describe(spec)), 3)
    end
  end

  return opts
end

return M
