-- Run from the mod directory: luajit tests/dashboard.lua
local function noop() end
local vanilla_mode = os.getenv('RUNSTATS_TEST_MODE') == 'vanilla'
local random_calls, random_value = 0, 0.25
function pseudorandom(seed, min, max) random_calls = random_calls + 1; return random_value end
Game = {
    init_game_object = function() return {} end,
    update_shop = function() G.STATE_COMPLETE = true; G.shop = {} end,
}
Card = {open = function(self)
    if not self.rejected and self.ability.set == 'Booster' then self.opening = true end
end}
function Card:get_p_dollars()
    if self.debuff then return 0 end
    local ability, total = self.ability or {}, 0
    if self.seal == 'Gold' and not ability.extra_enhancement then total = total + 3 end
    if ability.effect == 'Lucky Card' then
        if pseudorandom('lucky_money') < 1 / 15 then total = total + (ability.p_dollars or 0) end
    else total = total + (ability.p_dollars or 0) end
    return total + (not ability.extra_enhancement and (ability.perma_p_dollars or 0) or 0)
end
function Card:use_consumeable(area, copier)
    self.test_uses = (self.test_uses or 0) + 1
    return 'used', nil, copier
end
function eval_card(card)
    if card.test_income then
        local effect = {p_dollars = Card.get_p_dollars(card)}
        return SMODS and {playing_card = effect} or effect
    end
    return {active = card.test_active}
