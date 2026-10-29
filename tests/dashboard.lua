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
G.GAME.blind:set_blind({name = 'Small'}, true)
assert(#s.blinds == 1, 'reset must not create history')
set_hand_usage('Pair'); set_hand_usage('Pair'); set_hand_usage('Flush')
assert(RS.poker_chart_data().series[1].values[1] == 2)
win(2, 2)
assert(s.blinds[1].won and s.blinds[1].completed)
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
RS._ante_sel = 1
assert(#RS.score_chart_data().antes == 2 and #RS.cash_chart_data().antes == 2)
assert(#RS.poker_chart_data().antes == 2)
RS._ante_sel = 2
assert(#RS.hands_chart_data().antes == 0)
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
assert(RS._card_mode == 1, 'mode cycles Use rate back to Played')
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
print('Dashboard checks passed: hooks, saves, filtering, menus, six charts and draw paths')
print('Pack and result-screen checks passed: all five families/sizes, free packs, old saves, win/loss navigation')
print('Drawn-card checks passed: completed transfers, repeated draws, exclusions, filters, mode cycle and old saves')
print('Analysis checks passed: score samples/median, spending totals/categories, Trends views, matched use rates and save/load')
if not vanilla_mode then print('Probability checks passed: real tooltip helper, zero/multiple/debuffed Oops, selling, history, raw ratios and no_mod rolls') end
print('Ante selector checks passed: empty runs, played limit, future shop exclusion, endless antes, gaps and stale selections')

print('Economy/deck checks passed: claimed income, ante attribution, snapshots, levels, all deck groupings, save/load, filters and rendering')

print('Overlap/income checks passed: all hands, merges/splits/rejoins/gaps, distinct colours, source scopes, sales and joker/card bonuses')
