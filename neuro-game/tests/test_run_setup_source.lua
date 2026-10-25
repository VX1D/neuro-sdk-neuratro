local check, done = require("tests.helpers").harness("run-setup-source")

local restore_env = require("tests.helpers").snapshot_env()

local DeckFacts, MenuFlow, CtxMisc, Dispatcher, RED, GREEN
local function fresh()
  restore_env()
  require("tests.stubs").setup({ love = "zero" })
  _G.G = { NEURO = {}, FUNCS = {}, GAME = {} }
  DeckFacts = require("facts.deck_facts")
  MenuFlow = require("force.menu_flow")
  CtxMisc = require("context.ctx_misc")
  Dispatcher = require("core.dispatcher")
  RED = { key = "b_red", name = "Red Deck", set = "Back" }
  GREEN = { key = "b_green", name = "Green Deck", set = "Back" }
end

do
  fresh()

  local function back(center) return center and { name = center.name, effect = { center = center } } or nil end

  local started
  local function board(opts)
    started = nil
    _G.SMODS = { RunSelect = { Setup = { choices = { deck_choice = opts.on_screen } } },
      check_applied_stakes = require("tests.engine_cards").Rules.check_applied_stakes }
    _G.G = {
      NEURO = { persona = "neuro", state = "RUN_SETUP", selected_back_key = opts.picked },
      FUNCS = {
        start_setup_run = function(e) G.FUNCS.start_run(e, {}) end,
        start_run = function(_, args) started = args and args.deck_choice end,
      },
      GAME = { stake = 1, viewed_back = back(opts.viewed), selected_back = back(opts.selected) },
      SETTINGS = { profile = 1 },
      PROFILES = { [1] = { deck_usage = {}, MEMORY = { deck = opts.remembered },
        last_choices = { deck_choice = opts.last_choice } } },
      P_CENTERS = { b_red = RED, b_green = GREEN },
      P_CENTER_POOLS = { Back = { RED, GREEN }, Stake = { { key = "stake_white", applied_stakes = {} } } },
      OVERLAY_MENU = { get_UIE_by_ID = function(_, id) return id == "run_setup_seed" and {} or nil end },
    }
  end

  local function channels()
    local run_setup = MenuFlow.run_setup()
    local menu = MenuFlow.menu()
    local Readable = require("context.context_readable")
    return {
      run_setup_query = run_setup and run_setup.query or "",
      run_setup_state = Readable.build("RUN_SETUP", run_setup and run_setup.actions or {}) or "",
      menu_query = menu.query,
      menu_state = Readable.build("MENU", menu.actions) or "",
      deck_list = CtxMisc.setup_decks_section() or "",
      run_line = CtxMisc.run_section() or "",
      advice = DeckFacts.variety_advice(DeckFacts.viewed_deck_key()),
    }
  end

  local function started_key()
    local exec = Dispatcher.preflight("start_run", {})
    if type(exec) == "function" then pcall(exec) end
    return started and started.key
  end

  local CASES = {
    { label = "the mod's pick with no viewed deck (the regression)", picked = "b_green", selected = RED, want = GREEN },
    { label = "the mod's pick over a stale viewed deck", picked = "b_green", viewed = RED, selected = RED, want = GREEN },
    { label = "the run select screen's deck over selected_back", on_screen = "b_green", viewed = RED, selected = RED,
      want = GREEN },
    { label = "run select with a stale MEMORY.deck (the inverse regression)", remembered = "Green Deck",
      selected = RED, want = RED },
    { label = "run select showing the profile's last choice", remembered = "Red Deck",
      last_choice = "b_green", on_screen = "b_green", selected = RED, want = GREEN },
    { label = "the mod's pick over the run select screen", picked = "b_green", on_screen = "b_red",
      selected = RED, want = GREEN },
  }

  for _, case in ipairs(CASES) do
    board(case)
    local c = channels()
    local name = case.want.name
    check(case.label .. ": the run setup frame's state names " .. name,
      c.run_setup_state:find("Run setup: " .. name .. ",", 1, true) ~= nil, c.run_setup_state)
    check(case.label .. ": the menu frame's state names " .. name,
      c.menu_state:find("Run setup: " .. name .. ",", 1, true) ~= nil, c.menu_state)
    check(case.label .. ": the deck list selects " .. name,
      c.deck_list:find("Selected deck: " .. name .. " (key " .. case.want.key .. ")", 1, true) ~= nil, c.deck_list)
    check(case.label .. ": the run setup line names " .. name,
      c.run_line:find("Run setup: " .. name, 1, true) ~= nil, c.run_line)
    check(case.label .. ": the variety advice is about " .. name,
      c.advice:find(name, 1, true) ~= nil, c.advice)
    local other = case.want == RED and "Green Deck" or "Red Deck"
    check(case.label .. ": no channel names the other deck",
      not (c.run_setup_query .. c.menu_query .. c.run_line):find(other, 1, true), c.run_setup_query)
    local key = started_key()
    check(case.label .. ": start_run really begins with " .. name,
      key == case.want.key, tostring(key))
  end

  do
    board({ remembered = "Red Deck", last_choice = "b_green", selected = RED })
    G.OVERLAY_MENU = nil
    G.NEURO.state = "MENU"
    local menu_state = channels().menu_state
    check("at the main menu the deck run setup will load is named",
      menu_state:find("Run setup: Green Deck,", 1, true) ~= nil, menu_state)
  end

  do
    board({ last_choice = "b_green", on_screen = "b_red" })
    G.OVERLAY_MENU = nil
    G.NEURO.state = "MENU"
    local menu_state = channels().menu_state
    check("at the main menu run select will load the profile's last choice, not a stale screen pick",
      menu_state:find("Run setup: Green Deck,", 1, true) ~= nil, menu_state)
  end

  do
    board({})
    G.P_CENTER_POOLS.Back = { GREEN }
    G.P_CENTERS = { b_green = GREEN }
    local c = channels()
    check("with no deck known, the run setup frame names none",
      c.run_setup_state:find("Run setup: stake ", 1, true) ~= nil and c.run_setup_query:find("Deck:", 1, true) == nil,
      c.run_setup_state)
    check("with no deck known, the menu frame names none",
      c.menu_state:find("Run setup: stake ", 1, true) ~= nil and c.menu_query:find("Deck:", 1, true) == nil,
      c.menu_state)
    check("with no deck known, the deck list claims no selection", c.deck_list:find("Selected deck", 1, true) == nil,
      c.deck_list)
    check("deck_name_of invents nothing", require("facts.deck_names").deck_name_of(nil) == nil)
  end
