_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end
local Fixtures = require("hud.dev_fixtures")
_G.G = { I = Fixtures._test.sparse_ui_registry(4000), GAME = {}, TIMERS = { REAL = 0 } }

local check, done = require("tests.helpers").harness("ui reaper")
local Utils = require("util.utils")

local function capture_prints(fn)
  local captured = {}
  local original = print
  print = function(...) captured[#captured + 1] = table.concat({ ... }, " ") end
  local ok, err = pcall(fn)
  print = original
  return captured, ok, err
end

local preexisting = {
  remove = function(self)
    self.remove_calls = (self.remove_calls or 0) + 1
  end,
}
G.I.UIBOX.preexisting = preexisting

local throwing
local no_remove
local warning, call_ok, call_err = capture_prints(function()
  local center = {
    key = "j_reaper_failures",
    loc_vars = function()
      throwing = {
        remove = function(self)
          self.remove_calls = (self.remove_calls or 0) + 1
          self.started = true
          error("remove failed after starting")
        end,
      }
      no_remove = { marker = "no remove" }
      G.I.UIBOX.throwing = throwing
      G.I.UIBOX.no_remove = no_remove
      return { vars = { "value" } }
    end,
  }
  Utils.safe_description("#1#", { config = { center = center }, ability = {} })
end)

check("loc_vars call completes despite a throwing remove", call_ok, call_err)
check("throwing remove starts and its object is not forcibly unregistered",
  throwing and throwing.started == true and throwing.remove_calls == 1
    and G.I.UIBOX.throwing == throwing)
check("loc_vars object without remove remains registered", G.I.UIBOX.no_remove == no_remove)
check("pre-snapshot object is never reaped",
  G.I.UIBOX.preexisting == preexisting and preexisting.remove_calls == nil)
check("throwing and missing remove are both counted in one warning",
  #warning == 1 and warning[1]:find("2 UI object(s) could not be removed", 1, true) ~= nil,
  table.concat(warning, " | "))

local removable
local removable_center = {
  key = "j_reaper_success",
  loc_vars = function()
    removable = {
      remove = function(self)
        self.removed = true
        G.I.UIBOX.removable = nil
      end,
    }
    G.I.UIBOX.removable = removable
    return { vars = { 1 } }
  end,
}
Utils.safe_description("#1#", { config = { center = removable_center }, ability = {} })
check("loc_vars object with remove is reaped",
  removable and removable.removed == true and G.I.UIBOX.removable == nil)

local later_warning = capture_prints(function()
  local center = {
    key = "j_reaper_once",
    loc_vars = function()
      G.I.UIBOX.later_missing = { marker = "later" }
      return { vars = { 1 } }
    end,
  }
  Utils.safe_description("#1#", { config = { center = center }, ability = {} })
end)
check("UI reaper warning is emitted only once per process", #later_warning == 0, #later_warning)

local generated
local generated_card = {
  config = { center = { key = "j_generated_reaper" } },
  ability = {},
  generate_UIBox_ability_table = function()
    generated = {
      remove = function(self)
        self.removed = true
        G.I.UIBOX.generated = nil
      end,
    }
    G.I.UIBOX.generated = generated
    return { name = "Generated", main = {}, info = {} }
  end,
}
local generated_name = Utils.safe_name(generated_card)
check("build_ui_text uses the shared reaper",
  generated_name == "Generated" and generated and generated.removed == true
    and G.I.UIBOX.generated == nil,
  generated_name)
check("later windows do not revisit earlier registry objects",
  preexisting.remove_calls == nil and throwing.remove_calls == 1)

local sparse_existing = {
  G.I.MOVEABLE[0],
  G.I.UIBOX[2000],
  G.I.NODE[4000],
}
local sparse_removed = 0
local sparse_card = {
  config = {
    center = {
      key = "j_sparse_reaper",
      loc_vars = function()
        local function add_transient(registry, key)
          local object = {}
          object.remove = function(self)
            self.removed = true
            sparse_removed = sparse_removed + 1
            registry[key] = nil
          end
          registry[key] = object
        end
        add_transient(G.I.MOVEABLE, 1)
        add_transient(G.I.UIBOX, 2001)
        add_transient(G.I.NODE, 4001)
        return { vars = { 1 } }
      end,
    },
  },
  ability = {},
}
Utils.safe_description("#1#", sparse_card)
check("reaper handles sparse G.I registries at 0/2000/4000",
  sparse_removed == 3
    and G.I.MOVEABLE[1] == nil and G.I.UIBOX[2001] == nil and G.I.NODE[4001] == nil
    and G.I.MOVEABLE[0] == sparse_existing[1]
    and G.I.UIBOX[2000] == sparse_existing[2]
    and G.I.NODE[4000] == sparse_existing[3],
  sparse_removed)

done()