end
CardArea = {}
function CardArea:remove_card(card)
    card = card or self.cards[#self.cards]
    for i, candidate in ipairs(self.cards) do
        if candidate == card then
            table.remove(self.cards, i)
            card.area = nil
            return card
        end
    end
end
function CardArea:emplace(card)
    self.cards[#self.cards + 1] = card
    card.area = self
end
Blind = {
    set_blind = function(self, blind, reset)
        if not reset then self.chips = blind and blind.chips or 0; self.kind = blind and blind.kind end
    end,
    get_type = function(self) return self.kind end,
}
if vanilla_mode then SMODS = nil
else SMODS = {pseudorandom_probability = function(_, seed) return pseudorandom(seed) < 1 end} end
if SMODS then
    -- Run the real scoring/repetition loops with deterministic effect producers.
    local source_file = assert(io.open((os.getenv('SMODS_DIR') or '../smods-stable') .. '/src/utils.lua'))
    local source = source_file:read('*a'); source_file:close()
    assert(loadstring(assert(source:match('(function SMODS.score_card.-)\nfunction SMODS.calculate_main_scoring'))))()
    assert(loadstring(assert(source:match('(function SMODS.calculate_end_of_round_effects.-)\nfunction SMODS.calculate_destroying_cards'))))()
    SMODS.calculate_quantum_enhancements = noop
    SMODS.calculate_card_areas = noop
    SMODS.calculate_effect = noop
    SMODS.calculate_repetitions = function(card, context, reps)
        for _ = 2, card.test_repetitions or 1 do reps[#reps + 1] = {seals = {card = card}} end
    end
    SMODS.trigger_effects = function(effects) return {calculated = effects.active or (effects[1] or {}).active}, nil, 'preserved' end
    percent, percent_delta = 0, 0.1
    SMODS.calculate_individual_effect = function(effect, scored_card, key, amount)
        if key == 'dollars' or key == 'p_dollars' or key == 'h_dollars' then ease_dollars(amount); return true end
        return false
    end
end
Moveable = {}
function Moveable:extend()
    local class = setmetatable({}, {__index = self})
    class.__index = class
    return setmetatable(class, {
        __index = self,
        __call = function(cls, config) local o = setmetatable({}, cls); o:init(config); return o end,
    })
end
function Moveable.init(self, x, y, w, h)
    self.VT = {x = x, y = y, w = w, h = h}
    self.states = {drag = {}}
end
function localize(text) return text end
function number_format(n) return tostring(n) end
function darken(c) return c end
function UIBox_button(args)
    args.button = args.button or 'exit_overlay_menu'
    return {button = args.button ~= 'nil' and args.button or nil, config = args}
end
function create_UIBox_generic_options(args) return args end
function create_UIBox_win() return create_UIBox_generic_options({result = 'win', no_back = true, contents = {}}) end
function create_UIBox_game_over() return create_UIBox_generic_options({result = 'game_over', no_back = true, contents = {}}) end
function end_round() end
function set_hand_usage() end
function check_and_set_high_score() end
function ease_dollars(amount) G.GAME.dollars = G.GAME.dollars + amount end
function add_round_eval_row(config) return config.name end
function level_up_hand(card, hand, instant, amount)
    G.GAME.hands[hand].level = math.max(0, G.GAME.hands[hand].level + (amount or 1))
end
G = {
    STAGE = 1, STAGES = {RUN = 1, MAIN_MENU = 2}, STATES = {SHOP = 5, GAME_OVER = 9}, STATE = 2,
    FUNCS = {
        overlay_menu = function(args) G.last_overlay, G.last_overlay_config = args.definition, args.config end,
        use_card = function(e)
            local card = e.config.ref_table
            if card.ability.set == 'Booster' then card:open() end
        end,
        evaluate_play = function() end,
        evaluate_round = function()
            for _, config in ipairs(G.test_round_rows or {}) do add_round_eval_row(config) end
        end,
    },
    UIT = {R = 'R', C = 'C', T = 'T', O = 'O'},
    TILESIZE = 1,
    LANG = {font = {FONT = {getWidth = function(_, s) return #s * 0.45 end}, FONTSCALE = 1}},
    C = setmetatable({UI = setmetatable({}, {__index = function() return {1, 1, 1, 1} end})},
        {__index = function() return {1, 0.5, 0.2, 1} end}),
}
dofile('BalatroRunStats.lua')
local RS = RunStats
local function fresh()
    G.GAME = Game:init_game_object()
    G.GAME.round_resets = {ante = 1, blind_states = {}}
    G.GAME.current_round = {hands_played = 0, hands_left = 4}
    G.GAME.blind = setmetatable({}, {__index = Blind})
    G.GAME.round, G.GAME.dollars = 1, 4
    G.GAME.interest_cap, G.GAME.interest_amount = 25, 1
    G.GAME.modifiers = {}
    G.STAGE, G.STATE, G.shop, G.STATE_COMPLETE = 1, 2, nil, false
    RS._ante_sel = 0
    return G.GAME.run_stats
end
local function start(kind, target)
    G.GAME.current_round = {hands_played = 0, hands_left = 4}
    G.GAME.blind:set_blind({name = kind, kind = kind, chips = target}, false)
end
local function win(used, spare)
    G.GAME.current_round.hands_played, G.GAME.current_round.hands_left = used, spare
    G.GAME.chips = G.GAME.blind.chips
    end_round()
end
local function shop(cash)
    G.GAME.dollars, G.shop, G.STATE_COMPLETE = cash, nil, false
    Game:update_shop(0.1)
end
local s = fresh()
start('Small', 300)
check_and_set_high_score('hand', 100)
check_and_set_high_score('hand', 350)
assert(#s.blinds == 1 and s.blinds[1].best == 350)
assert(s.blinds[1].target == 300 and s.blinds[1].label == '1S')
G.GAME.chips = 450
assert(RS.score_chart_data().series[3].name == 'Total round score')
assert(RS.score_chart_data().series[3].values[1] == 450, 'live round total includes all hands')
G.GAME.blind:set_blind({name = 'Small'}, true)
assert(#s.blinds == 1, 'reset must not create history')
set_hand_usage('Pair'); set_hand_usage('Pair'); set_hand_usage('Flush')
assert(RS.poker_chart_data().series[1].values[1] == 2)
win(2, 2)
assert(s.blinds[1].won and s.blinds[1].completed)
assert(s.blinds[1].total_score == 300 and RS.score_chart_data().series[3].values[1] == 300,
    'completed total uses actual round chips, including adjustments, rather than summed hands')
assert(RS.hands_chart_data().series[2].values[1] == 2)
shop(12); shop(99)
assert(#s.shops == 1 and s.shops[1].cash == 12, 'shop re-entry must not replace entry cash')
G.GAME.round = 2
start('Boss', 600)
check_and_set_high_score('hand', 1000)
win(1, 3)
G.GAME.round_resets.ante = 2 -- boss advances ante before cash-out
shop(30)
assert(s.shops[2].ante == 1 and s.shops[2].cap == 25, 'boss shop belongs to played ante')
G.GAME.round = 3
start('Small', 800)
set_hand_usage('High Card')
check_and_set_high_score('hand', 50)
G.GAME.chips = 50
G.GAME.current_round.hands_played = 4
end_round()
assert(not s.blinds[3].won and #RS.hands_chart_data().antes == 2, 'failed blinds are not wins')
assert(RS.score_chart_data().series[3].values[3] == 50, 'failed rounds retain their total')
RS._ante_sel = 1
assert(#RS.score_chart_data().antes == 2 and #RS.cash_chart_data().antes == 2)
assert(#RS.poker_chart_data().antes == 2)
RS._ante_sel = 2
assert(#RS.hands_chart_data().antes == 0)
assert(#RS.score_chart_data().series[3].values == 1 and RS.score_chart_data().series[3].values[1] == 50)
assert(RS.poker_chart_data().antes[1] == 'High Card')
assert(RS.ante_in_progress(2) and not RS.ante_in_progress(1))
local pa = RS.pa()
pa.earned, pa.spent, pa.cset = 35, 20, {Tarot = 3, Planet = 2, Spectral = 1}
assert(RS.money_chart_data().antes[1] == '2*')
assert(RS.consumables_chart_data().series[3].values[1] == 1)
G.STATE = G.STATES.GAME_OVER
assert(not RS.ante_in_progress(2))
G.STATE = 2
RS._ante_sel = 0
-- Simulate save/load: history and deduplication live in G.GAME, not module state.
local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end
local saved = copy(s)
G.GAME.run_stats = saved
s = saved
assert(RS.stats() == saved and #RS.score_chart_data().antes == 3)
assert(RS.score_chart_data().series[3].values[1] == 300, 'round totals survive save/load')
local saved_total = s.blinds[2].total_score
s.blinds[2].total_score = nil
assert(RS.score_chart_data().series[3].values[2] == false, 'unrecorded historical totals are gaps')
s.blinds[2].total_score = saved_total
shop(90)
assert(#s.shops == 3)
-- Old saves have neither history nor per-ante hand types.
s = fresh()
s.blinds, s.shops = nil, nil
s.per_ante[1] = {career = {}, cset = {}, earned = 10, spent = 2}
assert(#RS.score_chart_data().antes == 0 and #RS.cash_chart_data().antes == 0)
assert(#RS.poker_chart_data().antes == 0 and RS.money_chart_data().series[1].values[1] == 10)
G.GAME.current_round.hands_played = 2
G.GAME.blind.kind, G.GAME.blind.chips = 'Big', 450
check_and_set_high_score('hand', 200)
assert(s.blinds[1].partial and RS.score_chart_data().antes[1] == '1B*')
set_hand_usage('Pair')
assert(s.per_ante[1].hand_types.Pair == 1)
G.GAME.modifiers.no_interest = true
shop(-5)
assert(s.shops[1].cash == -5 and s.shops[1].cap == false)
assert(#RS.cash_chart_data().series == 1)
-- Menu has four tabs and exactly the six intended chart objects.
G.FUNCS.runstats_tab_dash()
local charts, buttons, text = {}, {}, {}
local function walk(node)
    if type(node) ~= 'table' then return end
    if node.button then buttons[node.button] = true end
    if node.config and node.config.text then text[node.config.text] = true end
    if node.config and getmetatable(node.config.object) == RSChart then charts[#charts + 1] = node.config.object end
    for _, children in ipairs({node.contents or {}, node.nodes or {}}) do
        for _, child in ipairs(children) do walk(child) end
    end
end
walk(G.last_overlay)
assert(#charts == 6 and not buttons.runstats_tab_graphs)
local kinds = {}
for _, chart in ipairs(charts) do kinds[chart.config.kind] = (kinds[chart.config.kind] or 0) + 1 end
assert(kinds.line == 2 and kinds.stacked == 1 and kinds.grouped == 2 and kinds.horizontal == 1)
G.FUNCS.runstats_tab_stats()
text = {}; walk(G.last_overlay)
assert(not text['Odds Tracking'] and not text.Outcomes)
G.STAGE = G.STAGES.MAIN_MENU
G.last_overlay = nil
G.FUNCS.runstats_open()
assert(not G.last_overlay)
G.STAGE = G.STAGES.RUN
-- Exercise actual draw code: finite coordinates, nonnegative geometry and gap handling.
local counts = {}
local function finite(...)
    for _, v in ipairs({...}) do assert(type(v) == 'number' and v == v and math.abs(v) < 1e12) end
end
love = {graphics = {}}
local gfx = love.graphics
function prep_draw() counts = {} end
function gfx.setColor() end
function gfx.setFont() end
function gfx.setLineWidth(v) finite(v) end
function gfx.getLineWidth() return 1 end
function gfx.rectangle(_, x, y, w, h)
    finite(x, y, w, h); assert(w >= 0 and h >= 0); counts.rectangles = (counts.rectangles or 0) + 1
end
function gfx.circle(_, x, y, r) finite(x, y, r); counts.points = (counts.points or 0) + 1 end
function gfx.line(...) finite(...); counts.lines = (counts.lines or 0) + 1 end
function gfx.print(_, x, y, r, sx, sy) finite(x, y, r, sx, sy) end
function gfx.pop() counts.pops = (counts.pops or 0) + 1 end
local function draw(kind, data, log)
    local chart = RSChart({w = 4.25, h = 2.1, kind = kind, log = log, data = function() return data end})
    chart:draw()
    assert(counts.pops == 1)
    return counts
end
local series = {{name = 'Values', colour = {1, 0, 0}, values = {10, 30, 20}}}
local data = {antes = {'1S', '1B', '1BOSS'}, series = series}
assert(draw('line', data).lines == 2)
assert(draw('line', data, true).points == 3)
series[1].values = {10, false, 20}
assert(not draw('line', data).lines, 'missing points must break lines')
series[1].values = {-10, 0, 20}
draw('line', data)
series[1].values = {0, 0, 0}
draw('grouped', data); draw('stacked', data); draw('horizontal', data)
series[1].values = {10, 30, 20}
series[2] = {name = 'Other', colour = {0, 1, 0}, values = {15, 4, 6}}
draw('stacked', data); draw('grouped', data)
for _, kind in ipairs({'line', 'horizontal', 'stacked', 'grouped'}) do draw(kind, {antes = {}, series = {}}) end
for _, chart in ipairs(charts) do chart:draw() end
local labels, values = {}, {}
for i = 1, 40 do labels[i], values[i] = tostring(i) .. 'BOSS', i * 10 end
draw('line', {antes = labels, series = {{name = 'History', colour = {1, 1, 1}, values = values}}})
labels, values = {}, {}
for i = 1, 12 do labels[i], values[i] = 'Flush House', i end
draw('horizontal', {antes = labels, series = {{name = 'Hands', colour = {1, 1, 1}, values = values}}})
-- Packs are counted by actual openings, including tag packs, once per pack.
s = fresh()
local function pack(kind, size, explicit)
    return setmetatable({ability = {set = 'Booster', name = size .. ' ' .. kind .. ' Pack'},
        config = {center = {kind = explicit and kind or nil}}}, {__index = Card})
end
for _, kind in ipairs({'Standard', 'Arcana', 'Celestial', 'Spectral', 'Buffoon'}) do
    for _, size in ipairs({'Normal', 'Jumbo', 'Mega'}) do
        local card = pack(kind, size, size == 'Mega')
        G.FUNCS.use_card({config = {ref_table = card}})
        card:open() -- repeated calls on an already-opening pack do not double count
    end
    assert(RS.pack_count(kind) == 3)
end
assert(s.packs_opened == 15 and RS.pa_sum('packs') == 15)
local rejected = pack('Standard', 'Normal'); rejected.rejected = true
G.FUNCS.use_card({config = {ref_table = rejected}})
assert(RS.pack_count('Standard') == 3)
G.GAME.round_resets.ante = 2
pack('Standard', 'Normal'):open() -- free/tag pack bypasses use_card
RS._ante_sel = 2
assert(RS.pack_count('Standard') == 1 and RS.pa_sum('packs') == 1)
RS._ante_sel = 1
assert(RS.pack_count('Standard') == 3)
RS.rebuild_sliceview()
assert(RS._sliceview.standard_packs == '3' and RS._sliceview.packs == '15')
G.FUNCS.runstats_tab_stats(); text = {}; walk(G.last_overlay)
assert(text['Standard Packs'] and text['Booster Packs'])
s.per_ante[1].pack_types = nil -- pre-update save, no invented pack-type history
assert(RS.pack_count('Standard') == 0 and RS.pa_sum('packs') == 15)
assert(RS.pack_count('Other') == 15, 'old totals remain visible as unclassified packs')
pack('Standard', 'Normal'):open()
assert(s.packs_opened == 17 and s.per_ante[2].pack_types.Standard == 2)
-- Both result screens expose stats and every tab/filter returns to the result.
for _, screen in ipairs({'win', 'game_over'}) do
    G.STATE = screen == 'game_over' and G.STATES.GAME_OVER or 2
    local result = _G['create_UIBox_' .. screen]()
    assert(result.contents[1].button == 'runstats_open_' .. screen)
    assert(not RS._building_result)
    G.FUNCS['runstats_open_' .. screen]()
    assert(RS._ante_sel == 0 and RS._return_screen == screen)
    assert(G.last_overlay.back_func == 'runstats_return_to_result' and G.last_overlay_config.no_esc)
    G.FUNCS.runstats_tab_dash()
    G.FUNCS.runstats_ante_up()
    assert(G.last_overlay.back_func == 'runstats_return_to_result' and G.last_overlay_config.no_esc)
    G.FUNCS.runstats_return_to_result()
    assert(G.last_overlay.result == screen and not RS._return_screen)
    assert(G.last_overlay_config.no_esc and RS.stats() == s)
end
G.STATE = 2
G.FUNCS.runstats_open()
assert(G.last_overlay.back_func == 'exit_overlay_menu' and not G.last_overlay_config.no_esc)
assert(#create_UIBox_generic_options({contents = {}}).contents == 0, 'ordinary menus get no extra button')
G.STAGE = G.STAGES.MAIN_MENU
assert(#create_UIBox_win().contents == 0, 'no stale stats outside a run')
G.STAGE = G.STAGES.RUN
-- Drawn mode follows completed deck-to-hand transfers, not deck shrinkage.
s = fresh()
local function area()
    return setmetatable({cards = {}}, {__index = CardArea})
end
G.deck, G.hand, G.discard = area(), area(), area()
local ace = {base = {suit = 'Hearts', id = 14}}
local duplicate = {base = {suit = 'Hearts', id = 14}}
local two = {base = {suit = 'Spades', id = 2}}
local function move(from, to, card)
    local removed = from:remove_card(card)
    if removed then to:emplace(removed) end
end
G.deck:emplace(ace); G.deck:emplace(duplicate); G.deck:emplace(two)
assert(s.cards_drawn == 0)
local pending = G.deck:remove_card(ace)
assert(s.cards_drawn == 0, 'scheduled/removed cards are not draws until received by hand')
G.hand:emplace(pending)
assert(s.cards_drawn == 1 and s.per_ante[1].cards_drawn['Hearts:14'] == 1)
move(G.deck, G.hand, duplicate)
assert(s.cards_drawn == 2 and s.per_ante[1].cards_drawn['Hearts:14'] == 2)
move(G.deck, G.discard, two)
move(G.discard, G.hand, two)
assert(s.cards_drawn == 2, 'discard-to-hand and deck-to-discard are not draws')
move(G.hand, G.deck, ace)
move(G.deck, G.hand, ace)
assert(s.cards_drawn == 3 and RS.pa_sum('drawn') == 3, 'drawing the same card again counts again')
local created = {base = {suit = 'Clubs', id = 4}}
G.hand:emplace(created)
assert(s.cards_drawn == 3, 'cards created directly in hand are not deck draws')
G.GAME.round_resets.ante = 2
move(G.hand, G.deck, two); move(G.deck, G.hand, two)
assert(s.cards_drawn == 4 and s.per_ante[2].cards_drawn['Spades:2'] == 1)
RS._card_mode, RS._card_suit, RS._card_rank = 3, 1, 1
local card_data = RS.card_chart_data()
assert(card_data.mode == 'Drawn' and card_data.values[13][2] == 3 and card_data.values[1][1] == 1)
RS._ante_sel, RS._card_suit, RS._card_rank = 1, 3, 14 -- Hearts, Ace
card_data = RS.card_chart_data()
assert(#card_data.ranks == 1 and #card_data.suits == 1 and card_data.values[1][1] == 3)
RS._ante_sel = 2
assert(RS.card_chart_data().values[1][1] == 0)
RS._card_suit, RS._card_rank = 1, 1
assert(RS.card_chart_data().values[1][1] == 1)
G.FUNCS.runstats_cards_mode()
assert(RS._card_mode == 4, 'mode cycles Drawn to Use rate')
G.FUNCS.runstats_cards_mode()
assert(RS._card_mode == 5, 'mode cycles Use rate to Triggers')
G.FUNCS.runstats_cards_mode()
assert(RS._card_mode == 1, 'mode cycles Triggers back to Played')
G.FUNCS.runstats_cards_mode(); G.FUNCS.runstats_cards_mode()
assert(RS._card_mode == 3)
RSCardChart({w = 13.4, h = 4.6, data = RS.card_chart_data}):draw()
s.per_ante[1].cards_drawn = nil -- old saves keep totals, without invented card identities
RS._ante_sel = 1
assert(RS.pa_sum('drawn') == 3 and RS.card_chart_data().values[13][2] == 0)
move(G.hand, G.deck, two)
local stale = G.deck:remove_card(two)
local old = s
s = fresh()
G.hand:emplace(stale)
assert(s.cards_drawn == 0 and old.cards_drawn == 4, 'pending draws cannot leak across runs')
-- Score averages and medians use actual samples, including zero-score hands.
s = fresh()
for _, score in ipairs({0, 10, 20, 1000}) do check_and_set_high_score('hand', score) end
local scores = RS.score_summary()
assert(scores.count == 4 and scores.average == 257.5 and scores.median == 15)
assert(s.per_ante[1].hand_scores[1] == 0 and s.per_ante[1].hand_scores[4] == 1000, 'median must not sort saved history')
G.GAME.round_resets.ante = 2
check_and_set_high_score('hand', 100)
RS._ante_sel = 2
assert(RS.score_summary().median == 100 and RS.score_summary().count == 1)
RS._ante_sel = 0
assert(RS.score_summary().count == 5 and RS.score_summary().median == 20)
RS.rebuild_sliceview()
assert(RS._sliceview.average_hand == '226' and RS._sliceview.median_hand == '20')
s.per_ante[3] = {best_score = 50000, career = {}, spent = 0} -- old data is not a score sample
assert(RS.score_summary().count == 5)
local consistency = RS.consistency_chart_data()
assert(consistency.series[1].values[3] == false, 'untracked antes are chart gaps')
RS._ante_sel = 3
assert(RS.score_summary().count == 0 and #RS.consistency_chart_data().antes == 0)
RS.rebuild_sliceview()
assert(RS._sliceview.average_hand == '--' and RS._sliceview.median_hand == '--')
-- Spending uses successful charge amounts and preserves unclassified/old losses.
RS._ante_sel = 0
G.GAME.round_resets.ante = 1
s.per_ante[1].spent = 50
for category, amount in pairs({rerolls = 5, jokers = 10, packs = 8, vouchers = 10, cards = 3, consumables = 4}) do
    RS.record_spend(category, amount)
end
RS.record_spend('jokers', 0); RS.record_spend('jokers', -5)
local spending, total = RS.spending_summary()
assert(total == 50 and spending.other == 10 and spending.jokers == 10)
for set, expected in pairs({Booster = 'packs', Voucher = 'vouchers', Joker = 'jokers', Default = 'cards',
    Enhanced = 'cards', Tarot = 'consumables', Planet = 'consumables', Spectral = 'consumables'}) do
    assert(RS.purchase_category({ability = {set = set}}) == expected)
end
G.GAME.round_resets.ante = 2
s.per_ante[2].spent = 12
RS.record_spend('rerolls', 12)
RS._ante_sel = 2
spending, total = RS.spending_summary()
assert(total == 12 and spending.rerolls == 12 and spending.other == 0)
RS._ante_sel = 3
assert(#RS.spending_chart_data().antes == 0)
RS._ante_sel = 0
local spend_data = RS.spending_chart_data()
local sum = 0
for _, amount in ipairs(spend_data.series[1].values) do sum = sum + amount end
assert(sum == 62 and #spend_data.antes == 7)
-- Analysis is a view within Trends; existing Overview charts remain available.
RS._trend_view = 'overview'
G.FUNCS.runstats_tab_dash()
G.FUNCS.runstats_trend_view()
assert(RS._trend_view == 'analysis')
charts = {}; walk(G.last_overlay)
assert(#charts == 2 and charts[1].config.kind == 'line' and charts[2].config.kind == 'horizontal')
for _, chart in ipairs(charts) do chart:draw() end
G.FUNCS.runstats_trend_view()
assert(RS._trend_view == 'economy')
G.FUNCS.runstats_trend_view()
assert(RS._trend_view == 'deck')
G.FUNCS.runstats_trend_view()
charts = {}; walk(G.last_overlay)
assert(RS._trend_view == 'overview' and #charts == 6)
-- Use rate measures draws eventually played once, with matched sample coverage.
s = fresh()
G.deck, G.hand, G.discard = area(), area(), area()
local first = {base = {suit = 'Hearts', id = 14}, playing_card = 1, sort_id = 99}
local second = {base = {suit = 'Hearts', id = 14}, playing_card = 2, sort_id = 99}
G.deck:emplace(first); G.deck:emplace(second)
move(G.deck, G.hand, first); move(G.deck, G.hand, second)
RS._card_mode, RS._card_suit, RS._card_rank = 4, 3, 14
local function play(cards)
    G.play = {cards = cards}
    G.FUNCS.evaluate_play()
end
play({first})
local usage = RS.card_chart_data()
assert(usage.rate and usage.values[1][1] == 50 and usage.drawn_total == 2 and usage.played_total == 1)
play({first})
assert(RS.card_chart_data().values[1][1] == 50, 'a replay without another draw does not inflate use rate')
-- Saved tokens stay attached to stable playing-card IDs even when sort IDs change.
G.GAME.run_stats = copy(s); s = G.GAME.run_stats
second.sort_id = 1000
play({second})
assert(RS.card_chart_data().values[1][1] == 100)
move(G.hand, G.deck, first); move(G.deck, G.hand, first)
assert(math.abs(RS.card_chart_data().values[1][1] - 200 / 3) < 0.0001)
G.GAME.round_resets.ante = 2
move(G.hand, G.deck, second); move(G.deck, G.hand, second)
play({second})
usage = RS.card_chart_data()
assert(usage.values[1][1] == 75 and usage.drawn_total == 4, 'aggregate rate must use weighted counts')
RS._ante_sel = 1
assert(math.abs(RS.card_chart_data().values[1][1] - 200 / 3) < 0.0001)
RS._ante_sel = 2
assert(RS.card_chart_data().values[1][1] == 100)
RS._card_suit = 1
assert(RS.card_chart_data().values[1][1] == false, 'no draws is missing data, not a 0% success rate')
RSCardChart({w = 13.4, h = 4.6, data = RS.card_chart_data}):draw()
G.FUNCS.runstats_tab_cards()
assert(RS._card_mode == 4)
-- Old played/drawn totals must not contaminate the new matched sample.
s.per_ante[2].cards_drawn['Spades:14'] = 100
s.per_ante[2].cards_played = {['Spades:14'] = 100}
assert(RS.card_chart_data().values[1][1] == false)
if vanilla_mode then
    assert(SMODS == nil, 'standalone mode must not create a fake SMODS namespace')
    s = fresh()
    G.jokers, G.playing_cards = {cards = {}}, {}
    G.GAME.probabilities = {normal = 1}
    local before = random_calls
    random_value = 0.25
    assert(pseudorandom('space') == 0.25 and random_calls == before + 1)
    assert(s.probs.space.rolls == 1 and s.probs.space.hits == 0, 'use strict vanilla comparison at the threshold')
    random_value = 0.1
    assert(pseudorandom('space') == 0.1 and s.probs.space.hits == 1)
    local denominators = {bloodstone = 2, ['8ball'] = 4, lucky_mult = 5, lucky_money = 15,
        business = 2, wheel_of_fortune = 4, gros_michel = 6, cavendish = 1000, parking = 2, halu9 = 2, glass = 4}
    for seed, denominator in pairs(denominators) do
        before = random_calls
        assert(pseudorandom(seed) == 0.1 and random_calls == before + 1)
        assert(s.probs[seed].rolls == 1 and s.probs[seed].hits == (0.1 < 1 / denominator and 1 or 0))
    end
    pseudorandom('unrelated'); pseudorandom('space', 1, 10)
    assert(not s.probs.unrelated and s.probs.space.rolls == 2, 'ignore unrelated/ranged random calls')
    for _, normal in ipairs({1, 2, 4, 8, 1}) do
        G.GAME.probabilities.normal = normal
        before = random_calls
        RS.rebuild_probview()
        assert(RS._probview.p_bloodstone_odds == normal .. ' in 2')
        assert(RS._probview.p_space_odds == normal .. ' in 4')
        assert(RS._probview.p_halu_odds == normal .. ' in 2')
        assert(random_calls == before, 'viewing probabilities must not advance RNG')
    end
    G.jokers.cards = {{config = {center_key = 'j_space'}, ability = {extra = 10}}}
    random_value = 0.25
    G.GAME.probabilities.normal = 1
    pseudorandom('space')
    assert(s.probs.space.den == 10 and s.probs.space.hits == 1)
    G.GAME.probabilities.normal = 4
    pseudorandom('space')
    RS.rebuild_probview()
    assert(s.probs.space.hits == 2 and RS._probview.p_space_odds == '4 in 10')
    assert(s.per_ante[1].probs.space.rolls == 4)
    RS._ante_sel = 2
    RS.rebuild_probview()
    assert(RS._probview.p_space_odds == '4 in 10' and RS._probview.p_space == '0/0 (--)')
    RS._ante_sel = 0
    -- Lovely's module and the manifest entry must never wrap hooks twice.
    local init, rng = Game.init_game_object, pseudorandom
    package.preload['runstats.runtime'] = assert(loadfile('BalatroRunStats.lua'))
    assert(require('runstats.runtime') == RS)
    assert(dofile('BalatroRunStats.lua') == RS)
    assert(Game.init_game_object == init and pseudorandom == rng)
    print('Vanilla checks passed: no SMODS, all built-in probabilities, exact RNG preservation, Oops stacking and single initialization')
else
-- Exercise the real Steamodded tooltip probability helper with Oops contexts.
local smods_dir = os.getenv('SMODS_DIR') or '../smods-stable'
local utils = assert(io.open(smods_dir .. '/src/utils.lua', 'r'))
local utils_source = utils:read('*a'); utils:close()
local probability_helper = assert(utils_source:match('(function SMODS.get_probability_vars.-)\nfunction SMODS.pseudorandom_probability'))
assert(loadstring(probability_helper))()
function SMODS.find_card(key)
    local found = {}
    for _, card in ipairs((G.jokers or {}).cards or {}) do
        if card.config.center_key == key and not card.debuff then found[#found + 1] = card end
    end
    return found
end
function SMODS.calculate_context(context)
    if context.mod_probability then
        return {numerator = context.numerator * 2 ^ #SMODS.find_card('j_oops')}
    end
    return {}
end
s = fresh()
G.jokers = {cards = {}}
G.GAME.probabilities = {normal = 1}
local function oops(count)
    G.jokers.cards = {}
    for i = 1, count do G.jokers.cards[i] = {config = {center_key = 'j_oops'}} end
    G.GAME.probabilities.normal = 2 ^ count
    RS.rebuild_probview()
end
oops(0)
assert(RS._probview.p_bloodstone_odds == '1 in 2' and RS._probview.p_space_odds == '1 in 4')
oops(1)
assert(RS._probview.p_bloodstone_odds == '2 in 2' and RS._probview.p_space_odds == '2 in 4')
assert(RS._probview.p_lucky_money_odds == '2 in 15' and RS._probview.p_cavendish_odds == '2 in 1000')
oops(2)
assert(RS._probview.p_bloodstone_odds == '4 in 2' and RS._probview.p_space_odds == '4 in 4')
oops(3)
assert(RS._probview.p_glass_odds == '8 in 4')
oops(1)
G.jokers.cards[2] = {config = {center_key = 'j_oops'}, debuff = true}
RS.rebuild_probview()
assert(RS._probview.p_bloodstone_odds == '2 in 2', 'debuffed Oops must follow tooltip behavior')
s.probs.bloodstone = {rolls = 3, hits = 2, num = 1, den = 2}
RS.rebuild_probview()
assert(RS._probview.p_bloodstone == '2/3 (66.7%)' and RS._probview.p_bloodstone_odds == '2 in 2')
RS._ante_sel = 2 -- historical filter affects observations, not current listed odds
RS.rebuild_probview()
assert(RS._probview.p_bloodstone_odds == '2 in 2' and RS._probview.p_bloodstone == '0/0 (--)')
RS._ante_sel = 0
oops(0)
assert(RS._probview.p_bloodstone_odds == '1 in 2', 'selling Oops updates without another roll')
assert(s.probs.bloodstone.num == 1 and s.probs.bloodstone.rolls == 3 and s.probs.bloodstone.hits == 2)
oops(1)
local source_card = {config = {center_key = 'j_example'}}
SMODS.pseudorandom_probability(source_card, 'custom', 2, 3, 'custom_identifier', true)
assert(s.probs.custom.identifier == 'custom_identifier' and s.probs.custom.no_mod and s.probs.custom.card_key == 'j_example')
RS.rebuild_probview()
assert(RS._probview.p_custom_odds == '2 in 3', 'no_mod rolls stay unmodified')
SMODS.pseudorandom_probability(source_card, 'custom_modified', 2, 3)
RS.rebuild_probview()
assert(RS._probview.p_custom_modified_odds == '4 in 3', 'preserve numerator and denominator without reduction')
SMODS.pseudorandom_probability(source_card, 'halu1', 1, 2)
RS.rebuild_probview()
assert(RS._probview.p_halu_odds == '2 in 2')
local real_helper = SMODS.get_probability_vars
SMODS.get_probability_vars = nil
RS.rebuild_probview()
assert(RS._probview.p_bloodstone_odds == '2 in 2' and RS._probview.p_custom_odds == '2 in 3')
SMODS.get_probability_vars = real_helper
assert(s.probs.custom.rolls == 1 and s.probs.custom_modified.rolls == 1, 'SMODS rolls must not also enter the vanilla tracker')
end
s = fresh()
RS._tab = 'stats'
assert(RS.max_ante() == 0 and #RS.played_antes() == 0)
G.FUNCS.runstats_ante_up()
assert(RS._ante_sel == 0, 'no played antes must leave All selected')
buttons = {}; walk(G.last_overlay)
assert(not buttons.runstats_ante_up and not buttons.runstats_ante_down)
s.per_ante[1] = {career = {c_hands_played = 1}}
G.GAME.round_scores = {furthest_ante = {amt = 1}}
G.FUNCS.runstats_ante_up()
assert(RS._ante_sel == 1 and RS.max_ante() == 1)
G.FUNCS.runstats_ante_up()
assert(RS._ante_sel == 1)
buttons = {}; walk(G.last_overlay)
assert(not buttons.runstats_ante_up and buttons.runstats_ante_down)
G.FUNCS.runstats_ante_down()
assert(RS._ante_sel == 0)
-- Future-ante shop activity does not unlock the slicer before a blind starts.
s.per_ante[2] = {career = {}, spent = 10}
assert(RS.max_ante() == 1)
s.blinds = {{ante = 1}, {ante = 2}}
assert(RS.max_ante() == 2)
G.GAME.round_scores.furthest_ante.amt = 2
G.FUNCS.runstats_ante_up(); G.FUNCS.runstats_ante_up()
assert(RS._ante_sel == 2)
-- Endless antes are selectable, with no fixed ceiling at 8.
for ante = 1, 12 do s.per_ante[ante] = {career = {c_hands_played = 1}} end
G.GAME.round_scores.furthest_ante.amt = 12
RS._ante_sel = 8
G.FUNCS.runstats_ante_up()
assert(RS._ante_sel == 9 and RS.max_ante() == 12)
for i = 1, 6 do G.FUNCS.runstats_ante_up() end
assert(RS._ante_sel == 12)
G.FUNCS.runstats_ante_down()
assert(RS._ante_sel == 11)
-- Ante gaps are skipped in both directions.
s.per_ante = {[1] = {career = {}}, [3] = {career = {}}, [12] = {career = {}}}
s.blinds = {{ante = 1}, {ante = 3}, {ante = 12}}
RS._ante_sel = 1
G.FUNCS.runstats_ante_up(); assert(RS._ante_sel == 3)
G.FUNCS.runstats_ante_up(); assert(RS._ante_sel == 12)
G.FUNCS.runstats_ante_down(); assert(RS._ante_sel == 3)
G.FUNCS.runstats_ante_down(); assert(RS._ante_sel == 1)
G.FUNCS.runstats_ante_down(); assert(RS._ante_sel == 0)
-- A new run clears an obsolete selection from a previous endless run.
s = fresh()
RS._ante_sel = 12
G.FUNCS.runstats_open()
assert(RS._ante_sel == 0 and RS.max_ante() == 0)
-- Income categories are earned at payout time, with the source blind's ante.
s = fresh()
start('Boss', 600); win(1, 3)
G.GAME.round_resets.ante = 2
G.test_round_rows = {
    {name = 'blind1', dollars = 5}, {name = 'hands', dollars = 3},
    {name = 'interest', dollars = 4}, {name = 'joker1', dollars = 2},
    {name = 'discards', dollars = 1}, {name = 'bottom', dollars = 15},
}
G.FUNCS.evaluate_round()
local income, earned = RS.income_summary()
assert(earned == 0 and not income.interest, 'unclaimed rewards are not income')
assert(s.round_income.ante == 1)
RS.prepare_cashout_income(); ease_dollars(15)
income, earned = RS.income_summary()
assert(earned == 15 and income.blinds == 5 and income.hands == 3 and income.interest == 4 and income.jokers == 2 and income.other == 1)
assert(s.per_ante[1].earned == 15 and s.per_ante[2] == nil, 'boss payout is credited to the blind ante')
ease_dollars(7); RS.record_income('sales', 7)
ease_dollars(3)
RS.record_income('sales', 0); RS.record_income('sales', -2)
income, earned = RS.income_summary()
assert(earned == 25 and income.sales == 7 and income.other == 4)
local income_data = RS.income_chart_data()
for index, ante in ipairs({1, 2}) do
    local sum = 0
    for _, series in ipairs(income_data.series) do sum = sum + series.values[index] end
    assert(sum == s.per_ante[ante].earned)
end
RS._ante_sel = 1
income, earned = RS.income_summary()
assert(earned == 15 and not income.sales)
RS._ante_sel = 0
local old_stats = s
G.FUNCS.evaluate_round(); RS.prepare_cashout_income()
s = fresh(); ease_dollars(2)
assert(RS.income_summary().blinds == nil and s.money_earned == 2, 'pending income cannot leak into a different run')
assert(old_stats.money_earned == 25)
s = fresh()
s.round_income = {ante = 1, categories = {blinds = 5, hands = 3, interest = 4}}
RS.prepare_cashout_income(); ease_dollars(5)
income, earned = RS.income_summary()
assert(earned == 5 and not income.blinds and income.other == 5, 'adjusted net payouts must not fabricate a split')
s.per_ante[2] = {earned = 40, career = {}}
RS._ante_sel = 2
assert(RS.income_summary().other == 40, 'legacy income remains visible without fabricated categories')
-- Per-ante snapshots retain real deck traits and every poker hand's level.
s = fresh()
G.GAME.hands = {Pair = {level = 1}, Flush = {level = 1}, ['High Card'] = {level = 1}, Straight = {level = 1}}
G.playing_cards = {
    {base = {suit = 'Hearts', id = 2}},
    {base = {suit = 'Spades', id = 14}, config = {center = {key = 'm_glass', set = 'Enhanced'}}, seal = 'Red', edition = {foil = true}},
    {base = {suit = 'Hearts', id = 14}, config = {center = {key = 'm_steel', set = 'Enhanced'}}, seal = 'Blue', edition = {type = 'holo'}},
    {base = {suit = 'Diamonds', id = 13}, config = {center = {key = 'm_gold', set = 'Enhanced'}}, seal = 'Gold', edition = {polychrome = true}},
    {base = {suit = 'Clubs', id = 5}, seal = 'Purple', edition = {negative = true}},
    {base = {suit = 'Other', id = 10}, config = {center = {key = 'm_stone', set = 'Enhanced'}}},
}
RS.capture_snapshot()
assert(next(s.per_ante) == nil, 'snapshots must not unlock an unplayed ante')
start('Boss', 600)
local deck = s.per_ante[1].deck_snapshot
assert(deck.total == 6 and deck.suits.Hearts == 2 and deck.ranks['14'] == 2)
assert(deck.enhancements.Base == 2 and deck.enhancements.m_glass == 1 and deck.seals.None == 2)
assert(deck.editions.None == 2 and deck.editions.foil == 1 and deck.editions.holo == 1)
level_up_hand(nil, 'Pair', true, 1)
level_up_hand(nil, 'Flush', true, -1)
assert(s.per_ante[1].hand_levels.Pair == 2 and s.per_ante[1].hand_levels.Flush == 0)
win(1, 3)
G.GAME.round_resets.ante = 2
level_up_hand(nil, 'Pair', true, 2) -- shop after boss, before next played ante
assert(s.per_ante[1].hand_levels.Pair == 4 and not s.per_ante[2])
start('Small', 800)
level_up_hand(nil, 'Pair', true, 1)
table.insert(G.playing_cards, {base = {suit = 'Clubs', id = 3}, seal = 'Red'})
RS.capture_snapshot()
assert(s.per_ante[1].hand_levels.Pair == 4 and s.per_ante[2].hand_levels.Pair == 5)
assert(s.per_ante[1].deck_snapshot.total == 6 and s.per_ante[2].deck_snapshot.total == 7)
s.per_ante[1].hand_types = {Pair = 10, Flush = 4, ['High Card'] = 3, Straight = 1}
local levels = RS.hand_levels_chart_data()
assert(levels.hands.Pair[1] == 4 and levels.hands.Pair[2] == 5 and levels.hands.Straight[1] == 1)
assert(levels.hands.Flush[1] == 0, 'level zero is a real value, not missing data')
for mode = 1, 5 do
    RS._deck_mode = mode
    local history, breakdown = RS.deck_history_chart_data(), RS.deck_breakdown_chart_data()
    assert(#history.series <= 5 and breakdown.ante == 2 and breakdown.total == 7)
    for index, total in ipairs({6, 7}) do
        local sum = 0
        for _, series in ipairs(history.series) do sum = sum + series.values[index] end
        assert(sum == total, 'grouping must preserve every card')
    end
    local sum = 0
    for _, count in ipairs(breakdown.series[1].values) do sum = sum + count end
    assert(sum == 7)
end
RS._ante_sel = 1
assert(RS.deck_breakdown_chart_data().ante == 1 and RS.deck_breakdown_chart_data().total == 6)
assert(RS.hand_levels_chart_data().hands.Flush[1] == 0)
RS._ante_sel = 0
G.GAME.run_stats = copy(s); s = G.GAME.run_stats
assert(s.per_ante[1].deck_snapshot.total == 6 and s.per_ante[2].hand_levels.Pair == 5, 'snapshots survive save/load')
-- Missing historical snapshots stay missing.
s.per_ante[3] = {career = {}, earned = 10}
RS._ante_sel = 3
assert(#RS.deck_history_chart_data().antes == 0 and #RS.deck_breakdown_chart_data().antes == 0)
assert(#RS.hand_levels_chart_data().antes == 0)
RS._ante_sel = 0
RS._trend_view = 'economy'; G.FUNCS.runstats_tab_dash()
charts, buttons = {}, {}; walk(G.last_overlay)
assert(#charts == 2 and not buttons.runstats_level_hand)
for _, chart in ipairs(charts) do chart:draw() end
G.FUNCS.runstats_trend_view()
charts, buttons = {}, {}; walk(G.last_overlay)
assert(RS._trend_view == 'deck' and #charts == 2 and buttons.runstats_deck_mode)
for mode = 1, 5 do
    G.FUNCS.runstats_deck_mode()
    charts = {}; walk(G.last_overlay)
    for _, chart in ipairs(charts) do chart:draw() end
end
G.FUNCS.runstats_trend_view()
assert(RS._trend_view == 'overview')
-- Every hand is represented, with shared paths merged at points and intervals.
s = fresh()
local poker_hands = {'Flush Five','Flush House','Five of a Kind','Straight Flush','Four of a Kind','Full House',
    'Flush','Straight','Three of a Kind','Two Pair','Pair','High Card'}
local function levels_with(overrides)
    local result = {}
    for _, hand in ipairs(poker_hands) do result[hand] = 1 end
    for hand, level in pairs(overrides or {}) do result[hand] = level end
    return result
end
s.per_ante[1] = {career = {}, hand_levels = levels_with()}
levels = RS.hand_levels_chart_data()
assert(#levels.series == 1 and levels.series[1].name == 'All hands' and #levels.points[1].hands == 12)
assert(levels.series[1].values[1] == 1)
RSChart({w = 6.4, h = 3.2, kind = 'line', data = RS.hand_levels_chart_data}):draw()
assert(counts.lines == 1, 'one ante still shows the combined horizontal line')
s.per_ante[2] = {career = {}, hand_levels = levels_with({Flush = 2})}
levels = RS.hand_levels_chart_data()
local names = {}
for _, series in ipairs(levels.series) do names[series.name] = true end
assert(names['Other hands'] and names.Flush and not names['All hands'])
s.per_ante[3] = {career = {}, hand_levels = levels_with({Flush = 3, Straight = 2, ['High Card'] = 2})}
s.per_ante[4] = {career = {}, hand_levels = levels_with({Flush = 4, Straight = 2, ['High Card'] = 2})}
s.per_ante[5] = {career = {}, hand_levels = levels_with({Flush = 4, Straight = 3, ['High Card'] = 2})}
s.per_ante[6] = {career = {}, hand_levels = levels_with({Flush = 4, Straight = 3, ['High Card'] = 3})}
s.per_ante[7] = {career = {}} -- missing snapshot must not bridge a line
s.per_ante[8] = {career = {}, hand_levels = levels_with({Flush = 4, Straight = 4, ['High Card'] = 4})}
levels = RS.hand_levels_chart_data()
names = {}
for _, series in ipairs(levels.series) do names[series.name] = true end
assert(names['Straight + High Card'] and names['Flush + Straight + High Card'])
local saw_shared_interval, saw_split, saw_rejoin = false, false, false
for _, segment in ipairs(levels.segments) do
    assert(not (segment.i == 6 or segment.i == 7), 'missing snapshots must break paths')
    local label = levels.series[segment.series].name
    if segment.i == 3 and label == 'Straight + High Card' then
        saw_shared_interval = true
        assert(segment.from == 2 and segment.to == 2 and #segment.hands == 2)
    end
    if segment.i == 4 and label == 'Straight' then saw_split = true end
    if segment.i == 4 then assert(label ~= 'Straight + High Card', 'do not connect a shared line through a split') end
end
for _, point in ipairs(levels.points) do
    if point.i == 6 and levels.series[point.series].name == 'Straight + High Card' then saw_rejoin = true end
end
assert(saw_shared_interval and saw_split and saw_rejoin)
for index = 1, 8 do
    local covered = {}
    for _, point in ipairs(levels.points) do
        if point.i == index then
            for _, hand in ipairs(point.hands) do assert(not covered[hand]); covered[hand] = true end
        end
    end
    for _, hand in ipairs(poker_hands) do assert((covered[hand] or false) == (index ~= 7)) end
end
RSChart({w = 6.4, h = 3.2, kind = 'line', data = RS.hand_levels_chart_data}):draw()
RS._ante_sel = 1
assert(RS.hand_levels_chart_data().series[1].name == 'All hands')
RS._ante_sel = 3
levels = RS.hand_levels_chart_data(); names = {}
for _, series in ipairs(levels.series) do names[series.name] = true end
assert(names['Straight + High Card'] and names.Flush and names['Other hands'])
RS._ante_sel = 0
-- Income scopes identify actual gains, preserve returns and isolate coroutines.
s = fresh()
local joker_source = {ability = {set = 'Joker'}}
local card_source = {ability = {set = 'Tarot'}}
local a, b, c = RS.with_card_income(joker_source, function() ease_dollars(5); return 4, nil, 'kept' end)
assert(a == 4 and b == nil and c == 'kept')
RS.with_card_income(card_source, function() ease_dollars(7) end)
ease_dollars(2)
income, earned = RS.income_summary()
assert(earned == 14 and income.jokers == 5 and income.cards == 7 and income.other == 2)
RS.with_card_income(joker_source, function() RS.prepare_income('sales'); ease_dollars(4) end)
RS.with_card_income(joker_source, function() ease_dollars(0); ease_dollars(-3) end)
income, earned = RS.income_summary()
assert(earned == 18 and income.sales == 4 and income.jokers == 5 and income.other == 2)
RS.with_effect_income({card = joker_source}, function() ease_dollars(3) end)
RS.with_effect_income({}, function() ease_dollars(2) end)
income = RS.income_summary()
assert(income.jokers == 8 and income.cards == 9)
local worker = coroutine.create(function()
    RS.with_card_income(joker_source, function() coroutine.yield(); ease_dollars(5) end)
end)
assert(coroutine.resume(worker))
ease_dollars(2) -- main thread must not inherit the suspended joker scope
assert(coroutine.resume(worker))
income = RS.income_summary()
assert(income.jokers == 13 and income.other == 4)
if not vanilla_mode then
    assert(SMODS.calculate_individual_effect({card = joker_source}, card_source, 'dollars', 6))
    assert(SMODS.calculate_individual_effect({}, card_source, 'p_dollars', 3))
    income = RS.income_summary()
    assert(income.jokers == 19 and income.cards == 12)
end
G.test_round_rows = {{name = 'joker1', dollars = 5, card = joker_source},
    {name = 'custom_card', dollars = 3, card = {ability = {set = 'Enhanced'}}}, {name = 'bottom', dollars = 8}}
G.FUNCS.evaluate_round()
local prior_jokers, prior_cards = RS.income_summary().jokers, RS.income_summary().cards
RS.with_card_income(joker_source, function() RS.prepare_cashout_income(); ease_dollars(8) end)
income = RS.income_summary()
assert(income.jokers == prior_jokers + 5 and income.cards == prior_cards + 3, 'cash-out categories override effect scope exactly once')
income_data = RS.income_chart_data()
assert(#income_data.series == 7)
local used_colours, keys, sum = {}, {}, 0
for _, series in ipairs(income_data.series) do
    local key = table.concat(series.colour, ',')
    assert(not used_colours[key], 'income categories must have distinct colours')
    used_colours[key], keys[series.key] = true, true
    sum = sum + series.values[1]
end
assert(keys.jokers and keys.cards and keys.sales and sum == select(2, RS.income_summary()))
RSChart({w = 6.4, h = 3.2, kind = 'stacked', data = RS.income_chart_data}):draw()
-- Target rolls weight duplicate base cards, exclude Stone cards, and use the
-- whole current deck (including cards outside the draw pile), not ante slices.
local saved_cards = G.playing_cards
local function target_card(suit, rank, effect)
    return {base = {suit = suit, id = rank}, ability = {effect = effect}}
end
G.playing_cards = {
    target_card('Hearts', 14), target_card('Hearts', 14), target_card('Spades', 2),
    target_card('Hearts', 3, 'Wild Card'), target_card('Clubs', 5, 'Stone Card'),
}
local targets = RS.joker_target_summary()
assert(targets.total == 5 and targets.idol_total == 4 and targets.castle_total == 4)
assert(targets.idol[1].suit == 'Hearts' and targets.idol[1].rank == 14)
assert(targets.idol[1].count == 2 and targets.idol[1].total == 4 and targets.idol[1].percentage == 50)
assert(#targets.castle == 4 and targets.castle[1].count == 3 and targets.castle[1].percentage == 75)
RS._tab = 'stats'
RS.show_menu()
local menu_text = {}
local function gather_text(node)
    if type(node) ~= 'table' then return end
    if node.config and node.config.text then menu_text[node.config.text] = true end
    for _, child in ipairs(node.nodes or node.contents or {}) do gather_text(child) end
end
gather_text(G.last_overlay)
assert(menu_text['A Hearts'] and menu_text['2 / 4  (50.0%)'] and menu_text['3 / 4  (75.0%)'])
RS._ante_sel = 99
assert(RS.joker_target_summary().idol[1].count == 2, 'target chances always use the current full deck')
RS._ante_sel = 0
if SMODS then
    local old_suit, old_rank = SMODS.has_no_suit, SMODS.has_no_rank
    SMODS.has_no_suit = function(card) return card.test_no_suit end
    SMODS.has_no_rank = function(card) return card.test_no_rank end
    G.playing_cards[1].test_no_rank = true
    G.playing_cards[3].test_no_suit = true
    targets = RS.joker_target_summary()
    assert(targets.idol_total == 2 and targets.castle_total == 3)
    SMODS.has_no_suit, SMODS.has_no_rank = old_suit, old_rank
end
G.playing_cards = {target_card('Clubs', 5, 'Stone Card')}
targets = RS.joker_target_summary()
assert(targets.idol_total == 0 and #targets.idol == 0 and targets.castle[1].percentage == 0)
G.playing_cards = nil
assert(RS.joker_target_summary().total == 0)
G.playing_cards = saved_cards
-- Trigger passes aggregate duplicates by base identity, persist and slice by ante.
s = fresh()
local triggered = {base = {suit = 'Hearts', id = 14}, test_active = true, test_repetitions = 3}
local quiet = {base = {suit = 'Clubs', id = 2}, test_active = false}
G.play, G.hand = area(), area()
G.play:emplace(triggered)
if SMODS then
    SMODS.score_card(triggered, {cardarea = G.play})
    local first, hole, last = SMODS.trigger_effects({active = true}, triggered) -- outside the scoring scope
    assert(first.calculated and hole == nil and last == 'preserved')
    SMODS.score_card(triggered, {cardarea = 'unscored'})
else
    for _ = 1, 3 do RS.record_vanilla_trigger(triggered, 'scoring', {{chips = 11}}) end
end
assert(s.per_ante[1].scoring_triggers['Hearts:14'] == 3)
triggered.debuff = true
if SMODS then SMODS.score_card(triggered, {cardarea = G.play})
else RS.record_vanilla_trigger(triggered, 'scoring', {{chips = 11}}) end
triggered.debuff = nil
assert(s.per_ante[1].scoring_triggers['Hearts:14'] == 3)
G.hand:emplace(triggered); G.hand:emplace(quiet)
triggered.test_repetitions = 1
if SMODS then
    SMODS.score_card(triggered, {cardarea = G.hand})
    SMODS.score_card(quiet, {cardarea = G.hand})
    SMODS.calculate_end_of_round_effects({cardarea = G.hand, end_of_round = true})
else
    RS.record_vanilla_trigger(triggered, 'held', {{x_mult = 1.5}, {mult = 2}})
    RS.record_vanilla_trigger(quiet, 'held', {{}})
    RS.record_vanilla_trigger(triggered, 'held', {{h_dollars = 3}})
end
assert(s.per_ante[1].held_triggers['Hearts:14'] == 2 and not s.per_ante[1].held_triggers['Clubs:2'])
G.GAME.round_resets.ante = 2
RS.record_card_trigger({base = {suit = 'Hearts', id = 14}}, 'held')
RS._card_mode, RS._card_suit, RS._card_rank, RS._ante_sel = 5, 3, 14, 0
RS._show_scoring_triggers, RS._show_held_triggers = true, true
local triggers = RS.card_chart_data()
assert(triggers.mode == 'Triggers' and triggers.values[1][1] == 6)
assert(triggers.segments[1][1][1] == 3 and triggers.segments[1][1][2] == 3)
local shade = RS.trigger_colour(triggers.cols[1], true)
assert(shade[1] > triggers.cols[1][1] and shade[2] > triggers.cols[1][2], 'held segments retain a lighter suit shade')
RSCardChart({data = RS.card_chart_data}):draw()
G.FUNCS.runstats_cards_scoring_triggers()
assert(RS.card_chart_data().values[1][1] == 3)
G.FUNCS.runstats_cards_held_triggers()
assert(RS.card_chart_data().values[1][1] == 0)
RSCardChart({data = RS.card_chart_data}):draw()
RS._show_scoring_triggers, RS._show_held_triggers = true, true
RS._ante_sel = 1
assert(RS.card_chart_data().values[1][1] == 5)
G.GAME.run_stats = copy(s)
assert(RS.card_chart_data().values[1][1] == 5, 'trigger history survives save/load')
G.GAME.run_stats.per_ante[1].held_triggers = nil
assert(RS.card_chart_data().values[1][1] == 3, 'old saves have no fabricated trigger counts')
G.FUNCS.runstats_cards_reset()
assert(RS._card_mode == 1 and RS._show_scoring_triggers and RS._show_held_triggers)
-- Shop offers are saved by stock row, not by polling the remaining cards.
s = fresh()
G.GAME.shop, G.GAME.used_vouchers = {joker_max = 2}, {}
G.GAME.selected_back_key = 'b_red'
G.shop_jokers = area()
local next_shop_id = 0
local function offer(set, key, name, rank)
    next_shop_id = next_shop_id + 1
    return {sort_id = next_shop_id, config = {center = {key = key, set = set}},
        ability = {set = set, name = name}, cost = 5,
        base = rank and {suit = 'Hearts', id = rank} or nil}
end
local function stock(cards, reroll)
    if reroll then RS.capture_shop_stock() end
    RS.begin_shop_stock(reroll)
    G.shop_jokers.cards = {}
    for _, card in ipairs(cards) do G.shop_jokers:emplace(card) end
    RS.capture_shop_stock()
end
local j1, tarot = offer('Joker', 'j_joker', 'Joker'), offer('Tarot', 'c_fool', 'The Fool')
stock({j1, tarot}, false)
assert(#s.shop_stock == 1 and #s.shop_stock[1].cards == 2 and s.shop_stock[1].reroll == 0)
G.shop_jokers:remove_card(j1) -- buying must not remove the sighting
RS.capture_shop_stock(); RS.begin_shop_stock(false)
assert(#s.shop_stock == 1 and #s.shop_stock[1].cards == 2)
local planet = offer('Planet', 'c_pluto', 'Pluto')
stock({offer('Joker', 'j_joker', 'Joker'), planet}, true)
assert(s.shop_stock[2].reroll == 1 and RS.shop_frequency('Joker')[1].count == 2)
assert(RS.shop_frequency('Tarot')[1].name == 'The Fool')
-- Overstock adds a slot without replacing bought/sold offers or the row.
G.GAME.shop.joker_max = 3
G.shop_jokers:emplace(offer('Joker', 'j_joker', 'Joker'))
assert(#s.shop_stock[2].cards == 3 and s.shop_stock[2].capacity == 3)
assert(RS.shop_frequency('Joker')[1].count == 3, 'duplicates in one row count separately')
G.GAME.shop.joker_max = 4
G.shop_jokers:emplace(offer('Spectral', 'c_hex', 'Hex'))
assert(#s.shop_stock[2].cards == 4 and s.shop_stock[2].capacity == 4)
-- A restored row uses saved sort IDs to avoid counting remaining stock twice.
G.GAME.run_stats = copy(s); s = G.GAME.run_stats
local restored_cards = {}
for _, card in ipairs(G.shop_jokers.cards) do
    restored_cards[#restored_cards + 1] = copy({sort_id = card.sort_id, config = card.config,
        ability = card.ability, cost = card.cost, base = card.base})
end
G.shop_jokers.cards = restored_cards
RS.begin_shop_stock(false); RS.capture_shop_stock()
assert(#s.shop_stock == 2 and #s.shop_stock[2].cards == 4)
G.GAME.round = 2
G.GAME.round_resets.ante = 2
stock({offer('Default', 'c_base', 'Base Card', 14), offer('Planet', 'c_pluto', 'Pluto'),
    offer('Tarot', 'c_fool', 'The Fool'), offer('Spectral', 'c_hex', 'Hex')}, false)
assert(s.shop_stock[3].reroll == 0 and s.shop_stock[3].ante == 2)
RS._ante_sel = 1
assert(RS.shop_frequency('Planet')[1].count == 1 and #RS.shop_frequency('Playing') == 0)
RS._ante_sel = 2
assert(RS.shop_frequency('Playing')[1].key == 'Hearts:14')
RS._ante_sel = 0
local pages = RS.shop_history_pages()
assert(#pages == 1 and pages[1][1].group == s.shop_stock[3], 'history starts with newest stock')
for roll = 1, 6 do stock({offer('Joker', 'j_' .. roll, 'Joker ' .. roll),
    offer('Planet', 'c_pluto', 'Pluto'), offer('Tarot', 'c_fool', 'The Fool'),
    offer('Joker', 'j_joker', 'Joker')}, true) end
pages = RS.shop_history_pages()
assert(#pages == 3)
for _, page in ipairs(pages) do
    local count = 0
    for _, pane in ipairs(page) do count = count + pane.last - pane.first + 1 end
    assert(count <= 12, 'each page holds at most 12 offers and preserves stock rows')
end
assert(#RS.shop_frequency('Joker') == 5 and RS.shop_frequency('Joker')[1].key == 'j_joker')
RS._shop_view = 'history'
G.FUNCS.runstats_tab_shop()
assert(RS._shop_page == 1 and RS._tab == 'shop')
G.FUNCS.runstats_shop_older(); assert(RS._shop_page == 2)
G.FUNCS.runstats_shop_older(); G.FUNCS.runstats_shop_older(); assert(RS._shop_page == 3)
RS._ante_sel = 1
RS.show_menu(); assert(RS._shop_page == 1, 'ante changes clamp old page selections')
G.FUNCS.runstats_shop_view()
assert(RS._shop_view == 'frequency')
G.FUNCS.runstats_shop_category(); assert(RS._shop_category == 'Planet')
-- Category availability before any conditional offers have appeared.
s = fresh()
assert(#RS.shop_categories() == 3)
G.GAME.used_vouchers = {v_magic_trick = true}
assert(RS.shop_categories()[4] == 'Playing')
G.GAME.selected_back_key = 'b_ghost'
assert(RS.shop_categories()[5] == 'Spectral')
s.shop_stock = nil -- pre-tracking saves
assert(#RS.shop_history_pages() == 0 and #RS.shop_frequency('Joker') == 0)
RS._shop_view, RS._shop_category = 'history', 'Joker'
G.FUNCS.runstats_tab_shop()
s = fresh()
G.shop_jokers, G.shop_vouchers = area(), area()
G.GAME.shop = {joker_max = 4}
local foil = offer('Joker', 'j_joker', 'Joker'); foil.edition = {foil = true}
local holo = offer('Tarot', 'c_fool', 'The Fool'); holo.edition = {type = 'holo'}
local negative = offer('Joker', 'j_abstract', 'Abstract Joker'); negative.edition = {negative = true}
stock({foil, holo, negative, offer('Planet', 'c_pluto', 'Pluto')}, false)
local offers = s.shop_stock[1].cards
assert(offers[1].edition == 'foil' and offers[2].edition == 'holo' and offers[3].edition == 'negative' and offers[4].edition == 'base')
assert(RS.shop_edition_label('holo') == 'Holographic' and RS.shop_edition_label('polychrome') == 'Polychrome')
assert(RS.shop_edition_label(nil) == 'Not recorded', 'old offers must not invent an edition')
RS._shop_view = 'history'; G.FUNCS.runstats_tab_shop()
for i = 4, #G.last_overlay.contents do assert(#G.last_overlay.contents[i].nodes == 1, 'history panes form one column') end
menu_text = {}; gather_text(G.last_overlay)
assert(menu_text['Joker  [Foil]   $5'] and menu_text['The Fool  [Holographic]   $5'])
local voucher = offer('Voucher', 'v_overstock_norm', 'Overstock')
voucher.shop_voucher = true
G.shop_vouchers:emplace(voucher)
assert(#s.shop_vouchers[1] == 1 and not s.shop_vouchers[1][1].bought)
RS.capture_shop_stock(); RS.capture_shop_vouchers()
assert(#s.shop_vouchers[1] == 1, 'revisits and rerolls do not duplicate the same ante voucher')
voucher.cost = 0
RS.record_shop_voucher(voucher, true)
RS.capture_shop_vouchers()
assert(s.shop_vouchers[1][1].bought and s.shop_vouchers[1][1].paid == 0, 'free redemption counts as bought and stays bought')
local external = offer('Voucher', 'v_external', 'External voucher')
RS.record_shop_voucher(external, true)
assert(#s.shop_vouchers[1] == 1, 'out-of-shop redemptions are not shop offers')
local voucher_area = G.shop_vouchers
G.shop_vouchers = nil
RS.record_shop_voucher(external, true)
assert(#s.shop_vouchers[1] == 1, 'redemptions with no shop area must not count as shop offers')
G.shop_vouchers = voucher_area
-- Voucher refresh belongs to the new ante, even when cash/stock is attributed
-- to the Boss blind that led into the shop.
s.blinds = {{ante = 1, label = '1BOSS', completed = true}}
s.current_blind = 1
G.GAME.round_resets.ante = 2
G.shop_vouchers.cards = {}
G.shop_vouchers:emplace(offer('Voucher', 'v_overstock_norm', 'Overstock'))
assert(#s.shop_vouchers[2] == 1 and not s.shop_vouchers[2][1].bought and s.shop_vouchers[1][1].bought)
G.GAME.run_stats = copy(s); s = G.GAME.run_stats
assert(s.shop_vouchers[1][1].bought and s.shop_vouchers[1][1].paid == 0)
RS._ante_sel = 1
local voucher_pages = RS.voucher_history_pages()
assert(#voucher_pages[1] == 1 and voucher_pages[1][1].voucher.bought)
RS._ante_sel = 0
G.FUNCS.runstats_shop_view(); G.FUNCS.runstats_shop_view()
assert(RS._shop_view == 'vouchers')
menu_text = {}; gather_text(G.last_overlay)
assert(menu_text['Overstock   $0   |   Bought'] and menu_text['Overstock   $5   |   Not bought'])
for ante = 3, 10 do
    G.GAME.round_resets.ante = ante
    RS.record_shop_voucher(offer('Voucher', 'v_' .. ante, 'Voucher ' .. ante), false)
end
voucher_pages = RS.voucher_history_pages()
assert(#voucher_pages == 2 and #voucher_pages[1] == 8 and voucher_pages[1][1].ante == 10)
G.FUNCS.runstats_shop_older(); assert(RS._voucher_page == 2)
G.FUNCS.runstats_shop_newer(); assert(RS._voucher_page == 1)
G.FUNCS.runstats_shop_view(); assert(RS._shop_view == 'history')
-- Fine income uses the applied effect and observed money, never another roll.
s = fresh()
local ticket = {ability = {set = 'Joker', name = 'Golden Ticket'}, config = {center_key = 'j_ticket'}}
local mail = {ability = {set = 'Joker', name = 'Mail-In Rebate'}, config = {center_key = 'j_mail'}}
local lucky = {test_income = true, seal = 'Gold', ability = {set = 'Enhanced', name = 'Lucky Card', effect = 'Lucky Card', p_dollars = 20},
    config = {center_key = 'm_lucky'}}
local function pay_effect(effect, card, key, amount)
    if SMODS then SMODS.calculate_individual_effect(effect, card, key, amount)
    else RS.with_payment_income(effect, card, key, function() ease_dollars(amount) end) end
end
local function own_effect(card)
    local result = eval_card(card, {cardarea = G.play, main_scoring = true})
    return result.playing_card or result
end
local old_random = random_value
random_value = 0.01
local before_rolls = random_calls
local lucky_effect = own_effect(lucky)
random_value = 0.9
local seal_effect = own_effect(lucky)
assert(random_calls == before_rolls + 2, 'one existing Lucky roll per evaluation')
assert(lucky_effect.p_dollars == 23 and seal_effect.p_dollars == 3)
pay_effect(lucky_effect, lucky, 'p_dollars', 23)
pay_effect(seal_effect, lucky, 'p_dollars', 3)
assert(random_calls == before_rolls + 2, 'attributing income must not re-roll probabilities')
random_value = old_random
pay_effect({card = ticket}, lucky, 'dollars', 4)
RS.with_card_income(mail, function() ease_dollars(5) end)
local gold = {ability = {set = 'Enhanced', name = 'Gold Card'}, config = {center_key = 'm_gold'}}
pay_effect({card = gold}, gold, 'h_dollars', 3)
local hermit = {ability = {set = 'Tarot', name = 'The Hermit'}, config = {center_key = 'c_hermit'}}
RS.with_card_income(hermit, function() ease_dollars(12) end)
RS.with_card_income(ticket, function() RS.prepare_income('sales', ticket); ease_dollars(2) end)
ease_dollars(7)
local function detail_totals()
    local names, total = {}, 0
    for _, row in ipairs(RS.detailed_income_rows()) do names[row.name] = (names[row.name] or 0) + row.amount; total = total + row.amount end
    return names, total
end
local exact, exact_total = detail_totals()
assert(exact['Gold Seals'] == 6 and exact['Lucky Cards'] == 20 and exact['Golden Ticket'] == 4 and exact['Mail-In Rebate'] == 5)
assert(exact['Gold Cards'] == 3 and exact['The Hermit'] == 12 and exact['Sale: Golden Ticket'] == 2)
assert(exact['Other / unclassified'] == 7 and exact_total == select(2, RS.income_summary()))
-- Adjusted/mixed payouts are not assigned a fabricated seal/enhancement split.
pay_effect(lucky_effect, lucky, 'p_dollars', 5)
assert(select(1, detail_totals())['Card effects (mixed)'] == 5)
-- Cash-out source detail is credited once, to the blind that earned it.
G.test_round_rows = {{name = 'blind1', dollars = 5}, {name = 'hands', dollars = 2}, {name = 'interest', dollars = 1},
    {name = 'joker1', dollars = 8, card = {ability = {set = 'Joker', name = 'Cloud 9'}, config = {center_key = 'j_cloud_9'}}},
    {name = 'bottom', dollars = 16}}
G.FUNCS.evaluate_round()
G.GAME.round_resets.ante = 2
RS.prepare_cashout_income(); ease_dollars(16)
RS._ante_sel = 1
exact, exact_total = detail_totals()
assert(exact['Cloud 9'] == 8 and exact['Blind rewards'] == 5 and exact['Unused hands'] == 2 and exact.Interest == 1)
assert(exact_total == select(2, RS.income_summary()))
G.GAME.run_stats = copy(s); s = G.GAME.run_stats
assert(select(1, detail_totals())['Gold Seals'] == 6, 'source amounts survive save/load')
-- Old category data is retained as a residual; no invented historical sources.
RS.pa().earned, RS.pa().income = 9, {jokers = 6, cards = 3}
RS.pa().income_details = nil
RS._ante_sel = 2
exact, exact_total = detail_totals()
assert(exact['Jokers (earlier/unclassified)'] == 6 and exact['Cards (earlier/unclassified)'] == 3 and exact_total == 9)
RS._ante_sel = 0
RS._tab, RS._trend_view, RS._income_detail = 'dashboard', 'economy', false
G.FUNCS.runstats_income_detail()
assert(RS._income_detail and RS.income_detail_chart_data().pages >= 2)
charts = {}; walk(G.last_overlay)
assert(charts[1].config.kind == 'horizontal' and charts[1].config.data == RS.income_detail_chart_data)
RSChart({w = 6.4, h = 3.2, kind = 'horizontal', data = RS.income_detail_chart_data}):draw()
G.FUNCS.runstats_income_next(); assert(RS._income_detail_page == 2)
RS._ante_sel = 2
RS.income_detail_chart_data(); assert(RS._income_detail_page == 1, 'a narrower ante filter clamps pages')
G.FUNCS.runstats_income_detail(); assert(not RS._income_detail)
-- Consumable card counts are per ante, while older run-wide history remains
-- usable on All. The four charts show every used card through independent pages.
s = fresh()
RS._ante_sel = 0
local saved_centers = G.P_CENTERS
G.P_CENTERS = {
    c_sun = {key = 'c_sun', set = 'Tarot', name = 'The Sun'},
    c_cryptid = {key = 'c_cryptid', set = 'Spectral', name = 'Cryptid'},
    c_uranus = {key = 'c_uranus', set = 'Planet', name = 'Uranus'},
}
local sun = {config = {center_key = 'c_sun'}, ability = {set = 'Tarot', name = 'The Sun'}}
local cryptid = {config = {center = G.P_CENTERS.c_cryptid}, ability = {set = 'Spectral', name = 'Cryptid'}}
local uranus = {config = {center_key = 'c_uranus'}, ability = {set = 'Planet', name = 'Uranus'}}
assert(RS.all_consumables_chart_data().total == 0 and #RS.all_consumables_chart_data().antes == 0)
local used, missing, copier = Card.use_consumeable(sun, nil, 'kept')
assert(used == 'used' and missing == nil and copier == 'kept')
Card.use_consumeable(sun); Card.use_consumeable(cryptid); Card.use_consumeable(uranus)
G.GAME.round_resets.ante = 2
Card.use_consumeable(sun); Card.use_consumeable(cryptid); Card.use_consumeable(uranus); Card.use_consumeable(uranus)
local usage = RS.consumable_usage()
assert(usage.total == 8 and usage.totals.Tarot == 3 and usage.totals.Spectral == 2 and usage.totals.Planet == 3)
assert(RS.consumable_card_chart_data('Tarot').antes[1] == 'The Sun' and RS.consumable_card_chart_data('Tarot').series[1].values[1] == 3)
assert(RS.consumable_card_chart_data('Spectral').antes[1] == 'Cryptid' and RS.consumable_card_chart_data('Spectral').series[1].values[1] == 2)
assert(RS.consumable_card_chart_data('Planet').antes[1] == 'Uranus' and RS.consumable_card_chart_data('Planet').series[1].values[1] == 3)
local combined, combined_total, used_colours = RS.all_consumables_chart_data(), 0, {}
for i, count in ipairs(combined.series[1].values) do combined_total = combined_total + count; used_colours[table.concat(combined.colours[i], ',')] = true end
local colour_count = 0; for _ in pairs(used_colours) do colour_count = colour_count + 1 end
assert(combined_total == 8 and colour_count == 3)
Card.use_consumeable({ability = {set = 'Joker', name = 'Joker'}})
G.STAGE = G.STAGES.MAIN_MENU
Card.use_consumeable(sun)
G.STAGE = G.STAGES.RUN
assert(s.consumables_used.total == 8, 'only run-scoped Tarot/Planet/Spectral uses are recorded')
RS._ante_sel = 1
usage = RS.consumable_usage()
assert(usage.total == 4 and usage.totals.Tarot == 2 and usage.rows.Tarot[1].count == 2)
RS._ante_sel = 2
assert(RS.consumable_usage().totals.Planet == 2)
RS._ante_sel = 0
G.FUNCS.runstats_tab_consumables()
assert(RS._tab == 'consumables')
local nav_labels, nav_width = {}, 0
for _, button in ipairs(G.last_overlay.contents[1].nodes) do
    nav_labels[button.config.label[1]] = true
    nav_width = nav_width + button.config.minw
end
assert(nav_labels.Probabilities and nav_labels.Deck and nav_labels.Consumables and not nav_labels.Prob and not nav_labels.Cards)
assert(nav_width < 13.4, 'the longer tab names fit the menu width')
charts = {}; walk(G.last_overlay)
assert(#charts == 4)
for _, chart in ipairs(charts) do assert(chart.config.kind == 'horizontal'); chart:draw() end
for i = 1, 8 do Card.use_consumeable({config = {center_key = 'c_extra_' .. i}, ability = {set = 'Tarot', name = 'Extra Tarot ' .. i}}) end
assert(RS.consumable_card_chart_data('Tarot').pages == 2 and RS.all_consumables_chart_data().pages == 2)
G.FUNCS.runstats_consumables_tarot_next()
assert(RS._consumable_pages.Tarot == 2 and RS._consumable_pages.All == 1)
G.FUNCS.runstats_consumables_all_next(); assert(RS._consumable_pages.All == 2)
G.FUNCS.runstats_consumables_all_previous(); assert(RS._consumable_pages.All == 1)
RS._ante_sel = 1
RS.consumable_card_chart_data('Tarot'); assert(RS._consumable_pages.Tarot == 1)
G.GAME.run_stats = copy(s); s = G.GAME.run_stats
assert(RS.consumable_usage().rows.Tarot[1].count == 2, 'card use history survives save/load')
s.per_ante[1].consumables_by_key = nil
usage = RS.consumable_usage()
assert(usage.rows.Tarot[1].name == 'Earlier / unclassified' and usage.rows.Tarot[1].count == 2)
RS._ante_sel = 0
assert(RS.consumable_usage().rows.Tarot[1].name == 'The Sun' and RS.consumable_usage().rows.Tarot[1].count == 3,
    'All retains existing run-wide card counts even when older ante detail is missing')
local saved_info = s.consumable_info
s.consumable_info = nil
assert(RS.consumable_usage().rows.Spectral[1].name == 'Cryptid', 'older card keys resolve through the game catalog')
s.consumable_info = saved_info
G.P_CENTERS = saved_centers
s = fresh()
G.shop_jokers, G.shop_vouchers, G.GAME.used_vouchers = nil, nil, {}
RS._ante_sel = 0
assert(RS.shop_edition_rates('Joker').rate == nil and RS.shop_edition_rates('Joker').total == 0)
local function edition_offer(category, edition, name)
    return {key = name, name = name, category = category, edition = edition, cost = 5}
end
s.shop_stock = {
    {ante = 1, label = '1S', visit = '1:1', reroll = 0, capacity = 4, cards = {
        edition_offer('Joker', 'base', 'Base Joker'), edition_offer('Joker', 'foil', 'Foil Joker'),
        edition_offer('Joker', 'holo', 'Holo Joker'), edition_offer('Playing', 'base', 'Base Ace'),
        edition_offer('Playing', 'polychrome', 'Polychrome Ace'), edition_offer('Tarot', 'foil', 'Foil Tarot')}},
    {ante = 1, label = '1S', visit = '1:1', reroll = 1, capacity = 2, cards = {
        edition_offer('Joker', 'negative', 'Negative Joker'), edition_offer('Playing', 'foil', 'Foil King'),
        edition_offer('Planet', 'negative', 'Negative Planet')}},
    {ante = 2, label = '2B', visit = '2:2', reroll = 0, capacity = 4, cards = {
        edition_offer('Joker', 'base', 'Second Base Joker'), edition_offer('Joker', 'polychrome', 'Polychrome Joker'),
        edition_offer('Joker', nil, 'Older Joker'), edition_offer('Playing', 'base', 'Base Queen')}},
}
local joker_rates, playing_rates = RS.shop_edition_rates('Joker'), RS.shop_edition_rates('Playing')
assert(joker_rates.total == 7 and joker_rates.known == 6 and joker_rates.unknown == 1 and joker_rates.editions == 4)
assert(math.abs(joker_rates.rate - 100 * 4 / 6) < 0.00001)
assert(joker_rates.counts.foil == 1 and joker_rates.counts.holo == 1 and joker_rates.counts.polychrome == 1 and joker_rates.counts.negative == 1)
assert(playing_rates.known == 4 and playing_rates.editions == 2 and playing_rates.rate == 50)
assert(not RS.show_playing_edition_rates(), 'modded playing-card offers do not bypass the Magic Trick condition')
RS._shop_view = 'history'; G.FUNCS.runstats_tab_shop()
menu_text = {}; gather_text(G.last_overlay)
assert(menu_text['Observed Joker edition rate'] and menu_text['4 / 6 offers (66.7%)'])
assert(not menu_text['Observed playing-card edition rate'])
G.GAME.used_vouchers.v_magic_trick = true
RS.show_menu(); menu_text = {}; gather_text(G.last_overlay)
assert(menu_text['Observed playing-card edition rate'] and menu_text['2 / 4 offers (50.0%)'])
assert(menu_text['1 older offer excluded (edition not recorded)'])
RS._shop_page = 99
assert(RS.shop_edition_rates('Joker').known == 6, 'rates cover the whole history rather than just the current page')
RS._ante_sel = 1
assert(RS.shop_edition_rates('Joker').rate == 75 and RS.shop_edition_rates('Joker').unknown == 0)
assert(RS.shop_edition_rates('Playing').known == 3)
RS._ante_sel = 0
G.GAME.used_vouchers = {v_illusion = true}
assert(RS.show_playing_edition_rates(), 'Illusion retains the playing-card edition field')
table.insert(s.shop_stock[3].cards, edition_offer('Joker', 'custom_edition', 'Custom Edition Joker'))
joker_rates = RS.shop_edition_rates('Joker')
assert(joker_rates.known == 7 and joker_rates.editions == 5 and joker_rates.counts.other == 1)
G.GAME.run_stats = copy(s)
assert(RS.shop_edition_rates('Joker').counts.other == 1, 'edition rates survive save/load')
G.GAME.run_stats.shop_stock = {{ante = 1, label = '1S', visit = '1:1', reroll = 0, capacity = 2,
    cards = {edition_offer('Joker', nil, 'Unknown Joker')}}}
assert(RS.shop_edition_rates('Joker').rate == nil, 'unknown editions cannot masquerade as Base or zero probability')
RS.show_menu()
print('Shop edition rates passed: separate Joker/playing samples, edition breakdowns, voucher gating, ante filters, full history, unknown data, modded editions and saves')
print('Consumables checks passed: four charts, renamed tabs, individual/type totals, hook returns, ante filters, colors, independent paging, saves and older history')
print('Detailed income checks passed: exact Joker/card sources, Lucky + Gold Seal splits, unchanged RNG, sales, cash-out attribution, old saves, total reconciliation, paging and rendering')
print('Shop checks passed: visits, rerolls, purchases, duplicate offers, Overstock sizes, restored stock, pagination, top five, categories, editions, voucher offers/redemptions and ante filters')
print('Trigger checks passed: scoring, repetitions, held effects, end-of-round effects, filters, suit shades, saves and rendering')
print('Joker target checks passed: duplicates, full deck, Wild/Stone cards, empty pools and optional enhancement exclusions')
print('Dashboard checks passed: hooks, saves, filtering, menus, six charts and draw paths')
print('Pack and result-screen checks passed: all five families/sizes, free packs, old saves, win/loss navigation')
print('Drawn-card checks passed: completed transfers, repeated draws, exclusions, filters, mode cycle and old saves')
print('Analysis checks passed: score samples/median, spending totals/categories, Trends views, matched use rates and save/load')
if not vanilla_mode then print('Probability checks passed: real tooltip helper, zero/multiple/debuffed Oops, selling, history, raw ratios and no_mod rolls') end
print('Ante selector checks passed: empty runs, played limit, future shop exclusion, endless antes, gaps and stale selections')

print('Economy/deck checks passed: claimed income, ante attribution, snapshots, levels, all deck groupings, save/load, filters and rendering')

print('Overlap/income checks passed: all hands, merges/splits/rejoins/gaps, distinct colours, source scopes, sales and joker/card bonuses')
