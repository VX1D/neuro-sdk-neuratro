_G.NEURO_TEST = true
if not love then love = { timer = { getTime = function() return 0 end } } end

local check, done = require("tests.helpers").harness("select_blind_ui_guard")

local handle_select_blind = require("handlers.board_handlers").handle_select_blind
local Actions = require("core.actions")

local function blind_select_env()
  _G.G = {
    STATE = 1, STATES = { BLIND_SELECT = 1 },
    GAME = {
      dollars = 20, blind_on_deck = "Small",
      current_round = { hands_left = 4, discards_left = 3 },
      round_resets = {
        ante = 1,
        blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_boss" },
        blind_states = { Small = "Select", Big = "Upcoming", Boss = "Upcoming" },
      },
    },
    NEURO = { run_generation = 1, _decision_windows = {} },
    FUNCS = {
      select_blind = function(args)
        G._select_blind_called = (G._select_blind_called or 0) + 1
        G._select_blind_arg = args
      end,
    },
    P_BLINDS = {
      bl_small = { key = "bl_small", name = "Small Blind" },
      bl_big = { key = "bl_big", name = "Big Blind" },
      bl_boss = { key = "bl_boss", name = "Boss Blind" },
    },
    blind_select = {},
    jokers = { cards = {}, config = { card_limit = 5 } },
    consumeables = { cards = {}, config = { card_limit = 2 } },
  }
  require("core.actions")
  require("core.dispatcher")
end

local function set_selectable(key)
  local states = { Small = "Upcoming", Big = "Upcoming", Boss = "Upcoming" }
  states[key] = "Select"
  G.GAME.round_resets.blind_states = states
  G.GAME.blind_on_deck = key
end

local function positive_path(blind_key, ref_key, label)
  blind_select_env()
  set_selectable(blind_key)
  G._select_blind_called = 0
  G._select_blind_arg = nil
  local closure = handle_select_blind({ blind = string.lower(blind_key) })
  check(label .. ": execution closure returned", type(closure) == "function")
  if type(closure) == "function" then
    closure()
  end
  check(label .. ": callback invoked exactly once", G._select_blind_called == 1)
  check(label .. ": ref_table is exact",
    G._select_blind_arg and G._select_blind_arg.config
      and G._select_blind_arg.config.ref_table == G.P_BLINDS[ref_key])
end

blind_select_env()
check("small blind: handler returns an execution closure", type(handle_select_blind({ blind = "small" })) == "function")
G._select_blind_called = 0
local closure = handle_select_blind({ blind = "small" })
closure()
check("small blind: callback invoked once", G._select_blind_called == 1)
check("small blind: ref_table to small",
  G._select_blind_arg and G._select_blind_arg.config
    and G._select_blind_arg.config.ref_table == G.P_BLINDS.bl_small)

positive_path("Big", "bl_big", "big blind")
positive_path("Boss", "bl_boss", "boss blind")

blind_select_env()
G.blind_select = nil
check("missing G.blind_select is rejected",
  handle_select_blind({ blind = "small" }) == nil)

blind_select_env()
G.FUNCS = nil
local ok_r, res_r = pcall(handle_select_blind, { blind = "small" })
check("G.FUNCS == nil: action is rejected without throwing", ok_r and res_r == nil)

blind_select_env()
G.FUNCS.select_blind = nil
check("a missing callback is rejected",
  handle_select_blind({ blind = "small" }) == nil)

blind_select_env()
G.FUNCS.select_blind = {}
check("a non-function callback is rejected",
  handle_select_blind({ blind = "small" }) == nil)

blind_select_env()
check("a non-selectable blind is rejected",
  handle_select_blind({ blind = "boss" }) == nil)

blind_select_env()
G.GAME.round_resets.blind_choices.Small = "missing_small"
G.P_BLINDS.bl_small = nil
check("missing small blind definition rejects the action",
  handle_select_blind({ blind = "small" }) == nil)

blind_select_env()
set_selectable("Big")
G.GAME.round_resets.blind_choices.Big = "missing_big"
G.P_BLINDS.bl_big = nil
check("missing big blind definition rejects the action",
  handle_select_blind({ blind = "big" }) == nil)

blind_select_env()
set_selectable("Boss")
G.GAME.round_resets.blind_choices.Boss = "missing_boss"
G.P_BLINDS.bl_boss = nil
check("missing boss blind definition rejects the action",
  handle_select_blind({ blind = "boss" }) == nil)

blind_select_env()
G.blind_select_opts = nil
check("missing G.blind_select_opts remains valid because the engine does not require it",
  type(handle_select_blind({ blind = "small" })) == "function")

blind_select_env()
G.blind_select_opts = { big = {}, boss = {} }
check("missing small-blind UI option remains valid because the engine does not require it",
  type(handle_select_blind({ blind = "small" })) == "function")

local handle_skip_blind = require("handlers.board_handlers").handle_skip_blind

blind_select_env()
set_selectable("Small")
G.GAME.round_resets.blind_tags = { Small = "tag_handy", Big = "tag_handy" }
G.blind_select_opts = nil
check("skip: available without a UI tree because state is authoritative",
  Actions.is_action_valid("skip_blind") == true)

blind_select_env()
set_selectable("Small")
G.GAME.round_resets.blind_tags = nil
check("skip: a missing reward tag is unavailable",
  Actions.is_action_valid("skip_blind") == false)

blind_select_env()
set_selectable("Small")
G.GAME.round_resets.blind_tags = { Small = "tag_handy" }
G.P_BLINDS.bl_small.unskippable = true
check("skip: an unskippable blind is unavailable",
  Actions.is_action_valid("skip_blind") == false)

blind_select_env()
set_selectable("Boss")
G.GAME.round_resets.blind_tags = { Small = "tag_handy", Big = "tag_handy" }
check("skip: the boss blind is never skippable",
  Actions.is_action_valid("skip_blind") == false)

blind_select_env()
set_selectable("Small")
G.GAME.round_resets.blind_tags = { Small = "tag_handy" }
G.blind_select_opts = nil
do
  local skip_closure, err = handle_skip_blind({})
  check("skip: a missing UIBox is rejected with a reason because the engine reads e.UIBox",
    skip_closure == nil and type(err) == "string" and err:find("Blind UI option", 1, true) ~= nil)
end

blind_select_env()
set_selectable("Small")
G.GAME.round_resets.blind_tags = { Small = "tag_handy" }
G.blind_select_opts = { small = { get_UIE_by_ID = function() return { config = { ref_table = {} } } end } }
do
  local called = 0
  G.FUNCS.skip_blind = function() called = called + 1 end
  local skip_closure = handle_skip_blind({})
  check("skip: the valid path returns an execution closure", type(skip_closure) == "function")
  if type(skip_closure) == "function" then skip_closure() end
  check("skip: engine callback invoked once", called == 1)
end

done()
