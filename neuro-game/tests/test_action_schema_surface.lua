require("tests.stubs").setup({ love = "timers" })
_G.G = { NEURO = {}, FUNCS = {}, GAME = { current_round = {} }, hand = { cards = {} }, TIMERS = { REAL = 100 } }

local check, done = require("tests.helpers").harness("action-schema-surface")

local Bridge = require("core.bridge")
local Actions = require("core.actions")
local json = require("util.neuro_json")

local function wire_actions()
  local b = Bridge:new({ game = "Balatro", enabled = true })
  b.sent = {}
  b.send = function(self, message) self.sent[#self.sent + 1] = message end
  b:register_actions(Actions.get_static_actions())
  for _, m in ipairs(b.sent) do
    if m.command == "actions/register" then return m.data.actions end
  end
  return nil
end

local function find_key(v, key, path)
  if type(v) ~= "table" then return nil end
  for k, child in pairs(v) do
    if k == key then return path .. "." .. tostring(k) end
    local hit = find_key(child, key, path .. "." .. tostring(k))
    if hit then return hit end
  end
  return nil
end

do
  local wire = wire_actions()
  check("register message captured", type(wire) == "table" and #wire > 0)
  if type(wire) == "table" then
    local wbad
    for _, a in ipairs(wire) do
      local hit = a.schema and find_key(a.schema, "description", a.name or "?")
      if hit then wbad = hit break end
    end
    check("wire schemas carry no description keyword", wbad == nil, wbad)
    local kept = 0
    for _, a in ipairs(wire) do
      if type(a.description) == "string" and #a.description > 0 then kept = kept + 1 end
    end
    check("top-level action descriptions still reach the wire", kept == #wire, kept .. "/" .. #wire)
  end
end

for _, mode in ipairs({ "on", "off" }) do
  require("core.config").set("NEURO_CONFIRM_HAND", mode)
  local marked = {}
  for _, a in ipairs(wire_actions() or {}) do
    local d = tostring(a.description)
    if d:find("`", 1, true) or d:find("**", 1, true) or d:find("#", 1, true) or d:find("^%s*%- ") then
      marked[#marked + 1] = a.name
    end
  end
  check("confirm_hand " .. mode .. ": every registered description is plain text", #marked == 0, table.concat(marked, ","))
end
require("core.config").set("NEURO_CONFIRM_HAND", "on")

local function area_enum(wire, action_name)
  for _, a in ipairs(wire or {}) do
    if a.name == action_name then
      local props = a.schema and a.schema.properties
      local area = props and props.area
      return area and area.enum or nil
    end
  end
  return nil
end

local has = require("tests.helpers").has

do
  local wire = wire_actions()
  for _, name in ipairs({ "use_consumable", "sell_card" }) do
    local e = area_enum(wire, name)
    check(name .. ".area advertises the English spelling `consumables`",
      e ~= nil and has(e, "consumables"), e and table.concat(e, ",") or "nil")
    check(name .. ".area does not advertise the engine's `consumeables`",
      e ~= nil and not has(e, "consumeables"), e and table.concat(e, ",") or "nil")
  end
  for _, name in ipairs({ "choose_pack_card", "choose_directional_pack_card" }) do
    local e = area_enum(wire, name)
    check(name .. ".area is restricted to the open pack",
      e ~= nil and #e == 1 and e[1] == "booster_pack",
      e and table.concat(e, ",") or "nil")
  end
  for _, name in ipairs({ "use_consumable", "use_directional_consumable" }) do
    local e = area_enum(wire, name)
    check(name .. ".area is restricted to owned consumables",
      e ~= nil and #e == 1 and e[1] == "consumables",
      e and table.concat(e, ",") or "nil")
  end
end

local Dispatcher = require("core.dispatcher")
local Enforce = require("tests.helpers").enforce()
local Helpers = require("tests.helpers")

local function tarot()
  return require("tests.engine_cards").consumable("c_fool",
    { sort_id = "c_fool", sell_cost = 1, cost = 3, juice_up = function() end })
end

local function dispatch_use_card(area_value)
  G.TIMERS.REAL = (G.TIMERS.REAL or 100) + 100
  G.STATES = require("tests.engine_cards").states()
  G.STATE = G.STATES.SELECTING_HAND
  G.CONTROLLER = { locked = false }
  G.STATE_COMPLETE = true
  G.OVERLAY_MENU = nil
  G.GAME = {
    dollars = 10, chips = 0, used_vouchers = {},
    current_round = { hands_left = 4, discards_left = 2 },
    round_resets = { ante = 1, blind_on_deck = "Small",
      blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_hook" } },
    blind_on_deck = "Small", modifiers = {}, hands = {},
  }
  G.hand = { cards = {}, highlighted = {}, config = { card_limit = 5, highlighted_limit = 5 } }
  G.jokers = { cards = {}, config = { card_limit = 5 } }
  G.consumeables = { cards = { tarot() }, config = { card_limit = 2 } }
  G.deck = { cards = {} }
  G.FUNCS = { use_card = function() end }
  require("core.validate").reset_run_state()
  require("core.bridge").tx.reset()
  Enforce.reset_run_state()

  local log = {}
  G.NEURO = { enabled = true, decision_serial = 1, dispatcher = Dispatcher, actions = Actions,
    shop_visit_epoch = 1, state = "SELECTING_HAND", state_enter_serial = 1 }
  local bridge = {
    send_action_result = function(_, _, ok, message, code)
      log[#log + 1] = { ok = ok, message = tostring(message or ""), code = code }
    end,
    send_context = function() end,
    register_actions = function() end,
    is_transition_cooldown = function() return false end,
  }
  Helpers.stage_registered(nil, { "use_consumable" })
  Dispatcher.handle_message({ command = "action", data = {
    id = "area-" .. tostring(area_value), name = "use_consumable",
    data = json.encode({ area = area_value, index = 1 }) } }, bridge)
  return log[1] or { ok = nil, message = "(no result)", code = nil }
end

do
  local alias = dispatch_use_card("consumables")
  check("dispatcher still accepts the `consumables` alias (expanded before schema validation)",
    alias.code ~= "SCHEMA_INVALID", tostring(alias.code) .. " / " .. alias.message)

  local typo = dispatch_use_card("consumablez")
  check("control: an unaliased area value is still rejected by the enum",
    typo.code == "SCHEMA_INVALID", tostring(typo.code) .. " / " .. typo.message)
end

do
  local Registry = require("core.action_registry")
  local defs = Registry.definitions()
  check("action definitions are loaded", #defs >= 26, tostring(#defs))

  local UNSUPPORTED_KEYWORDS = {
    ["$anchor"] = true, ["$comment"] = true, ["$defs"] = true, ["$dynamicAnchor"] = true,
    ["$dynamicRef"] = true, ["$id"] = true, ["$ref"] = true, ["$schema"] = true,
    ["$vocabulary"] = true, ["additionalProperties"] = true, ["allOf"] = true,
    ["anyOf"] = true, ["contentEncoding"] = true, ["contentMediaType"] = true,
    ["contentSchema"] = true, ["dependentRequired"] = true, ["dependentSchemas"] = true,
    ["deprecated"] = true, ["description"] = true, ["else"] = true, ["if"] = true,
    ["maxProperties"] = true, ["minProperties"] = true, ["multipleOf"] = true,
    ["not"] = true, ["oneOf"] = true, ["patternProperties"] = true, ["readOnly"] = true,
    ["then"] = true, ["title"] = true, ["unevaluatedItems"] = true,
    ["unevaluatedProperties"] = true, ["writeOnly"] = true,
  }

  local SUPPORTED_VALIDATOR_KEYWORDS = require("util.schema_validate").SUPPORTED_KEYWORDS

  local function collect_schema_keys(schema, collected, path)
    if type(schema) ~= "table" then return end
    for k, v in pairs(schema) do
      if type(k) == "string" then
        collected[k] = collected[k] or {}
        table.insert(collected[k], path .. "." .. k)
      end
      if type(v) == "table" and k ~= "properties" and k ~= "items" and k ~= "enum" and k ~= "required" then
        collect_schema_keys(v, collected, path .. "." .. tostring(k))
      end
    end
    if schema.properties and type(schema.properties) == "table" then
      for prop_name, prop_schema in pairs(schema.properties) do
        collect_schema_keys(prop_schema, collected, path .. ".properties." .. prop_name)
      end
    end
    if schema.items and type(schema.items) == "table" then
      collect_schema_keys(schema.items, collected, path .. ".items")
    end
  end

  local all_used_keys = {}
  local non_object_roots = {}

  for _, def in ipairs(defs) do
    if type(def.schema) == "table" then
      if def.schema.type ~= "object" then
        table.insert(non_object_roots, def.name .. " (type=" .. tostring(def.schema.type) .. ")")
      end
      collect_schema_keys(def.schema, all_used_keys, def.name)
    end
  end

  local unsupported_found = {}
  for k in pairs(all_used_keys) do
    if UNSUPPORTED_KEYWORDS[k] then
      table.insert(unsupported_found, k .. " in " .. table.concat(all_used_keys[k], ", "))
    end
  end

  local unhandled_by_validator = {}
  for k in pairs(all_used_keys) do
    if not SUPPORTED_VALIDATOR_KEYWORDS[k] then
      table.insert(unhandled_by_validator, k)
    end
  end

  check("every action schema has root type 'object'",
    #non_object_roots == 0, table.concat(non_object_roots, "; "))
  check("used schema keywords exclude unsupported SPECIFICATION.md:61 keywords",
    #unsupported_found == 0, table.concat(unsupported_found, "; "))
  check("schema_validate supports every schema keyword used by an action",
    #unhandled_by_validator == 0, table.concat(unhandled_by_validator, "; "))
  local association_errors = {}
  local function walk(schema, path)
    if type(schema) ~= "table" then return end
    local props = schema.properties
    if type(props) == "table" then
      for _, required in ipairs(schema.required or {}) do
        if props[required] == nil then
          association_errors[#association_errors + 1] = path .. " requires missing " .. tostring(required)
        end
      end
      for key, child in pairs(props) do
        if type(child) ~= "table" then
          association_errors[#association_errors + 1] = path .. "." .. tostring(key) .. " has no schema"
        else
          walk(child, path .. "." .. tostring(key))
        end
      end
    end
    if type(schema.items) == "table" then walk(schema.items, path .. "[]") end
  end
  local function same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
  end
  local prompt_errors = {}
  for _, def in ipairs(defs) do
    walk(def.schema, def.name)
    local prompt = Registry.prompt(def.name) or ""
    local shown = ((Registry.display(def.name) or {}).schema or {}).properties or {}
    for key, spec in pairs((def.schema or {}).properties or {}) do
      if same(spec, shown[key]) and prompt:find("%f[%w_]" .. key .. "%f[^%w_]", #("Use the " .. def.name .. " action") + 1) then
        prompt_errors[#prompt_errors + 1] = def.name .. "." .. key
      end
    end
  end
  check("nested schema properties remain associated with required keys", #association_errors == 0,
    table.concat(association_errors, "; "))
  check("structured prompts restate no schema field they leave as registered", #prompt_errors == 0,
    table.concat(prompt_errors, "; "))

end


do
  local SchemaValidate = require("util.schema_validate")
  local seed_schema
  for _, def in ipairs(Actions.get_static_actions()) do
    if def.name == "paste_seed" then
      seed_schema = def.schema
      break
    end
  end
  local seed = seed_schema and seed_schema.properties and seed_schema.properties.seed
  local valid, valid_err = SchemaValidate.validate_value(seed_schema,
    { seed = "ABC123XY" }, "parameters")
  local invalid, invalid_err = SchemaValidate.validate_value(seed_schema,
    { seed = "AB-123" }, "parameters")
  check("paste_seed schema advertises the handler's alphanumeric contract",
    seed and seed.pattern == "^[A-Za-z0-9]*$",
    tostring(seed and seed.pattern))
  check("paste_seed accepts an eight-character alphanumeric seed",
    valid == true, tostring(valid_err))
  check("paste_seed rejects punctuation before handler execution",
    invalid == false and type(invalid_err) == "string",
    tostring(invalid_err))
end

do
  local function dispatch_test(action_name, state_name, payload_data)
    G.TIMERS.REAL = (G.TIMERS.REAL or 100) + 100
    G.STATE = G.STATES[state_name] or 1
    G.STATE_COMPLETE = true
    G.OVERLAY_MENU = nil
    G.NEURO.state = state_name
    require("core.validate").reset_run_state()
    require("core.bridge").tx.reset()
    Enforce.reset_run_state()

    local log = {}
    local bridge = {
      send_action_result = function(_, _, ok, message, code)
        log[#log + 1] = { ok = ok, message = tostring(message or ""), code = code }
      end,
      send_context = function() end,
      register_actions = function() end,
      is_transition_cooldown = function() return false end,
    }

    Helpers.stage_registered(nil, { action_name })
    require("tests.helpers").open_force(state_name, { action_name })
    local wire_payload = payload_data
    if type(payload_data) == "table" then
      local wire_value = next(payload_data) == nil and json.object(payload_data) or payload_data
      wire_payload = json.encode(wire_value)
    end
    Dispatcher.handle_message({
      command = "action",
      data = {
        id = "n200-test",
        name = action_name,
        data = wire_payload
      }
    }, bridge)
    return log[1] or { ok = nil, message = "(no result)", code = nil }
  end

  local r_req1 = dispatch_test("select_blind", "BLIND_SELECT", {})
  check("select_blind missing required parameter 'blind' returns SCHEMA_INVALID",
    r_req1.code == "SCHEMA_INVALID" and r_req1.message:find("Missing required parameter: blind", 1, true) ~= nil,
    tostring(r_req1.code) .. " / " .. r_req1.message)

  local r_req2 = dispatch_test("use_consumable", "SELECTING_HAND", { area = "consumeables" })
  check("use_consumable missing required parameter 'index' returns SCHEMA_INVALID",
    r_req2.code == "SCHEMA_INVALID" and r_req2.message:find("Missing required parameter: index", 1, true) ~= nil,
    tostring(r_req2.code) .. " / " .. r_req2.message)

  local r_engine = dispatch_test("use_consumable", "SELECTING_HAND", { area = "consumeables", index = 1 })
  local r_bogus = dispatch_test("use_consumable", "SELECTING_HAND", { area = "consumabels", index = 1 })
  check("the engine's `consumeables` spelling still passes the advertised area enum",
    r_engine.code ~= "SCHEMA_INVALID" and r_bogus.code == "SCHEMA_INVALID",
    tostring(r_engine.code) .. " / " .. tostring(r_bogus.code))

  local r_absent = dispatch_test("play_hand", "SELECTING_HAND", nil)
  check("an omitted action payload is treated as an empty JSON object",
    r_absent.code == "SCHEMA_INVALID"
      and r_absent.message:find("Missing required parameter: indices", 1, true) ~= nil
      and r_absent.message:find("must be an object", 1, true) == nil,
    tostring(r_absent.code) .. " / " .. r_absent.message)

  local r_arr = dispatch_test("play_hand", "SELECTING_HAND", { indices = "not_an_array" })
  check("a non-table array payload reports 'must be an array'",
    r_arr.code == "SCHEMA_INVALID" and r_arr.message:find("must be an array", 1, true) ~= nil,
    tostring(r_arr.code) .. " / " .. r_arr.message)

  local r_obj_scalar = dispatch_test("select_blind", "BLIND_SELECT", "scalar_payload")
  check("a scalar payload reports the reference SDK's invalid-JSON failure",
    r_obj_scalar.code == "SCHEMA_INVALID",
    tostring(r_obj_scalar.code) .. " / " .. r_obj_scalar.message)
  local r_bool = dispatch_test("select_blind", "BLIND_SELECT", false)
  local r_large = dispatch_test(
    "select_blind", "BLIND_SELECT", '{"x":"' .. string.rep("x", 65530) .. '"}')
  check("boolean payloads reject before schema defaults while large frame-valid payloads reach schema validation",
    r_bool.code == "SCHEMA_INVALID"
      and r_large.code == "SCHEMA_INVALID"
      and r_large.message:find("Missing required parameter: blind", 1, true) ~= nil,
    tostring(r_bool.code) .. " / " .. r_bool.message .. " | "
      .. tostring(r_large.code) .. " / " .. r_large.message)


  local r_obj_raw_scalar = dispatch_test("select_blind", "BLIND_SELECT", '"scalar_json"')
  check("a JSON scalar payload is told the parameters must be an object",
    r_obj_raw_scalar.code == "SCHEMA_INVALID",
    tostring(r_obj_raw_scalar.code) .. " / " .. r_obj_raw_scalar.message)

  local r_obj_arr = dispatch_test("select_blind", "BLIND_SELECT", { "blind", "small" })
  check("an array root payload is told the parameters must be an object",
    r_obj_arr.code == "SCHEMA_INVALID",
    tostring(r_obj_arr.code) .. " / " .. r_obj_arr.message)

  local r_enum_blind = dispatch_test("select_blind", "BLIND_SELECT", { blind = "invalid_blind" })
  check("an invalid select_blind enum reports the permitted values",
    r_enum_blind.code == "SCHEMA_INVALID" and r_enum_blind.message:find("must be one of: small, big, boss", 1, true) ~= nil,
    tostring(r_enum_blind.code) .. " / " .. r_enum_blind.message)

  local r_enum_tag = dispatch_test("record_joker_roles", "SHOP", { intents = { { index = 1, tag = "INVALID_TAG" } } })
  check("an invalid record_joker_roles tag reports the permitted values",
    r_enum_tag.code == "SCHEMA_INVALID" and r_enum_tag.message:find("must be one of: CORE, SCALING, HOLD, CHANGE", 1, true) ~= nil,
    tostring(r_enum_tag.code) .. " / " .. r_enum_tag.message)

  local r_min_items = dispatch_test("play_hand", "SELECTING_HAND", { indices = {} })
  check("an empty play_hand.indices array reports a minItems violation",
    r_min_items.code == "SCHEMA_INVALID" and r_min_items.message:find("must have at least 1 item", 1, true) ~= nil,
    tostring(r_min_items.code) .. " / " .. r_min_items.message)
end

done()