end

do
  fresh()
  local STAKES = {}
  for i = 1, 8 do STAKES[i] = { key = "stake_" .. i, order = i, applied_stakes = {} } end

  local started, drawn
  local function run_select(opts)
    drawn = { deck = {}, tower = {} }
    local pages = { deck_choice = { key = "deck_choice", automatic_preview = true },
      stake_choice = { key = "stake_choice", include_deck_preview = true, include_stake_tower = true } }
    return { RunSelect = {
      Setup = { choices = { deck_choice = opts.screen_deck, stake_choice = opts.screen_stake } },
      Pages = pages,
      Internals = { pages = { "deck_choice", "stake_choice" }, current_page = opts.page or 2,
        preview_area = {}, stake_tower = {} },
      Functions = {
        populate_preview_ui = function(key, to_add) drawn.deck[#drawn.deck + 1] = key .. ":" .. to_add end,
        populate_stake_tower = function(stake) drawn.tower[#drawn.tower + 1] = stake end,
      },
    }, check_applied_stakes = opts.locked and function(stake)
      return not (opts.locked[stake.key] and G.NEURO.selected_back_key == "b_green")
    end or require("tests.engine_cards").Rules.check_applied_stakes }
  end

  local function board(opts)
    started = nil
    _G.SMODS = run_select(opts)
    local overlay = { get_UIE_by_ID = function(_, id) return id == "run_setup_seed" and {} or nil end }
    _G.G = {
      NEURO = { persona = "neuro", state = "RUN_SETUP", selected_back_key = opts.picked,
        selected_stake = opts.picked_stake },
      FUNCS = {
        start_setup_run = function(e)
          G.FUNCS.start_run(e, { stake = G.forced_stake or G.PROFILES[1].MEMORY.stake or 1,
            seed = G.run_setup_seed and G.setup_seed or nil })
        end,
        start_run = function(_, args)
          started = { deck = args.deck_choice and args.deck_choice.key, stake = args.stake_choice or args.stake,
            seed = args.seed }
        end,
        change_stake = function(args)
          G.viewed_stake = args.to_key
          G.PROFILES[1].MEMORY.stake = args.to_key
        end,
        setup_run = function()
          G.OVERLAY_MENU = overlay
          local last = G.PROFILES[1].last_choices
          SMODS.RunSelect.Setup.choices = { deck_choice = last.deck_choice or "b_red",
            stake_choice = last.stake_choice or 1 }
        end,
      },
      GAME = { stake = opts.old_run_stake or 1, selected_back = { name = "Red Deck", effect = { center = RED } } },
      SETTINGS = { profile = 1 },
      PROFILES = { [1] = { deck_usage = {}, MEMORY = { deck = "Red Deck", stake = opts.memory_stake },
        last_choices = { deck_choice = opts.last_deck, stake_choice = opts.last_stake } } },
      P_CENTERS = { b_red = RED, b_green = GREEN },
      P_CENTER_POOLS = { Back = { RED, GREEN }, Stake = STAKES },
      OVERLAY_MENU = opts.closed and nil or overlay,
    }
  end

  local function run(name, data)
    local exec = Dispatcher.preflight(name, data or {})
    if type(exec) ~= "function" then return nil, exec end
    local ok, err = pcall(exec)
    return ok, err
  end

  local function texts()
    local rs = MenuFlow.run_setup()
    return (require("context.context_readable").build("RUN_SETUP", rs and rs.actions or {}) or "")
      .. " || " .. (rs and rs.query or "")
  end

  do
    board({ screen_stake = 3, memory_stake = 1, old_run_stake = 6 })
    check("the stake is the one Steamodded's screen shows, not MEMORY.stake or the last run's",
      DeckFacts.run_stake() == 3, DeckFacts.run_stake())
    local t = texts()
    check("the run setup frame's state names that stake", t:find("\n- Run setup: Red Deck, stake 3,", 1, true) ~= nil, t)
    check("the run setup line names that stake", t:find("stake 3", 1, true) ~= nil, t)
    run("start_run")
    check("start_run really begins on the screen's stake (vanilla start_setup_run would pass MEMORY.stake 1)",
      started and started.stake == 3, started and started.stake)
  end

  do
    board({ screen_deck = "b_red", screen_stake = 1, memory_stake = 1 })
    run("select_stake", { to_key = 5 })
    check("select_stake moves the screen's stake choice", SMODS.RunSelect.Setup.choices.stake_choice == 5,
      SMODS.RunSelect.Setup.choices.stake_choice)
    check("and redraws the stake tower the open page shows", drawn.tower[#drawn.tower] == 5,
      table.concat(drawn.tower, ","))
    run("select_deck", { back = "b_green" })
    check("select_deck moves the screen's deck choice", SMODS.RunSelect.Setup.choices.deck_choice == "b_green")
    check("and redraws the deck preview", drawn.deck[#drawn.deck] == "deck_choice:b_green",
      table.concat(drawn.deck, ","))
    local t = texts()
    check("the text names the same deck and stake", t:find("Run setup: Green Deck, stake 5,", 1, true) ~= nil, t)
    run("start_run")
    check("and start_run begins with exactly those", started and started.deck == "b_green" and started.stake == 5,
      started and (tostring(started.deck) .. "/" .. tostring(started.stake)))
  end

  do
    board({ page = 1, screen_deck = "b_red", screen_stake = 2 })
    run("select_deck", { back = "b_green" })
    check("on the deck page the deck preview is redrawn and no stake tower is touched",
      drawn.deck[1] == "deck_choice:b_green" and #drawn.tower == 0,
      table.concat(drawn.deck, ",") .. " / " .. table.concat(drawn.tower, ","))
  end

  do
    board({ closed = true, last_deck = "b_red", last_stake = 1 })
    G.NEURO.state = "MENU"
    run("select_stake", { to_key = 4 })
    run("select_deck", { back = "b_green" })
    run("open_run_setup")
    local choices = SMODS.RunSelect.Setup.choices
    check("opening run setup shows Neuro's deck and stake, not last_choices",
      choices.deck_choice == "b_green" and choices.stake_choice == 4,
      tostring(choices.deck_choice) .. "/" .. tostring(choices.stake_choice))
  end

  do
    board({ screen_deck = "b_red", screen_stake = 1, locked = { stake_5 = true } })
    run("select_stake", { to_key = 5 })
    run("select_deck", { back = "b_green" })
    check("a stake locked for the new deck falls back to 1", DeckFacts.run_stake() == 1, DeckFacts.run_stake())
    check("the screen follows", SMODS.RunSelect.Setup.choices.stake_choice == 1
      and drawn.tower[#drawn.tower] == 1, table.concat(drawn.tower, ","))
    run("start_run")
    check("and the run starts on it", started and started.stake == 1, started and started.stake)
  end

  do
    board({ closed = true, last_deck = "b_red", last_stake = 4, memory_stake = 1, old_run_stake = 6 })
    G.NEURO.state = "MENU"
    check("at the menu the stake is the profile's last choice, what run select opens on", DeckFacts.run_stake() == 4)
    local menu_state = require("context.context_readable").build("MENU", MenuFlow.menu().actions) or ""
    check("the menu names the stake the next run starts on, not the last run's G.GAME.stake",
      menu_state:find(", stake 4,", 1, true) ~= nil, menu_state)
    run("open_run_setup")
    G.NEURO.state = "RUN_SETUP"
    run("start_run")
    check("and start_run begins on it", started and started.stake == 4, started and started.stake)
  end

  do
    -- Steamodded stores seeded mode and seed on its screen, not in G.run_setup_seed.
    board({ screen_deck = "b_red", screen_stake = 1 })
    G.run_setup_seed, G.setup_seed = true, "STALE1"
    SMODS.RunSelect.Setup.choices.enable_seed = false
    local t0 = texts()
    check("seeded mode is read from the screen, not a stale vanilla flag", t0:find(", not seeded.", 1, true) ~= nil
      and t0:find("STALE1", 1, true) == nil, t0)
    run("start_run")
    check("and an unseeded screen starts an unseeded run", started and started.seed == nil,
      started and tostring(started.seed))
    run("toggle_seeded_run")
    check("toggle_seeded_run flips the screen's enable_seed", SMODS.RunSelect.Setup.choices.enable_seed == true)
    run("paste_seed", { seed = "abc123" })
    check("paste_seed writes the screen's seed", SMODS.RunSelect.Setup.choices.seed == "ABC123",
      tostring(SMODS.RunSelect.Setup.choices.seed))
    local t = texts()
    check("the texts read the same seed", t:find(", seeded (seed ABC123).", 1, true) ~= nil, t)
    run("start_run")
    check("and start_run begins on it", started and started.seed == "ABC123", started and tostring(started.seed))
    run("toggle_seeded_run")
    run("start_run")
    check("seeded mode off starts a random seed even with one typed in", started and started.seed == nil,
      started and tostring(started.seed))
  end

  do
    board({ screen_deck = "b_green", screen_stake = 2 })
    G.GAME.challenge = "c_previous_run"
    G.CHALLENGES = { { id = "c_omelette_1", name = "Omelette", deck = { type = "Red Deck" } } }
    G.FUNCS.start_setup_run = function(e)
      G.FUNCS.start_run(e, { stake = 1, challenge = G.challenge_tab })
    end
    local real = G.FUNCS.start_run
    G.FUNCS.start_run = function(e, args)
      real(e, args)
      started.challenge = args.challenge
    end
    check("no challenge is selected yet", DeckFacts.selected_challenge() == nil)
    local line = CtxMisc.run_section() or ""
    check("the run setup line does not report the previous run's challenge",
      line:find("challenge", 1, true) == nil, line)
    G.NEURO.state = "MENU"
    G.OVERLAY_MENU = nil
    run("select_challenge", { id = "c_omelette_1" })
    local idx, entry = DeckFacts.selected_challenge()
    check("select_challenge is the single source start_challenge_run resolves", idx == 1 and entry == G.CHALLENGES[1])
    local q = MenuFlow.menu().query
    check("the menu names the selected challenge", q:find("Omelette", 1, true) ~= nil, q)
    G.NEURO.state = "RUN_SETUP"
    G.OVERLAY_MENU = { get_UIE_by_ID = function(_, id) return id == "run_setup_seed" and {} or nil end }
    run("start_run")
    check("start_run from run setup begins a normal run on the shown deck and stake, not the selected challenge",
      started and started.challenge == nil and started.deck == "b_green" and started.stake == 2,
      started and (tostring(started.challenge) .. "/" .. tostring(started.deck) .. "/" .. tostring(started.stake)))
  end

  do
    board({ screen_deck = "b_green", screen_stake = 1 })
    G.P_CENTERS.b_green = { key = "b_green", name = "internal_green", set = "Back", loc_txt = { name = "Stale Mod Name" } }
    G.P_CENTER_POOLS.Back = { RED, G.P_CENTERS.b_green }
    G.CHALLENGES = { { id = "c_omelette_1", name = "internal" } }
    local saved = rawget(_G, "localize")
    _G.localize = function(args, misc)
      if type(args) == "table" and args.key == "b_green" then return "Green Deck" end
      if args == "c_omelette_1" and misc == "challenge_names" then return "The Omelette" end
      return "ERROR"
    end
    local names = {}
    for _, row in ipairs(DeckFacts.list_selectable_backs()) do names[row.key] = row.name end
    local ch = DeckFacts.selectable_challenges()[1]
    _G.localize = saved
    check("the deck list names a deck as the game shows it", names.b_green == "Green Deck", tostring(names.b_green))
    check("the challenge list names a challenge as the game shows it", ch and ch.name == "The Omelette",
      ch and ch.name)
  end
end

done()
