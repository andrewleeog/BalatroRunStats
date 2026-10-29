-- =============================================================
-- Run Stats — native-style stats menu + per-ante dashboard
-- Lovely mod with optional Steamodded integration. Stats persist with the run.
--
-- Tabs:
--   Summary   — emulates the vanilla high-scores/stats menu, but every
--               counter is scoped to the CURRENT RUN only.
--   Trends    — scoring, economy and hand usage: KPI cards + six charts.
-- =============================================================

RunStats = RunStats or {}

local RS = RunStats
if RS._loaded then return RS end
RS._loaded = true

-- ------------------------------------------------------------
-- Stats storage
-- ------------------------------------------------------------

local PA_DEFAULTS = {
    career = {},
    best_score = 0,
    drawn = 0,
    consumables = 0,
    cset = {},
    earned = 0,
    spent = 0,
    jokers_bought = 0,
    skips = 0,
    packs = 0,
    pack_types = {},
    vouchers = 0,
    most_money = 0,
    probs = {},
    cards_played = {},     -- ['Hearts:14'] = count (per-ante, per base card)
    cards_discarded = {},  -- same key space; deck additions merge into the base entry
    cards_drawn = {},      -- completed draws from the deck into the hand
    scoring_triggers = {},
    held_triggers = {},
    hand_types = {},
    hand_scores = {},
    spending = {},
    usage_drawn = {},
    usage_played = {},
    income = {},
}

local function new_pa()
    local pa = {}
    for k, v in pairs(PA_DEFAULTS) do
        pa[k] = (type(v) == 'table') and {} or v
    end
    return pa
end

function RS.fresh_stats()
    return {
        career = {},       -- mirror of every vanilla inc_career_stat key
        per_ante = {},     -- [ante] = per-ante bucket
        blinds = {},      -- chronological blind history, saved with the run
        shops = {},       -- cash on first entry to each shop
        shop_stock = {},  -- offers grouped by visit and reroll; plain save data
        shop_vouchers = {}, -- voucher offers by the ante in which they appeared
        draw_tokens = {}, -- latest draw per playing-card ID; survives save/load
        probs = {},        -- [seed] = {rolls, hits, num, den} — every chance roll
        skips = 0,
        best_hand_score = 0,
        most_money = 0,
        cards_drawn = 0,
        packs_opened = 0,
        jokers_bought = 0,
        money_earned = 0,
        money_spent = 0,
        consumables_used = { total = 0, Tarot = 0, Planet = 0, Spectral = 0 },
        consumables_by_key = {},
        glass = { destroyed = 0 },
    }
end

-- Returns the current run's stats table, or nil outside a run.
function RS.stats()
    if G and G.GAME and G.STAGE == G.STAGES.RUN then
        if not G.GAME.run_stats then G.GAME.run_stats = RS.fresh_stats() end
        return G.GAME.run_stats
    end
    return nil
end

-- Per-ante bucket for the current ante.
function RS.pa()
    local s = RS.stats()
    if not s then return nil end
    local ante = (G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante) or 1
    local pa = s.per_ante[ante]
    if not pa then
        pa = new_pa()
        s.per_ante[ante] = pa
    end
    return pa
end

local function bump(t, key, n)
    t[key] = (t[key] or 0) + (n or 0)
end

-- Lovely-patch callbacks (kept for API compatibility; glass roll tracking
-- now lives in the universal SMODS.pseudorandom_probability wrapper).
function RS.glass_scored(card)
    local s = RS.stats()
    if s and card and not card.debuff then
        s.probs['glass'] = s.probs['glass'] or { rolls = 0, hits = 0, num = 1, den = 4 }
        s.probs['glass'].rolls = s.probs['glass'].rolls + 1
    end
end

function RS.glass_shattered()
    local s = RS.stats()
    if s then
        s.probs['glass'] = s.probs['glass'] or { rolls = 0, hits = 0, num = 1, den = 4 }
        s.probs['glass'].hits = s.probs['glass'].hits + 1
    end
end

-- ------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------

local function fmt_pct(hits, rolls)
    if not rolls or rolls == 0 then return '--' end
    return string.format('%.1f%%', 100 * hits / rolls)
end

local function most_used_consumable(by_key)
    if not by_key then return '--' end
    local best_key, best_n
    for k, v in pairs(by_key) do
        if not best_n or v > best_n then best_key, best_n = k, v end
    end
    if not best_key then return '--' end
    return (best_key:gsub('^j_', ''):gsub('c_', '')) .. ' x' .. tostring(best_n)
end

local function most_played_hand()
    if not (G.GAME and G.GAME.hands) then return '--', 0 end
    local best_key, best_n
    for k, v in pairs(G.GAME.hands) do
        local played = v.played or 0
        if not best_n or played > best_n then best_key, best_n = k, played end
    end
    if not best_key or (best_n or 0) < 1 then return 'None yet', 0 end
    local ok, loc = pcall(localize, best_key, 'poker_hands')
    return (ok and type(loc) == 'string' and loc) or best_key, best_n
end

local function career(stat)
    local s = RS.stats()
    return (s and s.career and s.career[stat]) or 0
end

-- ------------------------------------------------------------
-- Ante filter (dashboard + stats follow it): 'All' or a single ante.
-- ------------------------------------------------------------

RS._ante_sel = 0 -- 0 = All antes, 1..N = only that ante

-- Offer only recorded antes, including endless runs and gaps from ante changes.
function RS.played_antes()
    local seen, antes = {}, {}
    local furthest = (G.GAME and G.GAME.round_scores and G.GAME.round_scores.furthest_ante
        and G.GAME.round_scores.furthest_ante.amt) or 0
    local function add(ante)
        if type(ante) == 'number' and ante >= 1 and ante == math.floor(ante) and not seen[ante] then
            seen[ante] = true
            antes[#antes + 1] = ante
        end
    end
    local s = RS.stats()
    for ante in pairs((s or {}).per_ante or {}) do
        -- Cash-out/shop activity can be recorded under the next ante before
        -- its first blind starts. The native record excludes that future ante.
        if furthest <= 0 or ante <= furthest then add(ante) end
    end
    for _, blind in ipairs((s or {}).blinds or {}) do add(blind.ante) end
    for _, group in ipairs((s or {}).shop_stock or {}) do
        if furthest <= 0 or group.ante <= furthest then add(group.ante) end
    end
    add(furthest)
    table.sort(antes)
    return antes
end

function RS.max_ante()
    local antes = RS.played_antes()
    return antes[#antes] or 0
end

function RS.normalize_ante_selection()
    if (RS._ante_sel or 0) <= 0 then RS._ante_sel = 0; return end
    for _, ante in ipairs(RS.played_antes()) do
        if ante == RS._ante_sel then return end
    end
    RS._ante_sel = 0
end

-- Compatibility range: a single selected ante collapses to [N, N];
-- 'All' spans the whole run.
function RS.slice_range()
    local maxa = RS.max_ante()
    local sel = math.max(0, math.min(math.floor((RS._ante_sel or 0) + 0.5), maxa))
    if sel <= 0 then return 1, maxa, maxa end
    return sel, sel, maxa
end

function RS.in_slice(a)
    local sel = math.max(0, math.floor((RS._ante_sel or 0) + 0.5))
    return sel <= 0 or a == sel
end

function RS.slice_is_full()
    return (RS._ante_sel or 0) <= 0
end

function RS.ante_sel_label()
    local sel = math.max(0, math.floor((RS._ante_sel or 0) + 0.5))
    return (sel <= 0) and 'All' or tostring(sel)
end

-- Sum of a per-ante bucket field over the selected range.
function RS.pa_sum(field)
    local s = RS.stats()
    local sum = 0
    if s and s.per_ante then
        for a, bucket in pairs(s.per_ante) do
            if RS.in_slice(a) then sum = sum + (bucket[field] or 0) end
        end
    end
    return sum
end

-- Max of a per-ante bucket field over the selected range.
function RS.pa_max(field)
    local s = RS.stats()
    local m = 0
    if s and s.per_ante then
        for a, bucket in pairs(s.per_ante) do
            if RS.in_slice(a) then m = math.max(m, bucket[field] or 0) end
        end
    end
    return m
end

-- Sum of a mirrored career stat over the selected range (falls back to the
-- run total when the whole run is selected).
function RS.career_sliced(stat)
    local s = RS.stats()
    if not s then return 0 end
    if RS.slice_is_full() then return s.career and s.career[stat] or 0 end
    local sum = 0
    for a, bucket in pairs(s.per_ante or {}) do
        if RS.in_slice(a) then sum = sum + ((bucket.career or {})[stat] or 0) end
    end
    return sum
end

-- Live KPI values (text nodes reference this table; the slider callbacks
-- and menu-open refresh it).
RS._kpi = { range = '-', money = '-', hands = '-', best = '-', earned = '-' }

function RS.rebuild_kpis()
    local s = RS.stats()
    RS._kpi.range = RS.slice_is_full() and 'All antes' or ('Ante ' .. RS.ante_sel_label())
    RS._kpi.money = localize('$') .. number_format((s and s.most_money and RS.pa_max('most_money')) or 0)
    RS._kpi.hands = number_format(RS.career_sliced('c_hands_played'))
    RS._kpi.best = number_format(RS.pa_max('best_score'))
    RS._kpi.earned = localize('$') .. number_format(RS.pa_sum('earned'))
end

local function safe_wrap(obj, key, make_new)
    if not obj then return end
    local ref = obj[key]
    if ref == nil then return end
    obj[key] = make_new(ref)
    return ref
end

-- Effect calculations may run in a scoring coroutine. Keep their income source
-- local to that coroutine so a yield cannot misattribute unrelated payments.
local income_main_thread = {}
local income_scopes = setmetatable({}, {__mode = 'k'})
local function income_thread() return coroutine.running() or income_main_thread end
local function pack_results(...) return {n = select('#', ...), ...} end

function RS.card_income_category(card)
    return card and (card.ability or {}).set == 'Joker' and 'jokers' or 'cards'
end

function RS.with_card_income(card, fn, ...)
    local thread = income_thread()
    local previous = income_scopes[thread]
    income_scopes[thread] = {stats = RS.stats(), category = RS.card_income_category(card)}
    local result = pack_results(fn(...))
    income_scopes[thread] = previous
    return unpack(result, 1, result.n)
end

function RS.with_effect_income(effect, fn, ...)
    effect = effect or {}
    return RS.with_card_income(effect.card or effect.juice_card or effect.focus, fn, ...)
end

safe_wrap(SMODS, 'calculate_individual_effect', function(ref)
    return function(effect, scored_card, key, amount, ...)
        if key == 'dollars' or key == 'p_dollars' or key == 'h_dollars' then
            local source = effect and (effect.card or effect.juice_card or effect.focus) or nil
            return RS.with_card_income(source or scored_card, ref, effect, scored_card, key, amount, ...)
        end
        return ref(effect, scored_card, key, amount, ...)
    end
end)

local function score_summary(scores)
    local sorted, total = {}, 0
    for _, score in ipairs(scores or {}) do sorted[#sorted + 1], total = score, total + score end
    table.sort(sorted)
    local n = #sorted
    if n == 0 then return { count = 0 } end
    local middle = math.floor((n + 1) / 2)
    return { count = n, average = total / n, best = sorted[n],
        median = n % 2 == 1 and sorted[middle] or (sorted[middle] / 2 + sorted[middle + 1] / 2) }
end

function RS.score_summary()
    local scores = {}
    for ante, bucket in pairs((RS.stats() or {}).per_ante or {}) do
        if RS.in_slice(ante) then
            for _, score in ipairs(bucket.hand_scores or {}) do scores[#scores + 1] = score end
        end
    end
    return score_summary(scores)
end

local SPEND_CATEGORIES = {
    {key = 'rerolls', label = 'Rerolls'}, {key = 'jokers', label = 'Jokers'},
    {key = 'packs', label = 'Packs'}, {key = 'vouchers', label = 'Vouchers'},
    {key = 'cards', label = 'Playing cards'}, {key = 'consumables', label = 'Consumables'},
}

function RS.purchase_category(card)
    local set = card and card.ability and card.ability.set
    if set == 'Booster' then return 'packs' end
    if set == 'Voucher' then return 'vouchers' end
    if set == 'Joker' then return 'jokers' end
    if set == 'Default' or set == 'Enhanced' or (card and card.playing_card) then return 'cards' end
    return 'consumables'
end

-- Called at the actual charge sites, after validation and inside purchase events.
function RS.record_spend(category, amount)
    if type(amount) ~= 'number' or amount <= 0 then return end
    local bucket = RS.pa()
    if not bucket then return end
    bucket.spending = bucket.spending or {}
    bump(bucket.spending, category, amount)
end

function RS.spending_summary()
    local values, total = {}, 0
    for ante, bucket in pairs((RS.stats() or {}).per_ante or {}) do
        if RS.in_slice(ante) then
            total = total + (bucket.spent or 0)
            for key, amount in pairs(bucket.spending or {}) do bump(values, key, amount) end
        end
    end
    local classified = 0
    for _, category in ipairs(SPEND_CATEGORIES) do classified = classified + (values[category.key] or 0) end
    values.other = math.max(0, total - classified)
    return values, total
end

local function current_ante()
    return (G.GAME.round_resets and G.GAME.round_resets.ante) or 1
end

local function snapshot_ante()
    local stats = RS.stats()
    if not stats then return nil end
    local blind = (stats.blinds or {})[stats.current_blind or 0]
    if blind then return blind.ante end
    local furthest = (((G.GAME or {}).round_scores or {}).furthest_ante or {}).amt or 0
    return furthest > 0 and math.min(current_ante(), furthest) or nil
end

function RS.capture_snapshot()
    local stats, ante = RS.stats(), snapshot_ante()
    if not stats or not ante or (not G.playing_cards and not G.GAME.hands) then return end
    local bucket = stats.per_ante[ante]
    if not bucket then bucket = new_pa(); stats.per_ante[ante] = bucket end
    if G.GAME.hands then
        local levels = {}
        for key, hand in pairs(G.GAME.hands) do
            if type(hand.level) == 'number' then levels[key] = hand.level end
        end
        bucket.hand_levels = levels
    end
    if G.playing_cards then
        local deck = { total = 0, suits = {}, ranks = {}, enhancements = {}, seals = {}, editions = {} }
        for _, card in ipairs(G.playing_cards) do
            local base, config = card.base or {}, card.config or {}
            local center = config.center or {}
            deck.total = deck.total + 1
            bump(deck.suits, base.suit or 'Other', 1)
            bump(deck.ranks, base.id and tostring(base.id) or 'Other', 1)
            local enhanced = center.set == 'Enhanced' or (card.ability or {}).set == 'Enhanced'
            bump(deck.enhancements, enhanced and (config.center_key or center.key or 'Enhanced') or 'Base', 1)
            bump(deck.seals, card.seal or 'None', 1)
            local edition = 'None'
            if card.edition then
                if type(card.edition.type) == 'string' then edition = card.edition.type
                else
                    local keys = {}
                    for key, value in pairs(card.edition) do if value == true then keys[#keys + 1] = key end end
                    table.sort(keys)
                    edition = keys[1] or 'None'
                end
            end
            bump(deck.editions, edition, 1)
        end
        bucket.deck_snapshot = deck
    end
end

safe_wrap(_G, 'level_up_hand', function(ref)
    return function(...)
        local result = ref(...)
        RS.capture_snapshot()
        return result
    end
end)

-- Collect the displayed payout components, then credit them only at cash-out.
safe_wrap(G.FUNCS, 'evaluate_round', function(ref)
    return function(...)
        local stats = RS.stats()
        if stats then stats.round_income = { ante = snapshot_ante() or current_ante(), categories = {} } end
        local result = ref(...)
        return result
    end
end)

safe_wrap(_G, 'add_round_eval_row', function(ref)
    return function(config, ...)
        local stats = RS.stats()
        local payout = stats and stats.round_income
        if payout and config and type(config.dollars) == 'number' and config.dollars > 0 then
            local category = ({blind1 = 'blinds', hands = 'hands', interest = 'interest'})[config.name]
            if not category and config.card then category = RS.card_income_category(config.card) end
            if not category and type(config.name) == 'string' and config.name:match('^joker%d+$') then category = 'jokers' end
            if category then bump(payout.categories, category, config.dollars) end
        end
        return ref(config, ...)
    end
end)

function RS.prepare_cashout_income()
    local stats = RS.stats()
    if stats then
        RS._next_income = { stats = stats, payout = stats.round_income
            or { ante = snapshot_ante() or current_ante(), categories = {} } }
        stats.round_income = nil
    end
end

function RS.prepare_income(category)
    local stats = RS.stats()
    if stats then RS._next_income = {stats = stats, category = category} end
end

function RS.record_income(category, amount)
    if type(amount) ~= 'number' or amount <= 0 then return end
    local bucket = RS.pa()
    if bucket then bucket.income = bucket.income or {}; bump(bucket.income, category, amount) end
end

function RS.income_summary()
    local totals, earned = {}, 0
    for ante, bucket in pairs((RS.stats() or {}).per_ante or {}) do
        if RS.in_slice(ante) then
            earned = earned + (bucket.earned or 0)
            for key, value in pairs(bucket.income or {}) do bump(totals, key, value) end
        end
    end
    local known = (totals.blinds or 0) + (totals.hands or 0) + (totals.interest or 0)
        + (totals.sales or 0) + (totals.jokers or 0) + (totals.cards or 0)
    totals.other = math.max(0, earned - known)
    return totals, earned
end

function RS.ante_in_progress(ante)
    local resets = G.GAME.round_resets or {}
    return ante == current_ante() and G.STATE ~= G.STATES.GAME_OVER
        and (resets.blind_states or {}).Boss ~= 'Defeated'
end

-- Keep stable records rather than reconstructing past rounds from current totals.
function RS.blind_record(create)
    local s = RS.stats()
    if not s then return nil end
    s.blinds = s.blinds or {}
    local record = s.blinds[s.current_blind or 0]
    if record and not record.completed then return record end
    if not create or not G.GAME.blind then return nil end
    local blind = G.GAME.blind
    if not blind.chips or blind.chips <= 0 then return nil end
    local kind = blind:get_type() or 'Boss'
    record = {
        ante = current_ante(), kind = kind,
        label = tostring(current_ante()) .. (({Small = 'S', Big = 'B', Boss = 'BOSS'})[kind] or kind),
        target = blind.chips, best = 0, hands_used = 0,
        partial = (G.GAME.current_round.hands_played or 0) > 0,
    }
    s.blinds[#s.blinds + 1] = record
    s.current_blind = #s.blinds
    return record
end

safe_wrap(Blind, 'set_blind', function(ref)
    return function(self, blind, reset, ...)
        if not reset then RS.capture_snapshot() end
        local result = ref(self, blind, reset, ...)
        if not reset and blind and blind.name and G.GAME.blind == self and RS.stats() then
            -- set_blind is called once at the start of each played blind.
            local s = RS.stats()
            local previous = (s.blinds or {})[s.current_blind or 0]
            if previous then previous.completed = true end
            RS.blind_record(true)
            RS.capture_snapshot()
        end
        return result
    end
end)

safe_wrap(_G, 'end_round', function(ref)
    return function(...)
        RS.capture_snapshot()
        local record = RS.blind_record(true)
        if record then
            local round = G.GAME.current_round
            record.target = G.GAME.blind.chips
            record.total_score = G.GAME.chips
            record.hands_used = round.hands_played or 0
            record.unused = math.max(0, round.hands_left or 0)
            record.won = G.GAME.chips >= record.target
            record.completed = true
        end
        return ref(...)
    end
end)

safe_wrap(_G, 'set_hand_usage', function(ref)
    return function(hand, ...)
        local pa = RS.pa()
        if pa then
            pa.hand_types = pa.hand_types or {}
            bump(pa.hand_types, hand, 1)
        end
        return ref(hand, ...)
    end
end)

safe_wrap(Game, 'update_shop', function(ref)
    return function(self, dt, ...)
        local s = RS.stats()
        if s and not G.STATE_COMPLETE and not G.shop then
            s.shops = s.shops or {}
            local blind = (s.blinds or {})[s.current_blind or 0]
            local ante = blind and blind.ante or current_ante()
            local key = tostring(ante) .. ':' .. tostring(G.GAME.round or 0)
            local last = s.shops[#s.shops]
            if not last or last.key ~= key then
                local interest = not (G.GAME.modifiers or {}).no_interest and (G.GAME.interest_amount or 0) > 0
                s.shops[#s.shops + 1] = {
                    key = key, ante = ante, cash = G.GAME.dollars or 0,
                    cap = interest and G.GAME.interest_cap or false,
                    label = blind and blind.label or (tostring(ante) .. '?'),
                }
            end
        end
        return ref(self, dt, ...)
    end
end)

-- ------------------------------------------------------------
-- Hooks
-- ------------------------------------------------------------

-- Fresh stats every new run; loaded runs restore their own saved stats.
safe_wrap(Game, 'init_game_object', function(ref)
    return function(self, ...)
        local t = ref(self, ...)
        t.run_stats = RS.fresh_stats()
        return t
    end
end)

-- Mirror EVERY vanilla career stat into the run (totals + per-ante).
-- This is what makes the Stats tab track "each of the native game's stats".
safe_wrap(_G, 'inc_career_stat', function(ref)
    return function(stat, mod, ...)
        local s = RS.stats()
        if s and type(stat) == 'string' then
            local n = mod or 0
            bump(s.career, stat, n)
            local pa = RS.pa()
            if pa then bump(pa.career, stat, n) end
        end
        return ref(stat, mod, ...)
    end
end)

-- Steamodded probability tracking uses its API for vanilla and modded rolls,
-- keyed by seed. The standalone observer below handles vanilla comparisons.
-- 'space' (Space Joker), 'bloodstone', '8ball', 'glass', 'lucky_mult',
-- 'lucky_money', 'business', 'wheel_of_fortune', 'gros_michel', 'cavendish',
-- 'halu<ante>' (Hallucination), etc.
function RS.prob_seed_name(seed)
    local known = {
        space = 'Space Joker',
        bloodstone = 'Bloodstone',
        ['8ball'] = '8 Ball',
        glass = 'Glass Card',
        lucky_mult = 'Lucky Card (Mult)',
        lucky_money = 'Lucky Card ($)',
        business = 'Business Card',
        wheel_of_fortune = 'Wheel of Fortune',
        gros_michel = 'Gros Michel',
        cavendish = 'Cavendish',
    }
    if known[seed] then return known[seed] end
    if type(seed) == 'string' and seed:sub(1, 4) == 'halu' then return 'Hallucination' end
    return seed
end

function RS.record_probability(card, seed, base_num, base_den, result, identifier, no_mod)
    local s = RS.stats()
    if s and type(seed) == 'string' then
        local e = s.probs[seed]
        if not e then
            e = { rolls = 0, hits = 0, num = base_num or 1, den = base_den or 2 }
            s.probs[seed] = e
        end
        e.rolls = e.rolls + 1
        e.num, e.den = base_num or 1, base_den or 2
        e.identifier, e.no_mod = identifier or seed, no_mod or false
        e.card_key = card and card.config and (card.config.center_key or (card.config.center or {}).key)
        if result then e.hits = e.hits + 1 end
        local pa = RS.pa()
        if pa then
            local pe = pa.probs[seed]
            if not pe then
                pe = { rolls = 0, hits = 0 }
                pa.probs[seed] = pe
            end
            pe.rolls = pe.rolls + 1
            if result then pe.hits = pe.hits + 1 end
        end
    end
end

safe_wrap(SMODS, 'pseudorandom_probability', function(ref)
    return function(card, seed, base_num, base_den, identifier, no_mod, ...)
        local ret = ref(card, seed, base_num, base_den, identifier, no_mod, ...)
        RS.record_probability(card, seed, base_num, base_den, ret, identifier, no_mod)
        return ret
    end
end)

-- Vanilla performs its comparisons directly against pseudorandom(). Observe the
-- existing sample without drawing another one or changing the value returned.
safe_wrap(_G, 'pseudorandom', function(ref)
    return function(seed, min, max, ...)
        local sample = ref(seed, min, max, ...)
        if not (SMODS and SMODS.pseudorandom_probability) and min == nil and max == nil
            and RS.record_vanilla_roll then
            RS.record_vanilla_roll(seed, sample)
        end
        return sample
    end
end)

-- Glass destructions from every cause (scoring shatters, Tarots, etc.);
-- the glass break ROLL itself is tracked via the 'glass' seed above.
safe_wrap(Card, 'shatter', function(ref)
    return function(self, ...)
        local s = RS.stats()
        if s and self.ability and self.ability.name == 'Glass Card' then
            s.glass.destroyed = s.glass.destroyed + 1
        end
        return ref(self, ...)
    end
end)

-- Consumable uses (Tarot / Planet / Spectral)
safe_wrap(Card, 'use_consumeable', function(ref)
    return function(self, area, copier, ...)
        local s = RS.stats()
        if s and self.ability then
            local set = self.ability.set
            if set == 'Tarot' or set == 'Planet' or set == 'Spectral' then
                s.consumables_used.total = s.consumables_used.total + 1
                s.consumables_used[set] = (s.consumables_used[set] or 0) + 1
                local pa = RS.pa()
                if pa then
                    pa.consumables = pa.consumables + 1
                    pa.cset[set] = (pa.cset[set] or 0) + 1
                end
                local key = (self.config and self.config.center_key) or self.ability.name or 'unknown'
                s.consumables_by_key[key] = (s.consumables_by_key[key] or 0) + 1
            end
        end
        return ref(self, area, copier, ...)
    end
end)

-- Money made / spent (totals + per-ante buckets)
safe_wrap(_G, 'ease_dollars', function(ref)
    return function(mod, instant, ...)
        local s = RS.stats()
        local pending = RS._next_income
        RS._next_income = nil
        if s and type(mod) == 'number' and mod ~= 0 then
            local payout = pending and pending.stats == s and pending.payout
            local pa
            if mod > 0 and payout then
                pa = s.per_ante[payout.ante]
                if not pa then pa = new_pa(); s.per_ante[payout.ante] = pa end
                local known = 0
                for _, value in pairs(payout.categories) do known = known + value end
                -- Unknown negative adjustments cannot be split reliably.
                if known <= mod then
                    pa.income = pa.income or {}
                    for category, value in pairs(payout.categories) do bump(pa.income, category, value) end
                end
            else
                pa = RS.pa() or new_pa()
                if mod > 0 then
                    local scope = income_scopes[income_thread()]
                    local category = pending and pending.stats == s and pending.category
                        or (scope and scope.stats == s and scope.category)
                    if category then pa.income = pa.income or {}; bump(pa.income, category, mod) end
                end
            end
            if mod < 0 then
                s.money_spent = s.money_spent - mod
                pa.spent = (pa.spent or 0) - mod
            else
                s.money_earned = s.money_earned + mod
                pa.earned = (pa.earned or 0) + mod
            end
        end
        return ref(mod, instant, ...)
    end
end)

-- Run-scoped high scores: best hand score (+per ante) and most money held
safe_wrap(_G, 'check_and_set_high_score', function(ref)
    return function(stat, score, ...)
        local s = RS.stats()
        if s and type(score) == 'number' then
            if stat == 'hand' then
                local record = RS.blind_record(true)
                if record then
                    record.best = math.max(record.best or 0, score)
                    record.target = G.GAME.blind.chips
                end
                if score > (s.best_hand_score or 0) then s.best_hand_score = score end
                local pa = RS.pa()
                if pa then
                    pa.hand_scores = pa.hand_scores or {}
                    pa.hand_scores[#pa.hand_scores + 1] = score
                end
                if pa and score > (pa.best_score or 0) then pa.best_score = score end
            elseif stat == 'most_money' then
                if score > (s.most_money or 0) then s.most_money = score end
                local pa = RS.pa()
                if pa and score > (pa.most_money or 0) then pa.most_money = score end
            end
        end
        return ref(stat, score, ...)
    end
end)

-- Blind skips
if G.FUNCS.skip_blind then
    safe_wrap(G.FUNCS, 'skip_blind', function(ref)
        return function(e, ...)
            local s = RS.stats()
            if s then
                s.skips = s.skips + 1
                local pa = RS.pa(); if pa then pa.skips = pa.skips + 1 end
            end
            return ref(e, ...)
        end
    end)
end

-- Per-card played/discarded counts. Key = '<Suit>:<base id>' so duplicates
-- (cards added to the deck later) merge into the same one of the 52 entries.
local CARD_RANK_LABEL = { [11] = 'J', [12] = 'Q', [13] = 'K', [14] = 'A' }

function RS.card_key(card)
    if not (card and card.base and card.base.suit and card.base.id) then return nil end
    return tostring(card.base.suit) .. ':' .. tostring(card.base.id)
end

function RS.card_rank_label(id)
    return CARD_RANK_LABEL[id] or tostring(id)
end

local shop_tokens = setmetatable({}, {__mode = 'k'})
local function shop_visit()
    local stats = RS.stats()
    local blind = stats and (stats.blinds or {})[stats.current_blind or 0]
    local ante = blind and blind.ante or snapshot_ante() or current_ante()
    return tostring(ante) .. ':' .. tostring(G.GAME.round or 0), ante, blind and blind.label or tostring(ante)
end

function RS.begin_shop_stock(reroll)
    local stats = RS.stats()
    if not stats then return end
    stats.shop_stock = stats.shop_stock or {}
    local key, ante, label = shop_visit()
    local last = stats.shop_stock[#stats.shop_stock]
    if not reroll and last and last.visit == key then return last end
    local group = {visit = key, ante = ante, label = label,
        reroll = reroll and last and last.visit == key and last.reroll + 1 or (reroll and 1 or 0),
        capacity = (G.GAME.shop or {}).joker_max or 2, cards = {}}
    stats.shop_stock[#stats.shop_stock + 1] = group
    return group
end

local function shop_offer(card)
    local center = card.config and card.config.center or {}
    local set = center.set or (card.ability or {}).set
    local playing = set == 'Default' or set == 'Enhanced' or card.playing_card
    local category = playing and 'Playing' or set
    if category ~= 'Joker' and category ~= 'Tarot' and category ~= 'Planet'
        and category ~= 'Spectral' and category ~= 'Playing' and category ~= 'Voucher' then return end
    local key = playing and RS.card_key(card) or (center.key or (card.config or {}).center_key)
    if not key then return end
    local name
    if playing then
        name = RS.card_rank_label(card.base.id) .. ' ' .. localize(card.base.suit, 'suits_plural')
    elseif G.localization and G.localization.descriptions and G.localization.descriptions[set]
        and G.localization.descriptions[set][key] then
        name = localize{type = 'name_text', set = set, key = key}
    end
    name = type(name) == 'string' and name or (card.ability or {}).name or key
    local edition = 'base'
    if card.edition then
        if type(card.edition.type) == 'string' then edition = card.edition.type
        else
            local keys = {}
            for k, value in pairs(card.edition) do if value == true then keys[#keys + 1] = k end end
            table.sort(keys)
            edition = keys[1] or 'base'
        end
    end
    return {key = key, category = category, name = name, cost = card.cost or 0,
        edition = edition,
        enhancement = playing and set == 'Enhanced' and (card.ability or {}).name or nil,
        seal = card.seal}
end

function RS.record_shop_voucher(card, bought)
    local stats = RS.stats()
    if not stats then return end
    local offer = shop_offer(card)
    if not offer or offer.category ~= 'Voucher' then return end
    if bought and not (card.shop_voucher or (G.shop_vouchers and card.area == G.shop_vouchers)) then return end
    stats.shop_vouchers = stats.shop_vouchers or {}
    -- Vouchers refresh when the ante advances, including the post-Boss shop.
    local ante = current_ante()
    local rows = stats.shop_vouchers[ante] or {}
    stats.shop_vouchers[ante] = rows
    for _, row in ipairs(rows) do
        if row.key == offer.key then
            if bought then row.bought, row.paid = true, offer.cost end
            return row
        end
    end
    offer.bought, offer.paid = bought == true, bought and offer.cost or nil
    rows[#rows + 1] = offer
    return offer
end

function RS.capture_shop_vouchers()
    if not RS.stats() then return end
    for _, card in ipairs((G.shop_vouchers or {}).cards or {}) do RS.record_shop_voucher(card, false) end
end

function RS.capture_shop_stock()
    RS.capture_shop_vouchers()
    local stats = RS.stats()
    if not stats or not G.shop_jokers or not G.shop_jokers.cards then return end
    local group = RS.begin_shop_stock(false)
    group.capacity = math.max(group.capacity, (G.GAME.shop or {}).joker_max or 2)
    local seen = {}
    for index, offer in ipairs(group.cards) do seen[offer.token] = index end
    for _, card in ipairs(G.shop_jokers.cards) do
        local offer = shop_offer(card)
        if offer then
            local token = card.sort_id and ('card:' .. tostring(card.sort_id)) or shop_tokens[card]
            if not token then
                stats.shop_token_id = (stats.shop_token_id or 0) + 1
                token = 'fallback:' .. stats.shop_token_id
                shop_tokens[card] = token
            end
            offer.token = token
            local index = seen[token] or (#group.cards + 1)
            group.cards[index], seen[token] = offer, index
        end
    end
end

local function record_card_keys(bucket, field, cards)
    if not bucket then return end
    local t = bucket[field]
    if not t then t = {}; bucket[field] = t end
    for _, c in ipairs(cards) do
        local k = RS.card_key(c)
        if k then t[k] = (t[k] or 0) + 1 end
    end
end

function RS.record_card_trigger(card, kind)
    if not card or card.debuff or not RS.card_key(card) then return end
    if kind ~= 'scoring' and kind ~= 'held' then return end
    record_card_keys(RS.pa(), kind .. '_triggers', {card})
end

function RS.record_vanilla_trigger(card, kind, effects)
    if SMODS then return end -- Steamodded uses its effect application hook.
    for _, effect in ipairs(effects or {}) do
        if type(effect) == 'table' and next(effect) then
            RS.record_card_trigger(card, kind)
            return
        end
    end
end

-- Count applied passes, after Joker effects have joined the card's own effects.
-- Scoping avoids counting unrelated calculate_effect/preview calls. Quantum
-- enhancements share one pass, while Red Seal/Joker repetitions get new passes.
local trigger_scopes = setmetatable({}, {__mode = 'k'})
local trigger_main = {}
local function trigger_thread() return coroutine.running() or trigger_main end
for _, method in ipairs({'score_card', 'calculate_end_of_round_effects'}) do
    safe_wrap(SMODS, method, function(ref)
        return function(first, second, ...)
            local context = method == 'score_card' and second or first
            local thread = trigger_thread()
            local previous = trigger_scopes[thread]
            local area = context and context.cardarea
            trigger_scopes[thread] = {card = method == 'score_card' and first or nil,
                area = area, kind = area == G.play and 'scoring' or (area == G.hand and 'held' or nil)}
            local result = pack_results(ref(first, second, ...))
            trigger_scopes[thread] = previous
            return unpack(result, 1, result.n)
        end
    end)
end
safe_wrap(SMODS, 'trigger_effects', function(ref)
    return function(effects, card, ...)
        local scope = trigger_scopes[trigger_thread()]
        local result = pack_results(ref(effects, card, ...))
        if scope and scope.kind and card and (scope.card == card or (not scope.card and card.area == scope.area))
            and result[1] and result[1].calculated then
            RS.record_card_trigger(card, scope.kind)
        end
        return unpack(result, 1, result.n)
    end
end)

local function draw_token_key(card)
    if card.playing_card then return 'card:' .. tostring(card.playing_card) end
    if card.sort_id then return 'sort:' .. tostring(card.sort_id) end
end

function RS.record_card_plays(cards)
    local stats = RS.stats()
    if not stats then return end
    for _, card in ipairs(cards) do
        local token = (stats.draw_tokens or {})[draw_token_key(card)]
        if token and not token.used then
            token.used = true
            local bucket = (stats.per_ante or {})[token.ante]
            if bucket then
                bucket.usage_played = bucket.usage_played or {}
                bump(bucket.usage_played, token.key, 1)
            end
        end
    end
end

-- Cards played: by the time evaluate_play runs, the played cards live in
-- G.play.cards (G.hand.highlighted is already cleared).
if G.FUNCS.evaluate_play then
    safe_wrap(G.FUNCS, 'evaluate_play', function(ref)
        return function(e, ...)
            local s = RS.stats()
            local played = {}
            if s and G.play and G.play.cards then
                for _, c in ipairs(G.play.cards) do played[#played + 1] = c end
            end
            local r = ref(e, ...)
            if s and #played > 0 then
                print('RunStats: evaluate_play recorded ' .. #played .. ' cards')
                record_card_keys(RS.pa(), 'cards_played', played)
                RS.record_card_plays(played)
            else
                print('RunStats: evaluate_play hook fired, s=' .. tostring(s ~= nil) .. ' played=' .. #played)
            end
            return r
        end
    end)
end

-- Cards discarded: snapshot the highlighted cards before the discard runs.
if G.FUNCS.discard_cards_from_highlighted then
    safe_wrap(G.FUNCS, 'discard_cards_from_highlighted', function(ref)
        return function(e, ...)
            local s = RS.stats()
            local discarded = {}
            if s and G.hand and G.hand.highlighted then
                for _, c in ipairs(G.hand.highlighted) do discarded[#discarded + 1] = c end
            end
            local r = ref(e, ...)
            if s and #discarded > 0 then
                record_card_keys(RS.pa(), 'cards_discarded', discarded)
            end
            return r
        end
    end)
end

-- Record completed deck-to-hand transfers, rather than estimating deck shrinkage.
-- Weak keys keep removed/destroyed cards from being retained by the tracker.
local draw_sources = setmetatable({}, { __mode = 'k' })

safe_wrap(CardArea, 'remove_card', function(ref)
    return function(self, ...)
        local card = ref(self, ...)
        if card then
            local stats = RS.stats()
            draw_sources[card] = self == G.deck and stats
                and { stats = stats, bucket = RS.pa(), ante = current_ante() } or nil
        end
        return card
    end
end)

safe_wrap(CardArea, 'emplace', function(ref)
    return function(self, card, ...)
        local source = card and draw_sources[card]
        if card then draw_sources[card] = nil end
        local result = ref(self, card, ...)
        if self == G.shop_jokers then RS.capture_shop_stock() end
        if self == G.shop_vouchers then RS.capture_shop_vouchers() end
        if source and self == G.hand and card.area == self and source.stats == RS.stats() then
            local stats, bucket = source.stats, source.bucket
            stats.cards_drawn = (stats.cards_drawn or 0) + 1
            if bucket then
                bucket.drawn = (bucket.drawn or 0) + 1
                record_card_keys(bucket, 'cards_drawn', { card })
                local key = RS.card_key(card)
                local token_key = draw_token_key(card)
                if key and token_key then
                    bucket.usage_drawn = bucket.usage_drawn or {}
                    bump(bucket.usage_drawn, key, 1)
                    stats.draw_tokens = stats.draw_tokens or {}
                    stats.draw_tokens[token_key] = { ante = source.ante, key = key, used = false }
                end
            end
        end
        return result
    end
end)

-- Shop purchases (jokers bought has no vanilla career stat — track our own)
if G.FUNCS.buy_from_shop then
    safe_wrap(G.FUNCS, 'buy_from_shop', function(ref)
        return function(e, ...)
            local s = RS.stats()
            local t = e and e.config and e.config.ref_table
            if s and t and t.ability and t.ability.set == 'Joker' and not t.playing_card then
                s.jokers_bought = s.jokers_bought + 1
                local pa = RS.pa(); if pa then pa.jokers_bought = pa.jokers_bought + 1 end
            end
            return ref(e, ...)
        end
    end)
end

-- Count real pack opens, including free/tag packs and all pack sizes.
local PACK_KINDS = { 'Arcana', 'Celestial', 'Spectral', 'Standard', 'Buffoon' }

function RS.pack_count(kind)
    local count = 0
    for ante, bucket in pairs((RS.stats() or {}).per_ante or {}) do
        if RS.in_slice(ante) then
            local types = bucket.pack_types or {}
            if kind == 'Other' then
                local known = 0
                for _, family in ipairs(PACK_KINDS) do known = known + (types[family] or 0) end
                count = count + math.max(0, (bucket.packs or 0) - known)
            else
                count = count + (types[kind] or 0)
            end
        end
    end
    return count
end

safe_wrap(Card, 'open', function(ref)
    return function(self, ...)
        local was_opening = self.opening
        local s, pa = RS.stats(), RS.pa()
        local result = ref(self, ...)
        if s and self.ability and self.ability.set == 'Booster' and self.opening and not was_opening then
            local center = self.config and self.config.center or {}
            local kind = center.kind
            if not kind then
                for _, candidate in ipairs(PACK_KINDS) do
                    if (self.ability.name or ''):find(candidate, 1, true) then kind = candidate; break end
                end
            end
            s.packs_opened = (s.packs_opened or 0) + 1
            if pa then
                pa.packs = (pa.packs or 0) + 1
                pa.pack_types = pa.pack_types or {}
                bump(pa.pack_types, kind or 'Other', 1)
            end
        end
        return result
    end
end)

-- Vouchers redeemed through the use-card action.
if G.FUNCS.use_card then
    safe_wrap(G.FUNCS, 'use_card', function(ref)
        return function(e, mute, nosave, ...)
            local s = RS.stats()
            local card = e and e.config and e.config.ref_table
            if s and card and card.ability then
                if card.ability.set == 'Voucher' then
                    s.vouchers_bought = (s.vouchers_bought or 0) + 1
                    local pa = RS.pa(); if pa then pa.vouchers = (pa.vouchers or 0) + 1 end
                end
            end
            return ref(e, mute, nosave, ...)
        end
    end)
end

-- ------------------------------------------------------------
-- Chart object (custom-drawn love2d object for the dashboard)
-- ------------------------------------------------------------

RSChart = Moveable:extend()

function RSChart:init(config)
    config = config or {}
    self.config = config
    Moveable.init(self, config.X or 0, config.Y or 0, config.w or 3.4, config.h or 2.4)
    self.font = G.LANG.font
    self.states.drag.can = false
end

-- Text inside the chart canvas; scale matches DynaText 'scale' conventions.
-- The game never sets LANG font as the active font, so set it explicitly.
function RSChart:_text(s, x, y, scale, colour, center)
    love.graphics.setColor(colour)
    love.graphics.setFont(self.font.FONT)
    local k = scale * self.font.FONTSCALE / G.TILESIZE
    if center then x = x - self.font.FONT:getWidth(s) * k / 2 end
    love.graphics.print(s, x, y, 0, k, k)
end

-- All chart types share axis scaling, legends and empty-state behavior.
function RSChart:draw()
    if not self.VT or not self.VT.w then return end
    prep_draw(self, 1)
    local cfg, w, h = self.config, self.VT.w, self.VT.h
    local data = cfg.data and cfg.data() or {}
    local labels, series = data.antes or {}, data.series or {}
    local graphics = love.graphics
    graphics.setColor({0, 0, 0, 0.55})
    graphics.rectangle('fill', 0, 0, w, h)
    if #labels == 0 or #series == 0 then
        self:_text(data.empty or 'No data yet', w / 2, h / 2 - 0.1, 0.23, {1, 1, 1, 0.6}, true)
        graphics.pop()
        return
    end
    local horizontal = cfg.kind == 'horizontal'
    local stacked = cfg.kind == 'stacked'
    local left, right, top, bottom = horizontal and 1.45 or 0.58, 0.2, 0.32, 0.3
    local legend_scale, legend_step, legend_rows, legend_widest = 0.18, 0.15, 1, 0
    repeat
        local legend_x = 0.08
        legend_rows, legend_step, legend_widest = 1, legend_scale * 0.84, 0
        for _, ser in ipairs(series) do
            local width = 0.2 + self.font.FONT:getWidth(ser.name) * (legend_scale * self.font.FONTSCALE / G.TILESIZE)
            legend_widest = math.max(legend_widest, width)
            if legend_x + width > w and legend_x > 0.08 then legend_x, legend_rows = 0.08, legend_rows + 1 end
            legend_x = legend_x + width + 0.12
        end
        top = 0.17 + legend_rows * legend_step
        if top > h * 0.55 or legend_widest > w - 0.08 then legend_scale = legend_scale * 0.85 end
    until top <= h * 0.55 and legend_widest <= w - 0.08
    local pw, ph = w - left - right, h - top - bottom
    local function transform(v)
        return cfg.log and math.log10(math.max(0, v) + 1) or v
    end
    local lo, hi = 0, 0
    for i = 1, #labels do
        local total = 0
        for _, ser in ipairs(series) do
            local value = ser.values[i]
            if type(value) == 'number' then
                local v = transform(value)
                lo, hi = math.min(lo, v), math.max(hi, v)
                total = total + math.max(0, v)
            end
        end
        if stacked then hi = math.max(hi, total) end
    end
    if hi == lo then hi = lo + 1 end
    local ticks = {}
    if cfg.log then
        for i = 0, 3 do ticks[#ticks + 1] = hi - (hi - lo) * i / 3 end
    else
        -- Readable integer ticks for counts and dollars (no fractional hands).
        local rough = (hi - lo) / 4
        local power = math.pow(10, math.floor(math.log10(rough)))
        local unit = rough / power
        local step = math.max(1, (unit <= 1 and 1 or unit <= 2 and 2 or unit <= 5 and 5 or 10) * power)
        lo, hi = math.floor(lo / step) * step, math.ceil(hi / step) * step
        for value = lo, hi, step do ticks[#ticks + 1] = value end
    end
    local function y(v) return top + ph * (hi - transform(v)) / (hi - lo) end
    local function tick(v)
        if not cfg.log then return number_format(math.floor(v + 0.5)) end
        if cfg.log then v = math.pow(10, v) - 1 end
        if math.abs(v) < 0.001 then return '0' end
        if math.abs(v) < 10 then return string.format('%.1f', v) end
        return number_format(math.floor(v + 0.5))
    end
    -- Reserve plot space for every wrapped legend row.
    local lx, ly = 0.08, 0.02
    for _, ser in ipairs(series) do
        local width = 0.2 + self.font.FONT:getWidth(ser.name) * (legend_scale * self.font.FONTSCALE / G.TILESIZE)
        if lx + width > w and lx > 0.08 then lx, ly = 0.08, ly + legend_step end
        graphics.setColor(ser.colour)
        graphics.rectangle('fill', lx, ly + 0.02, 0.09, 0.09)
        self:_text(ser.name, lx + 0.13, ly, legend_scale, {1, 1, 1, 0.85})
        lx = lx + width + 0.12
    end
    if horizontal then
        local slot = ph / #labels
        local maxv = math.max(1, hi)
        for i, label in ipairs(labels) do
            local value = series[1].values[i] or 0
            local cy = top + (i - 1) * slot
            self:_text(tostring(label), 0.06, cy, math.min(0.19, slot * 1.05), {1, 1, 1, 0.85})
            graphics.setColor((data.colours or {})[i] or series[1].colour)
            local width = value / maxv * (pw - 0.3)
            if value > 0 then graphics.rectangle('fill', left, cy + slot * 0.15, width, slot * 0.65) end
            self:_text(tostring(value), left + width + 0.06, cy, math.min(0.19, slot * 1.05), {1, 1, 1, 0.85})
        end
    else
        for _, value in ipairs(ticks) do
            local gy = top + ph * (hi - value) / (hi - lo)
            graphics.setColor({1, 1, 1, 0.12})
            graphics.rectangle('fill', left, gy, pw, 0.008)
            self:_text(tick(value), 0.03, gy - 0.07, 0.18, {1, 1, 1, 0.6})
        end
        local slot = pw / #labels
        local function x(i) return left + (i - 0.5) * slot end
        if cfg.kind == 'line' then
            local original_line_width = graphics.getLineWidth()
            graphics.setLineWidth(0.022)
            if data.segments then
                for _, segment in ipairs(data.segments) do
                    graphics.setColor(series[segment.series].colour)
                    graphics.line(x(segment.i), y(segment.from), x(segment.j), y(segment.to))
                end
                for _, point in ipairs(data.points or {}) do
                    graphics.setColor(series[point.series].colour)
                    if #labels == 1 then graphics.line(left + pw * 0.15, y(point.value), left + pw * 0.85, y(point.value)) end
                    graphics.circle('fill', x(point.i), y(point.value), 0.032)
                end
            else
                for _, ser in ipairs(series) do
                    local previous
                    graphics.setColor(ser.colour)
                    for i = 1, #labels do
                        local v = ser.values[i]
                        if type(v) == 'number' then
                            local px, py = x(i), y(v)
                            if previous then graphics.line(previous[1], previous[2], px, py) end
                            graphics.circle('fill', px, py, 0.027)
                            previous = {px, py}
                        else
                            previous = nil -- missing history is a gap, never a zero
                        end
                    end
                end
            end
            graphics.setLineWidth(original_line_width)
        else
            local accum = {}
            local count = stacked and 1 or #series
            local bw = math.min(slot * 0.7 / count, 0.34)
            for si, ser in ipairs(series) do
                graphics.setColor(ser.colour)
                for i = 1, #labels do
                    local v = ser.values[i]
                    if type(v) == 'number' and v ~= 0 then
                        local base = stacked and (accum[i] or 0) or 0
                        local bx = x(i) - bw * count / 2 + (stacked and 0 or (si - 1) * bw)
                        local ya, yb = y(base), y(base + v)
                        graphics.rectangle('fill', bx, math.min(ya, yb), math.max(0.005, bw - 0.015), math.abs(yb - ya))
                        if stacked then accum[i] = base + v end
                    end
                end
            end
        end
        -- Limit tick density while always labelling the newest point.
        local max_labels = math.max(2, math.floor(pw / 0.55))
        local step = math.max(1, math.ceil(#labels / max_labels))
        for i = 1, #labels do
            if ((i - 1) % step == 0 and #labels - i >= math.ceil(step / 2)) or i == #labels then
                self:_text(tostring(labels[i]), x(i), h - bottom + 0.035, 0.17, {1, 1, 1, 0.75}, true)
            end
        end
    end
    graphics.pop()
end

-- ------------------------------------------------------------
-- Per-card bar chart (Cards tab): x = one entry per base card (52),
-- y = played / discarded / drawn counts, sliceable by ante + suit + rank.
-- Cards added to the deck merge into their base entry (52 total, counted
-- cumulatively in that entry).
-- ------------------------------------------------------------

RS._card_suit = 1 -- 1 = All suits
RS._card_rank = 1 -- 1 = All ranks
RS._card_mode = 1 -- Played, Discarded, Drawn, Use rate, Triggers
RS._show_scoring_triggers, RS._show_held_triggers = true, true

local CARD_SUITS = { 'Spades', 'Hearts', 'Diamonds', 'Clubs' }
local CARD_SUIT_COLOURS = {
    Spades   = { 0.45, 0.45, 0.58, 1 },
    Hearts   = { 0.95, 0.35, 0.4, 1 },
    Diamonds = { 0.95, 0.62, 0.25, 1 },
    Clubs    = { 0.35, 0.58, 0.95, 1 },
}
local CARD_RANKS = { 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14 }
local CARD_SUIT_OPTS = { 'All suits', 'Spades', 'Hearts', 'Diamonds', 'Clubs' }
local CARD_RANK_OPTS = { 'All ranks', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A' }
local CARD_MODE_OPTS = { 'Played', 'Discarded', 'Drawn', 'Use rate', 'Triggers' }
local CARD_MODE_FIELDS = { Played = 'cards_played', Discarded = 'cards_discarded', Drawn = 'cards_drawn' }
local CARD_RANK_ID = { J = 11, Q = 12, K = 13, A = 14 }

function RS.trigger_colour(colour, held)
    if not held then return colour end
    return {colour[1] + (1 - colour[1]) * 0.45, colour[2] + (1 - colour[2]) * 0.45,
        colour[3] + (1 - colour[3]) * 0.45, colour[4] or 1}
end

-- Chart data: one x bucket per RANK; within a bucket, one bar per suit
-- (colour-coded) holding that suit's count for the active mode.
function RS.card_chart_data()
    local suit = CARD_SUIT_OPTS[RS._card_suit or 1]
    local rank_opt = CARD_RANK_OPTS[RS._card_rank or 1]
    local suits = (suit == 'All suits') and CARD_SUITS or { suit }
    local ranks
    if rank_opt == 'All ranks' then
        ranks = CARD_RANKS
    else
        local id = CARD_RANK_ID[rank_opt] or tonumber(rank_opt)
        ranks = { id }
    end
    local mode = CARD_MODE_OPTS[RS._card_mode or 1]
    local field = CARD_MODE_FIELDS[mode]

    -- aggregate the selected field per (suit, rank id) over the ante slice
    local agg, usage_drawn, usage_played, scoring, held = {}, {}, {}, {}, {}
    local s = RS.stats()
    if s then
        for a, bucket in pairs(s.per_ante or {}) do
            if RS.in_slice(a) then
                local t = (field and bucket[field]) or {}
                for k, v in pairs(t) do
                    local suit_name, id_str = k:match('^([^:]+):(%d+)$')
                    if suit_name and id_str then
                        local sk = suit_name .. ':' .. id_str
                        agg[sk] = (agg[sk] or 0) + v
                    end
                end
                for key, count in pairs(bucket.usage_drawn or {}) do bump(usage_drawn, key, count) end
                for key, count in pairs(bucket.usage_played or {}) do bump(usage_played, key, count) end
                if mode == 'Triggers' then
                    for key, count in pairs(bucket.scoring_triggers or {}) do bump(scoring, key, count) end
                    for key, count in pairs(bucket.held_triggers or {}) do bump(held, key, count) end
                end
            end
        end
    end

    local labels, suits_shown, cols = {}, {}, {}
    for _, su in ipairs(suits) do
        suits_shown[#suits_shown + 1] = su
        cols[#cols + 1] = CARD_SUIT_COLOURS[su]
    end
    local values, segments, drawn_total, played_total = {}, {}, 0, 0
    for ri, id in ipairs(ranks) do
        labels[ri] = RS.card_rank_label(id)
        values[ri] = {}
        segments[ri] = {}
        for si, su in ipairs(suits_shown) do
            local key = su .. ':' .. id
            if mode == 'Triggers' then
                local sc = RS._show_scoring_triggers and (scoring[key] or 0) or 0
                local he = RS._show_held_triggers and (held[key] or 0) or 0
                values[ri][si], segments[ri][si] = sc + he, {sc, he}
            elseif mode == 'Use rate' then
                local drawn, played = usage_drawn[key] or 0, usage_played[key] or 0
                values[ri][si] = drawn > 0 and (100 * played / drawn) or false
                drawn_total, played_total = drawn_total + drawn, played_total + played
            else
                values[ri][si] = agg[key] or 0
            end
        end
    end
    return { ranks = ranks, labels = labels, suits = suits_shown, cols = cols,
        values = values, segments = mode == 'Triggers' and segments or nil,
        mode = mode, rate = mode == 'Use rate', drawn_total = drawn_total, played_total = played_total }
end

RSCardChart = Moveable:extend()

function RSCardChart:init(config)
    config = config or {}
    self.config = config
    Moveable.init(self, config.X or 0, config.Y or 0, config.w or 13.4, config.h or 4.6)
    self.font = G.LANG.font
    self.states.drag.can = false
end

function RSCardChart:_text(s, x, y, scale, colour, center)
    love.graphics.setColor(colour)
    love.graphics.setFont(self.font.FONT)
    local k = scale * self.font.FONTSCALE / G.TILESIZE
    if center then x = x - self.font.FONT:getWidth(s) * k / 2 end
    love.graphics.print(s, x, y, 0, k, k)
end

function RSCardChart:draw()
    if not self.VT or not self.VT.w then return end
    prep_draw(self, 1)
    local w, h = self.VT.w, self.VT.h
    local pad_l, pad_r, pad_t, pad_b = 0.5, 0.1, 0.3, 0.3
    local pw, ph = w - pad_l - pad_r, h - pad_t - pad_b

    love.graphics.setColor({0, 0, 0, 0.55})
    love.graphics.rectangle('fill', 0, 0, w, h)

    local data = self.config.data and self.config.data() or nil
    if data and data.ranks and #data.ranks > 0 then
        local n = #data.ranks
        local m = #data.suits
        local maxv = data.rate and 100 or 1
        for _, row in ipairs(data.values) do
            for _, v in ipairs(row) do if type(v) == 'number' and v > maxv then maxv = v end end
        end
        local function fmt_tick(v)
            if data.rate then return tostring(math.floor(v + 0.5)) .. '%' end
            if maxv <= 4 then return (string.format('%.2f', v):gsub('0+$', ''):gsub('%.$', '')) end
            if v >= 100 then return number_format(math.floor(v + 0.5)) end
            return string.format('%.1f', v)
        end
        -- gridlines + y ticks
        love.graphics.setColor({1, 1, 1, 0.12})
        for i = 1, 3 do
            local gy = pad_t + ph * i / 4
            love.graphics.rectangle('fill', pad_l, gy, pw, 0.008)
            self:_text(fmt_tick(maxv * (1 - i / 4)), 0.04, gy - 0.09, 0.2, {1, 1, 1, 0.55})
        end
        self:_text(fmt_tick(maxv), 0.04, pad_t - 0.09, 0.2, {1, 1, 1, 0.55})
        -- bars: one x bucket per rank, one bar per suit inside the bucket
        local slot = pw / n
        local bw = math.max(slot * 0.78 / m, 0.02)
        for ri = 1, n do
            local row = data.values[ri]
            for si = 1, m do
                local v = row[si]
                local x = pad_l + (ri - 1) * slot + slot / 2 - (bw * m) / 2 + (si - 1) * bw
                if data.segments then
                    local bottom = pad_t + ph
                    for index, count in ipairs(data.segments[ri][si]) do
                        if count > 0 then
                            local bh = count / maxv * ph
                            love.graphics.setColor(RS.trigger_colour(data.cols[si], index == 2))
                            love.graphics.rectangle('fill', x, bottom - bh, bw - 0.015, bh)
                            bottom = bottom - bh
                        end
                    end
                elseif type(v) == 'number' then
                    local bh = math.max(v / maxv * ph, v > 0 and 0.02 or 0.004)
                    love.graphics.setColor(data.cols[si])
                    love.graphics.rectangle('fill', x,
                        pad_t + ph - bh, bw - 0.015, bh)
                end
            end
            -- rank label under the bucket
            self:_text(data.labels[ri], pad_l + (ri - 1) * slot + slot / 2, h - pad_b + 0.02, 0.22,
                {1, 1, 1, 0.75}, true)
        end
        -- legend: suit swatches; mode indicator top-right
        local lx = pad_l
        for si, su in ipairs(data.suits) do
            love.graphics.setColor(data.cols[si])
            love.graphics.rectangle('fill', lx, 0.05, 0.13, 0.13)
            self:_text(su:sub(1, 1), lx + 0.17, 0.02, 0.22, {1, 1, 1, 0.85})
            lx = lx + 0.17 + self.font.FONT:getWidth(su:sub(1, 1)) * (0.22 * self.font.FONTSCALE / G.TILESIZE) + 0.12
        end
        if data.segments then
            self:_text('Base: Scoring   Light: Held In Hand', pad_l + 3.2, 0.02, 0.20, {1, 1, 1, 0.85})
        end
        -- mode indicator, right-aligned
        local mode_txt = 'showing: ' .. (data.mode or 'Played')
        local k = 0.24 * self.font.FONTSCALE / G.TILESIZE
        self:_text(mode_txt, w - pad_r - self.font.FONT:getWidth(mode_txt) * k, 0.02, 0.24, {1, 1, 1, 0.85})
    else
        self:_text('No card data in this slice yet', w / 2, h / 2 - 0.15, 0.3, {1, 1, 1, 0.5}, true)
    end
    love.graphics.pop()
end

-- ------------------------------------------------------------
-- UI — Stats tab (native high-scores style, run-scoped)
-- ------------------------------------------------------------

-- Sliced roll/hit counts for one probability seed.
function RS.prob_sliced(seed)
    local s = RS.stats()
    local rolls, hits = 0, 0
    if s then
        if RS.slice_is_full() then
            local e = s.probs and s.probs[seed]
            if e then rolls, hits = e.rolls, e.hits end
        else
            for a, bucket in pairs(s.per_ante or {}) do
                if RS.in_slice(a) then
                    local e = (bucket.probs or {})[seed]
                    if e then rolls, hits = rolls + e.rolls, hits + e.hits end
                end
            end
        end
    end
    return rolls, hits
end

-- Live view-model for the Stats tab: every value cell references this table
-- and updates as the slider moves (T nodes re-read ref_table each frame).
RS._sliceview = {}

function RS.rebuild_sliceview()
    local s = RS.stats() or RS.fresh_stats()
    local v = RS._sliceview
    local f, t = RS.slice_range()
    v.totals_title = RS.slice_is_full() and 'Run Totals' or ('Run Totals (Ante ' .. RS.ante_sel_label() .. ')')
    v.best_hand = number_format(RS.pa_max('best_score'))
    local scores = RS.score_summary()
    v.average_hand = scores.average and number_format(scores.average) or '--'
    v.median_hand = scores.median and number_format(scores.median) or '--'
    v.scored_hands = number_format(scores.count)
    local furthest = 0
    for a in pairs(s.per_ante or {}) do
        if RS.in_slice(a) then furthest = math.max(furthest, a) end
    end
    v.furthest = furthest > 0 and tostring(furthest) or '1'
    v.rounds = number_format(RS.career_sliced('c_rounds'))
    v.most_money = localize('$') .. number_format(RS.pa_max('most_money'))
    local mph, mpc = most_played_hand()
    v.most_played = mph .. (mpc > 0 and (' (' .. mpc .. ')') or '')
    v.earned = localize('$') .. number_format(RS.pa_sum('earned'))
    v.spent = localize('$') .. number_format(RS.pa_sum('spent'))
    v.hands_played = number_format(RS.career_sliced('c_hands_played'))
    v.cards_played = number_format(RS.career_sliced('c_cards_played'))
    v.face_cards = number_format(RS.career_sliced('c_face_cards_played'))
    v.cards_discarded = number_format(RS.career_sliced('c_cards_discarded'))
    v.cards_drawn = number_format(RS.pa_sum('drawn'))
    v.rerolls = number_format(RS.career_sliced('c_shop_rerolls'))
    v.jokers_bought = number_format(RS.pa_sum('jokers_bought'))
    v.cards_bought = number_format(RS.career_sliced('c_playing_cards_bought'))
    v.tarots_bought = number_format(RS.career_sliced('c_tarots_bought'))
    v.planets_bought = number_format(RS.career_sliced('c_planets_bought'))
    v.vouchers_bought = number_format(RS.career_sliced('c_vouchers_bought'))
    v.tarot_packs = number_format(RS.pack_count('Arcana'))
    v.planet_packs = number_format(RS.pack_count('Celestial'))
    v.standard_packs = number_format(RS.pack_count('Standard'))
    v.spectral_packs = number_format(RS.pack_count('Spectral'))
    v.buffoon_packs = number_format(RS.pack_count('Buffoon'))
    v.other_packs = number_format(RS.pack_count('Other'))
    v.packs = number_format(RS.pa_sum('packs'))
    v.jokers_sold = number_format(RS.career_sliced('c_jokers_sold'))
    v.cards_sold = number_format(RS.career_sliced('c_cards_sold'))
    local odds_fmt = function(seed)
        local rolls, hits = RS.prob_sliced(seed)
        local e = (RS.stats() and RS.stats().probs or {})[seed]
        local den = e and e.den or nil
        local expected = den and ('1 in ' .. tostring(math.floor(den / ((e.num or 1)) + 0.5))) or '--'
        return hits .. '/' .. rolls .. ' (' .. fmt_pct(hits, rolls) .. ')  ' .. expected
    end
    v.space_joker = odds_fmt('space')
    v.bloodstone = odds_fmt('bloodstone')
    v.ball8 = odds_fmt('8ball')
    v.lucky_mult = odds_fmt('lucky_mult')
    v.lucky_money = odds_fmt('lucky_money')
    v.glass_break = odds_fmt('glass')
    local grolls, ghits = RS.prob_sliced('glass')
    v.glass_rolled = number_format(grolls)
    v.glass_shattered = number_format(ghits)
    v.glass_destroyed = number_format(ghits > 0 and (s.glass.destroyed or 0) or 0)
    v.skips = number_format(RS.pa_sum('skips'))
    v.wins = number_format(RS.career_sliced('c_wins'))
    v.losses = number_format(RS.career_sliced('c_losses'))
end

-- Value cells bound to the live view-model (native black-pill styling kept)
local function native_row(label, key, value_colour)
    return { n = G.UIT.R, config = { align = 'cm', padding = 0.03, r = 0.1, colour = darken(G.C.JOKER_GREY, 0.1), emboss = 0.05 }, nodes = {
        { n = G.UIT.C, config = { align = 'cl', padding = 0.03, minw = 1.35, maxw = 1.35 }, nodes = {
            { n = G.UIT.T, config = { text = label, scale = 0.27, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
        } },
        { n = G.UIT.C, config = { align = 'cl', minh = 0.34, r = 0.1, minw = 1.5, colour = G.C.BLACK, emboss = 0.05 }, nodes = {
            { n = G.UIT.C, config = { align = 'cm', padding = 0.03, r = 0.1, minw = 1.5, maxw = 1.5 }, nodes = {
                { n = G.UIT.T, config = { ref_table = RS._sliceview, ref_value = key,
                    scale = 0.26, colour = value_colour or G.C.FILTER, shadow = true } },
            } },
        } },
    } }
end

local function text_row(label, key)
    return { n = G.UIT.R, config = { align = 'cm', padding = 0.025, r = 0.1, colour = darken(G.C.JOKER_GREY, 0.1), emboss = 0.05 }, nodes = {
        { n = G.UIT.C, config = { align = 'cl', padding = 0.04, minw = 1.35, maxw = 1.35 }, nodes = {
            { n = G.UIT.T, config = { text = label, scale = 0.25, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
        } },
        { n = G.UIT.C, config = { align = 'cr', padding = 0.04, minw = 1.75, maxw = 1.75 }, nodes = {
            { n = G.UIT.T, config = { ref_table = RS._sliceview, ref_value = key,
                scale = 0.25, colour = G.C.YELLOW, shadow = true } },
        } },
    } }
end

local function section_title(text)
    return { n = G.UIT.R, config = { align = 'cl', padding = 0.04 }, nodes = {
        { n = G.UIT.T, config = { text = text, scale = 0.3, colour = G.C.WHITE, shadow = true } },
    } }
end

-- Match the pools used by reset_idol_card/reset_castle_card. Count base
-- identities: Wild cards are not extra copies of every suit in these rolls.
function RS.joker_target_summary()
    local result = {total = #(G.playing_cards or {}), idol = {}, castle = {}, idol_total = 0, castle_total = 0}
    local idols, suits = {}, {}
    for _, card in ipairs(G.playing_cards or {}) do
        local base = card.base or {}
        local stone = card.ability and card.ability.effect == 'Stone Card'
        local no_suit = SMODS and SMODS.has_no_suit and SMODS.has_no_suit(card)
        local no_rank = SMODS and SMODS.has_no_rank and SMODS.has_no_rank(card)
        if not stone and not no_suit and base.suit then
            result.castle_total = result.castle_total + 1
            suits[base.suit] = (suits[base.suit] or 0) + 1
            if not no_rank and base.id then
                result.idol_total = result.idol_total + 1
                local key = RS.card_key(card)
                idols[key] = idols[key] or {suit = base.suit, rank = base.id, count = 0}
                idols[key].count = idols[key].count + 1
            end
        end
    end
    for _, entry in pairs(idols) do result.idol[#result.idol + 1] = entry end
    -- Keep the four standard suits visible even when a suit has no copies.
    for _, suit in ipairs(CARD_SUITS) do suits[suit] = suits[suit] or 0 end
    for suit, count in pairs(suits) do result.castle[#result.castle + 1] = {suit = suit, count = count} end
    local function order(a, b)
        if a.count ~= b.count then return a.count > b.count end
        if a.suit ~= b.suit then return a.suit < b.suit end
        return (a.rank or 0) > (b.rank or 0)
    end
    for _, kind in ipairs({'idol', 'castle'}) do
        table.sort(result[kind], order)
        local total = result[kind .. '_total']
        for _, entry in ipairs(result[kind]) do
            entry.total = total
            entry.percentage = total > 0 and entry.count / total * 100 or 0
        end
    end
    return result
end

local function joker_target_columns()
    local data = RS.joker_target_summary()
    local columns = {}
    for _, kind in ipairs({'idol', 'castle'}) do
        local nodes = {section_title(kind == 'idol' and 'The Idol — Top Targets' or 'Castle — Suits')}
        for i = 1, math.min(4, #data[kind]) do
            local entry = data[kind][i]
            local suit = localize(entry.suit, 'suits_plural')
            local label = kind == 'idol' and (RS.card_rank_label(entry.rank) .. ' ' .. suit) or suit
            nodes[#nodes + 1] = {n = G.UIT.R, config = {align = 'cm', padding = 0.025}, nodes = {
                {n = G.UIT.C, config = {align = 'cl', minw = 2.6}, nodes = {
                    {n = G.UIT.T, config = {text = label, scale = 0.26,
                        colour = CARD_SUIT_COLOURS[entry.suit] or G.C.UI.TEXT_LIGHT, shadow = true}},
                }},
                {n = G.UIT.C, config = {align = 'cr', minw = 2.6}, nodes = {
                    {n = G.UIT.T, config = {text = string.format('%d / %d  (%0.1f%%)', entry.count, entry.total, entry.percentage),
                        scale = 0.26, colour = G.C.UI.TEXT_LIGHT, shadow = true}},
                }},
            }}
        end
        if data[kind .. '_total'] == 0 then nodes[#nodes + 1] = section_title('No eligible cards') end
        columns[#columns + 1] = {n = G.UIT.C, config = {align = 'tm', padding = 0.08, minw = 6.2}, nodes = nodes}
    end
    return {
        {n = G.UIT.R, config = {align = 'cm'}, nodes = columns},
    }
end

local function stats_tab_columns()
    RS.rebuild_sliceview()

    -- Column 1: High scores (sliced)
    local c1 = { section_title('High Scores') }
    c1[#c1 + 1] = native_row('Best Hand', 'best_hand', G.C.RED)
    c1[#c1 + 1] = native_row('Furthest Ante', 'furthest')
    c1[#c1 + 1] = native_row('Rounds Beaten', 'rounds')
    c1[#c1 + 1] = native_row('Most Money', 'most_money', G.C.MONEY)
    c1[#c1 + 1] = text_row('Most Played', 'most_played')
    c1[#c1 + 1] = section_title('Score Consistency')
    c1[#c1 + 1] = native_row('Average Hand', 'average_hand', G.C.BLUE)
    c1[#c1 + 1] = native_row('Median Hand', 'median_hand', G.C.PURPLE)
    c1[#c1 + 1] = native_row('Hands Tracked', 'scored_hands')

    -- Column 2: Run totals (vanilla career stats, this run only)
    local c2 = {}
    c2[#c2 + 1] = { n = G.UIT.R, config = { align = 'cl', padding = 0.04 }, nodes = {
        { n = G.UIT.T, config = { ref_table = RS._sliceview, ref_value = 'totals_title',
            scale = 0.3, colour = G.C.WHITE, shadow = true } },
    } }
    c2[#c2 + 1] = native_row('Dollars Earned', 'earned', G.C.MONEY)
    c2[#c2 + 1] = native_row('Dollars Spent', 'spent', G.C.RED)
    c2[#c2 + 1] = native_row('Hands Played', 'hands_played', G.C.BLUE)
    c2[#c2 + 1] = native_row('Cards Played', 'cards_played')
    c2[#c2 + 1] = native_row('Face Cards', 'face_cards')
    c2[#c2 + 1] = native_row('Cards Discarded', 'cards_discarded', G.C.RED)
    c2[#c2 + 1] = native_row('Cards Drawn', 'cards_drawn')
    c2[#c2 + 1] = native_row('Shop Rerolls', 'rerolls', G.C.GREEN)

    -- Column 3: Purchases & sales
    local c3 = { section_title('Purchases & Sales') }
    c3[#c3 + 1] = native_row('Jokers Bought', 'jokers_bought', G.C.GREEN)
    c3[#c3 + 1] = native_row('Cards Bought', 'cards_bought', G.C.MONEY)
    c3[#c3 + 1] = native_row('Tarots Bought', 'tarots_bought')
    c3[#c3 + 1] = native_row('Planets Bought', 'planets_bought')
    c3[#c3 + 1] = native_row('Vouchers Bought', 'vouchers_bought')
    c3[#c3 + 1] = native_row('Jokers Sold', 'jokers_sold', G.C.MONEY)
    c3[#c3 + 1] = native_row('Cards Sold', 'cards_sold', G.C.MONEY)

    local c4 = { section_title('Booster Packs') }
    c4[#c4 + 1] = native_row('Standard Packs', 'standard_packs')
    c4[#c4 + 1] = native_row('Arcana Packs', 'tarot_packs')
    c4[#c4 + 1] = native_row('Celestial Packs', 'planet_packs')
    c4[#c4 + 1] = native_row('Spectral Packs', 'spectral_packs')
    c4[#c4 + 1] = native_row('Buffoon Packs', 'buffoon_packs')
    c4[#c4 + 1] = native_row('Other / Earlier', 'other_packs')
    c4[#c4 + 1] = native_row('Packs Opened', 'packs')

    local function col(nodes)
        return { n = G.UIT.C, config = { align = 'tm', padding = 0.06 }, nodes = nodes }
    end
    return { col(c1), col(c2), col(c3), col(c4) }
end

-- ------------------------------------------------------------
-- UI — Dashboard tab (per-ante KPIs + charts)
-- ------------------------------------------------------------

local function pa_list()
    local s = RS.stats()
    local out = {}
    if s and s.per_ante then
        local antes = {}
        for a in pairs(s.per_ante) do antes[#antes + 1] = a end
        table.sort(antes)
        for _, a in ipairs(antes) do
            out[#out + 1] = { ante = a, bucket = s.per_ante[a] }
        end
    end
    return out
end

-- Extract a per-ante value series over the selected range: {antes={...}, values={...}}
local function ante_series(fn)
    local antes, values = {}, {}
    for _, r in ipairs(pa_list()) do
        if RS.in_slice(r.ante) then
            antes[#antes + 1] = tostring(r.ante) .. (RS.ante_in_progress(r.ante) and '*' or '')
            values[#values + 1] = fn(r.bucket, r.ante) or 0
        end
    end
    return { antes = antes, values = values }
end

local function series_of(name, colour, values)
    return { name = name, colour = colour, values = values }
end

local function chart_node(title, data_fn, opts)
    local CW = (opts and opts.w) or 3.7
    local CH = (opts and opts.h) or 1.95
    return { n = G.UIT.C, config = { align = 'cm', padding = 0.05 }, nodes = {
        { n = G.UIT.R, config = { align = 'cm' }, nodes = {
            { n = G.UIT.T, config = { text = title, scale = 0.27, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
        } },
        { n = G.UIT.R, config = { align = 'cm' }, nodes = {
            { n = G.UIT.O, config = { w = CW, h = CH, object = RSChart({
                w = CW, h = CH,
                log = opts and opts.log or false,
                kind = opts and opts.kind or 'grouped',
                data = data_fn,
            }) } },
        } },
    } }
end

local function kpi_row()
    RS.rebuild_kpis()
    local defs = {
        { 'RANGE', 'range', G.C.WHITE },
        { 'MOST $ HELD', 'money', G.C.MONEY },
        { 'HANDS', 'hands', G.C.BLUE },
        { 'BEST HAND', 'best', G.C.RED },
        { 'EARNED', 'earned', G.C.GREEN },
    }
    local cards = {}
    for _, d in ipairs(defs) do
        cards[#cards + 1] = { n = G.UIT.C, config = { align = 'cm', padding = 0.04, minw = 1.55, r = 0.1, colour = darken(G.C.JOKER_GREY, 0.1), emboss = 0.05 }, nodes = {
            { n = G.UIT.R, config = { align = 'cm' }, nodes = {
                { n = G.UIT.T, config = { text = d[1], scale = 0.2, colour = G.C.UI.TEXT_DARK, shadow = true } },
            } },
            { n = G.UIT.R, config = { align = 'cm', minh = 0.34 }, nodes = {
                { n = G.UIT.T, config = { ref_table = RS._kpi, ref_value = d[2], scale = 0.3, colour = d[3], shadow = true } },
            } },
        } }
    end
    return { n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = cards }
end

local function summary_line()
    local txt = 'Skips: ' .. RS.pa_sum('skips') ..
        '   •   Packs: ' .. RS.pa_sum('packs') ..
        '   •   Vouchers: ' .. RS.pa_sum('vouchers') ..
        '   •   Rerolls: ' .. RS.career_sliced('c_shop_rerolls')
    return { n = G.UIT.R, config = { align = 'cm', padding = 0.03 }, nodes = {
        { n = G.UIT.T, config = { text = txt, scale = 0.24, colour = G.C.UI.TEXT_DARK, shadow = true } },
    } }
end

-- Data functions are separate from rendering so filtering is consistent everywhere.
local function blind_history(wins_only)
    local rows = {}
    for _, record in ipairs((RS.stats() or {}).blinds or {}) do
        if RS.in_slice(record.ante) and (not wins_only or record.won) then rows[#rows + 1] = record end
    end
    return rows
end

function RS.score_chart_data()
    local labels, best, targets, totals = {}, {}, {}, {}
    local stats = RS.stats() or {}
    local current = (stats.blinds or {})[stats.current_blind or 0]
    for _, r in ipairs(blind_history()) do
        labels[#labels + 1] = r.label .. (r.partial and '*' or '')
        best[#best + 1] = r.best or 0
        targets[#targets + 1] = r.target or 0
        -- Read the actual accumulated score, including boss adjustments. Older
        -- completed rounds without a saved total remain gaps in this series.
        local total = r == current and not r.completed and G.GAME.chips or r.total_score
        totals[#totals + 1] = total or false
    end
    return { antes = labels, series = {
        series_of('Best hand', G.C.RED, best), series_of('Blind target', G.C.BLUE, targets),
        series_of('Total round score', G.C.GREEN, totals),
    }, empty = 'Play a blind to start score history' }
end

function RS.hands_chart_data()
    local labels, used, unused = {}, {}, {}
    for _, r in ipairs(blind_history(true)) do
        labels[#labels + 1] = r.label
        used[#used + 1] = r.hands_used or 0
        unused[#unused + 1] = r.unused or 0
    end
    return { antes = labels, series = {
        series_of('Used', G.C.BLUE, used), series_of('Unused', G.C.GREEN, unused),
    }, empty = 'Clear a blind to see hands used' }
end

function RS.money_chart_data()
    local earned = ante_series(function(b) return b.earned end)
    local spent = ante_series(function(b) return b.spent end)
    return { antes = earned.antes, series = {
        series_of('Earned', G.C.GREEN, earned.values), series_of('Spent', G.C.RED, spent.values),
    } }
end

function RS.cash_chart_data()
    local labels, cash, caps = {}, {}, {}
    local any_cap = false
    for _, r in ipairs((RS.stats() or {}).shops or {}) do
        if RS.in_slice(r.ante) then
            local i = #labels + 1
            labels[i], cash[i], caps[i] = r.label, r.cash, r.cap
            if type(r.cap) == 'number' then any_cap = true end
        end
    end
    local series = { series_of('Shop entry $', G.C.MONEY, cash) }
    if any_cap then series[#series + 1] = series_of('Interest cap', G.C.WHITE, caps) end
    return { antes = labels, series = series, empty = 'Enter a shop to start cash history' }
end

function RS.poker_chart_data()
    local counts = {}
    for ante, bucket in pairs((RS.stats() or {}).per_ante or {}) do
        if RS.in_slice(ante) then
            for hand, count in pairs(bucket.hand_types or {}) do counts[hand] = (counts[hand] or 0) + count end
        end
    end
    local keys = {}
    for hand in pairs(counts) do keys[#keys + 1] = hand end
    table.sort(keys, function(a, b)
        if counts[a] == counts[b] then return a < b end
        return counts[a] > counts[b]
    end)
    local labels, values = {}, {}
    for _, hand in ipairs(keys) do
        labels[#labels + 1] = localize(hand, 'poker_hands')
        values[#values + 1] = counts[hand]
    end
    return { antes = labels, series = { series_of('Times played', G.C.BLUE, values) }, empty = 'Play a poker hand to start tracking' }
end

function RS.consumables_chart_data()
    local tarot = ante_series(function(b) return (b.cset or {}).Tarot or 0 end)
    local planet = ante_series(function(b) return (b.cset or {}).Planet or 0 end)
    local spectral = ante_series(function(b) return (b.cset or {}).Spectral or 0 end)
    return { antes = tarot.antes, series = {
        series_of('Tarot', G.C.PURPLE, tarot.values), series_of('Planet', G.C.BLUE, planet.values),
        series_of('Spectral', G.C.CHANCE, spectral.values),
    } }
end

function RS.consistency_chart_data()
    local labels, averages, medians = {}, {}, {}
    local any = false
    for _, row in ipairs(pa_list()) do
        if RS.in_slice(row.ante) then
            local scores = score_summary(row.bucket.hand_scores)
            labels[#labels + 1] = tostring(row.ante) .. (RS.ante_in_progress(row.ante) and '*' or '')
            averages[#labels], medians[#labels] = scores.average or false, scores.median or false
            any = any or scores.count > 0
        end
    end
    return { antes = any and labels or {}, series = {
        series_of('Average', G.C.BLUE, averages), series_of('Median', G.C.PURPLE, medians),
    }, empty = 'Play a hand to start score history' }
end

function RS.spending_chart_data()
    local spending, total = RS.spending_summary()
    local labels, values = {}, {}
    for _, category in ipairs(SPEND_CATEGORIES) do
        labels[#labels + 1], values[#values + 1] = category.label, spending[category.key] or 0
    end
    labels[#labels + 1], values[#values + 1] = 'Other / Earlier', spending.other
    return { antes = total > 0 and labels or {}, series = { series_of('Dollars spent', G.C.MONEY, values) },
        empty = 'No spending in this ante range' }
end

local function analysis_grid()
    return { n = G.UIT.R, config = { align = 'cm' }, nodes = {
        chart_node('Score Consistency by Ante (log)', RS.consistency_chart_data,
            { w = 6.4, h = 3.2, kind = 'line', log = true }),
        chart_node('Spending by Category', RS.spending_chart_data,
            { w = 6.4, h = 3.2, kind = 'horizontal' }),
    } }
end

local function analysis_summary()
    local scores = RS.score_summary()
    local function score_text(value) return value and number_format(value) or '--' end
    local _, spending = RS.spending_summary()
    return { n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = {
        { n = G.UIT.T, config = { text = 'Average: ' .. score_text(scores.average)
            .. '   Median: ' .. score_text(scores.median) .. '   Hands tracked: ' .. scores.count
            .. '   Spent: ' .. localize('$') .. number_format(spending),
            scale = 0.27, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
    } }
end

local INCOME_CATEGORIES = {
    {key = 'blinds', label = 'Blinds', colour = {0.12, 0.55, 1, 1}},
    {key = 'hands', label = 'Unused hands', colour = {0.2, 0.78, 0.38, 1}},
    {key = 'interest', label = 'Interest', colour = {1, 0.8, 0.12, 1}},
    {key = 'jokers', label = 'Jokers', colour = {1, 0.42, 0.12, 1}},
    {key = 'cards', label = 'Cards', colour = {0.98, 0.35, 0.65, 1}},
    {key = 'sales', label = 'Sales', colour = {0.65, 0.4, 0.95, 1}},
    {key = 'other', label = 'Other', colour = {0.64, 0.7, 0.75, 1}},
}
local DECK_MODES = { 'Suits', 'Ranks', 'Enhancements', 'Seals', 'Editions' }
local DECK_FIELDS = { 'suits', 'ranks', 'enhancements', 'seals', 'editions' }
RS._deck_mode = 1

local function category_colour(i)
    return ({G.C.BLUE, G.C.GREEN, G.C.MONEY, G.C.PURPLE, G.C.ORANGE})[(i - 1) % 5 + 1]
end

function RS.income_chart_data()
    local labels, series = {}, {}
    for i, category in ipairs(INCOME_CATEGORIES) do
        series[i] = series_of(category.label, category.colour, {})
        series[i].key = category.key
    end
    for _, row in ipairs(pa_list()) do
        if RS.in_slice(row.ante) then
            labels[#labels + 1] = tostring(row.ante) .. (RS.ante_in_progress(row.ante) and '*' or '')
            local income, known = row.bucket.income or {}, 0
            for i = 1, #INCOME_CATEGORIES - 1 do
                local amount = income[INCOME_CATEGORIES[i].key] or 0
                series[i].values[#labels] = amount
                known = known + amount
            end
            series[#INCOME_CATEGORIES].values[#labels] = math.max(0, (row.bucket.earned or 0) - known)
        end
    end
    return {antes = labels, series = series, empty = 'Receive income to start tracking'}
end

local HAND_ORDER = { 'Flush Five', 'Flush House', 'Five of a Kind', 'Straight Flush',
    'Four of a Kind', 'Full House', 'Flush', 'Straight', 'Three of a Kind', 'Two Pair', 'Pair', 'High Card' }

function RS.level_hand_options()
    local seen, options, order = {}, {}, {}
    for index, hand in ipairs(G.handlist or HAND_ORDER) do order[hand] = index end
    for _, row in ipairs(pa_list()) do
        for hand in pairs(row.bucket.hand_levels or {}) do
            if not seen[hand] then seen[hand] = true; options[#options + 1] = hand end
        end
    end
    table.sort(options, function(a, b)
        if (order[a] or 999) == (order[b] or 999) then return a < b end
        return (order[a] or 999) < (order[b] or 999)
    end)
    return options
end

local function hand_group_colour(key)
    if key == 'baseline' or key == 'all' then return {0.78, 0.83, 0.89, 1} end
    local hue = 0
    for i = 1, #key do hue = (hue * 37 + key:byte(i)) % 359 end
    local h, c, m = hue / 60, 0.7, 0.25
    local x = c * (1 - math.abs(h % 2 - 1))
    local rgb = ({ {c,x,0}, {x,c,0}, {0,c,x}, {0,x,c}, {x,0,c}, {c,0,x} })[math.floor(h) + 1]
    return {rgb[1] + m, rgb[2] + m, rgb[3] + m, 1}
end

function RS.hand_levels_chart_data()
    local options, labels, hands = RS.level_hand_options(), {}, {}
    for _, hand in ipairs(options) do hands[hand] = {} end
    local any, all_same = false, true
    for _, row in ipairs(pa_list()) do
        if RS.in_slice(row.ante) then
            labels[#labels + 1] = tostring(row.ante) .. (RS.ante_in_progress(row.ante) and '*' or '')
            local common, present = nil, 0
            for _, hand in ipairs(options) do
                local value = (row.bucket.hand_levels or {})[hand]
                hands[hand][#labels] = value or false
                if value ~= nil then
                    any, present = true, present + 1
                    if common == nil then common = value elseif value ~= common then all_same = false end
                end
            end
            if present > 0 and present < #options then all_same = false end
        end
    end
    local data = {antes = any and labels or {}, series = {}, segments = {}, points = {}, hands = hands,
        empty = 'Hand levels appear after tracking starts'}
    if not any then return data end
    if all_same and #options > 1 then
        local values = hands[options[1]]
        data.series[1] = series_of('All hands', hand_group_colour('all'), values)
        for i, value in ipairs(values) do
            if type(value) == 'number' then
                data.points[#data.points + 1] = {series = 1, i = i, value = value, hands = options}
                if type(values[i + 1]) == 'number' then
                    data.segments[#data.segments + 1] = {series = 1, i = i, j = i + 1, from = value, to = values[i + 1], hands = options}
                end
            end
        end
        return data
    end
    local registry = {}
    local function group_series(group, first, last)
        local key, name
        if #group > 1 and first == 1 and (last == nil or last == 1) then
            key, name = 'baseline', 'Other hands'
        elseif #group > 1 and #group == #options then
            key, name = 'all', 'All hands'
        else
            key = table.concat(group, '\31')
            local names = {}
            for _, hand in ipairs(group) do names[#names + 1] = localize(hand, 'poker_hands') end
            name = table.concat(names, ' + ')
        end
        if not registry[key] then
            local values = {}
            for i = 1, #labels do values[i] = false end
            data.series[#data.series + 1] = series_of(name, hand_group_colour(key), values)
            registry[key] = #data.series
        end
        return registry[key]
    end
    -- Shared points are drawn last, so the combined colour is visible at merges.
    for i = 1, #labels do
        local groups, levels = {}, {}
        for _, hand in ipairs(options) do
            local value = hands[hand][i]
            if type(value) == 'number' then
                if not groups[value] then groups[value] = {}; levels[#levels + 1] = value end
                groups[value][#groups[value] + 1] = hand
            end
        end
        table.sort(levels)
        for _, value in ipairs(levels) do
            local group = groups[value]
            local si = group_series(group, value)
            data.series[si].values[i] = value
            data.points[#data.points + 1] = {series = si, i = i, value = value, hands = group}
        end
    end
    -- Group each interval independently: hands can split and rejoin later.
    for i = 1, #labels - 1 do
        local groups, keys = {}, {}
        for _, hand in ipairs(options) do
            local first, last = hands[hand][i], hands[hand][i + 1]
            if type(first) == 'number' and type(last) == 'number' then
                local key = tostring(first) .. ':' .. tostring(last)
                if not groups[key] then groups[key] = {first = first, last = last, hands = {}}; keys[#keys + 1] = key end
                groups[key].hands[#groups[key].hands + 1] = hand
            end
        end
        table.sort(keys)
        for _, key in ipairs(keys) do
            local group = groups[key]
            local si = group_series(group.hands, group.first, group.last)
            data.series[si].values[i], data.series[si].values[i + 1] = group.first, group.last
            data.segments[#data.segments + 1] = {series = si, i = i, j = i + 1,
                from = group.first, to = group.last, hands = group.hands}
        end
    end
    return data
end

local function deck_label(key, field)
    if field == 'ranks' then return RS.card_rank_label(tonumber(key) or key) end
    if field == 'enhancements' and G.P_CENTERS and G.P_CENTERS[key] then
        local center = G.P_CENTERS[key]
        local ok, label = pcall(localize, {type = 'name_text', key = key, set = center.set})
        if ok and type(label) == 'string' then return label end
        return center.name or key
    end
    return key:gsub('^m_', ''):gsub('^e_', ''):gsub('^%l', string.upper)
end

local function deck_rows()
    local rows = {}
    for _, row in ipairs(pa_list()) do
        if RS.in_slice(row.ante) and row.bucket.deck_snapshot then rows[#rows + 1] = row end
    end
    return rows
end

local function deck_keys(rows, field)
    local totals, keys = {}, {}
    for _, row in ipairs(rows) do
        for key, count in pairs(row.bucket.deck_snapshot[field] or {}) do bump(totals, key, count) end
    end
    for key in pairs(totals) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        if totals[a] == totals[b] then
            if field == 'ranks' and tonumber(a) and tonumber(b) then return tonumber(a) < tonumber(b) end
            return a < b
        end
        return totals[a] > totals[b]
    end)
    return keys
end

function RS.deck_history_chart_data()
    local rows = deck_rows()
    local field = DECK_FIELDS[RS._deck_mode or 1]
    local keys = deck_keys(rows, field)
    local grouped = #keys > 4
    while #keys > 4 do table.remove(keys) end
    local labels, series = {}, {}
    for i, key in ipairs(keys) do
        series[i] = series_of(deck_label(key, field), CARD_SUIT_COLOURS[key] or category_colour(i), {})
    end
    if grouped then series[#series + 1] = series_of('Other types', category_colour(5), {}) end
    for _, row in ipairs(rows) do
        labels[#labels + 1] = tostring(row.ante) .. (RS.ante_in_progress(row.ante) and '*' or '')
        local snapshot, shown = row.bucket.deck_snapshot, 0
        for i, key in ipairs(keys) do
            local count = (snapshot[field] or {})[key] or 0
            series[i].values[#labels] = count
            shown = shown + count
        end
        if grouped then series[#series].values[#labels] = math.max(0, snapshot.total - shown) end
    end
    return {antes = labels, series = series, empty = 'No deck snapshots in this ante range'}
end

function RS.deck_breakdown_chart_data()
    local rows = deck_rows()
    local last = rows[#rows]
    local field = DECK_FIELDS[RS._deck_mode or 1]
    local labels, values, colours = {}, {}, {}
    if last then
        local keys = deck_keys({last}, field)
        if field == 'ranks' then table.sort(keys, function(a, b) return (tonumber(a) or 99) < (tonumber(b) or 99) end) end
        for i, key in ipairs(keys) do
            labels[i], values[i] = deck_label(key, field), last.bucket.deck_snapshot[field][key]
            colours[i] = CARD_SUIT_COLOURS[key] or category_colour(i)
        end
    end
    return {antes = labels, series = {series_of('Cards', G.C.BLUE, values)}, colours = colours,
        ante = last and last.ante, total = last and last.bucket.deck_snapshot.total,
        empty = 'No deck snapshots in this ante range'}
end

local function economy_grid()
    return {n = G.UIT.R, config = {align = 'cm'}, nodes = {
        chart_node('Income Sources by Ante', RS.income_chart_data, {w = 6.4, h = 3.2, kind = 'stacked'}),
        chart_node('Poker-Hand Levels by Ante', RS.hand_levels_chart_data, {w = 6.4, h = 3.2, kind = 'line'}),
    }}
end

local function deck_grid()
    local latest = RS.deck_breakdown_chart_data()
    local title = latest.ante and ('Latest Breakdown: Ante ' .. latest.ante .. ' (' .. latest.total .. ' cards)') or 'Deck Breakdown'
    return {n = G.UIT.R, config = {align = 'cm'}, nodes = {
        chart_node('Deck Composition by Ante', RS.deck_history_chart_data, {w = 6.4, h = 3.2, kind = 'stacked'}),
        chart_node(title, RS.deck_breakdown_chart_data, {w = 6.4, h = 3.2, kind = 'horizontal'}),
    }}
end

local function chart_grid()
    local function panel(title, data, kind, log)
        return chart_node(title, data, {w = 4.25, h = 2.1, kind = kind, log = log})
    end
    return {
        { n = G.UIT.R, config = { align = 'cm' }, nodes = {
            panel('Score vs Blind Target (log)', RS.score_chart_data, 'line', true),
            panel('Hands Needed to Win', RS.hands_chart_data, 'stacked'),
            panel('Money Earned / Spent by Ante', RS.money_chart_data, 'grouped'),
        } },
        { n = G.UIT.R, config = { align = 'cm' }, nodes = {
            panel('Cash Reserve by Shop', RS.cash_chart_data, 'line'),
            panel('Poker Hands Played', RS.poker_chart_data, 'horizontal'),
            panel('Consumables Used by Ante', RS.consumables_chart_data, 'grouped'),
        } },
    }
end

-- ------------------------------------------------------------
-- UI — Probabilities tab (hit rates for every chance card)
-- ------------------------------------------------------------

-- ------------------------------------------------------------
-- UI — Probabilities tab (hit rates for every chance card)
-- ------------------------------------------------------------

-- Live view-model for the Probabilities tab.
RS._probview = {}

-- Known chance seeds: display name, success case, and base odds (from the
-- game's center configs / call sites; live num/den override once rolls exist).
local PROB_META = {
    glass            = { name = 'Glass Card',       case = 'Breaks',    den = 4 },
    space            = { name = 'Space Joker',      case = 'Level up',  den = 4 },
    bloodstone       = { name = 'Bloodstone',       case = 'XMult',     den = 2 },
    ['8ball']        = { name = '8 Ball',           case = 'Tarot',     den = 4 },
    lucky_mult       = { name = 'Lucky Card',       case = '+Mult',     den = 5 },
    lucky_money      = { name = 'Lucky Card',       case = '+$20',      den = 15 },
    business         = { name = 'Business Card',    case = '+$2',       den = 2 },
    wheel_of_fortune = { name = 'Wheel of Fortune', case = 'Edition',   den = 4 },
    gros_michel      = { name = 'Gros Michel',      case = 'Destroyed', den = 6 },
    cavendish        = { name = 'Cavendish',        case = 'Destroyed', den = 1000 },
    parking          = { name = 'Reserved Parking', case = '+$1',       den = 2 },
    halu             = { name = 'Hallucination',    case = '+1 Tarot',  den = 2 },
}

local PROB_CENTERS = {
    glass = 'm_glass', space = 'j_space', bloodstone = 'j_bloodstone', ['8ball'] = 'j_8_ball',
    lucky_mult = 'm_lucky', lucky_money = 'm_lucky', business = 'j_business',
    wheel_of_fortune = 'c_wheel_of_fortune', gros_michel = 'j_gros_michel',
    cavendish = 'j_cavendish', parking = 'j_reserved_parking', halu = 'j_hallucination',
}

local function probability_card(center_key)
    if not center_key then return nil end
    for _, cards in ipairs({ (G.jokers or {}).cards or {}, G.playing_cards or {}, (G.consumeables or {}).cards or {} }) do
        for _, card in ipairs(cards) do
            local config = card.config or {}
            if (config.center_key or (config.center or {}).key) == center_key then return card end
        end
    end
end

local function vanilla_probability(seed)
    local canonical = type(seed) == 'string' and seed:sub(1, 4) == 'halu' and 'halu' or seed
    local meta = PROB_META[canonical]
    if not meta then return nil end
    local card = probability_card(PROB_CENTERS[canonical])
    local denominator = meta.den
    if card and canonical ~= 'lucky_mult' and canonical ~= 'lucky_money' then
        local extra = card.ability and card.ability.extra
        if type(extra) == 'number' then denominator = extra
        elseif type(extra) == 'table' and type(extra.odds) == 'number' then denominator = extra.odds end
    end
    return card, denominator
end

function RS.record_vanilla_roll(seed, sample)
    if not RS.stats() or type(seed) ~= 'string' or type(sample) ~= 'number' then return end
    local card, denominator = vanilla_probability(seed)
    if not denominator then return end
    local numerator = (G.GAME.probabilities or {}).normal or 1
    RS.record_probability(card, seed, 1, denominator, sample < numerator / denominator)
end

-- Use the same live probability calculation as card tooltips. Recorded num/den
-- are base inputs, so applying modifiers here does not double-count Oops.
function RS.current_probability(seed)
    local stats = RS.stats()
    local entry = stats and (stats.probs or {})[seed]
    if not entry and seed == 'halu' then
        for key, value in pairs((stats or {}).probs or {}) do
            if type(key) == 'string' and key:sub(1, 4) == 'halu' then entry = value; break end
        end
    end
    local meta = PROB_META[seed]
    local numerator = entry and entry.num or 1
    local denominator = (entry and entry.den) or (meta and meta.den)
    if not denominator then return nil, nil end
    local center_key = (entry and entry.card_key) or PROB_CENTERS[seed]
    local trigger = probability_card(center_key)
    local no_mod = entry and entry.no_mod or false
    if SMODS and SMODS.get_probability_vars then
        return SMODS.get_probability_vars(trigger, numerator, denominator, (entry and entry.identifier) or seed, nil, no_mod)
    end
    if meta then
        local _, live_denominator = vanilla_probability(seed)
        denominator = live_denominator or denominator
    end
    return numerator * (no_mod and 1 or ((G.GAME.probabilities or {}).normal or 1)), denominator
end

function RS.prob_seed_name(seed)
    if PROB_META[seed] then return PROB_META[seed].name end
    if type(seed) == 'string' and seed:sub(1, 4) == 'halu' then return 'Hallucination' end
    return seed
end

-- Ordered registry; 'halu' aggregates the per-ante hallucination seeds.
local PROB_REGISTRY = {
    'glass', 'space', 'bloodstone', '8ball', 'lucky_mult', 'lucky_money',
    'business', 'wheel_of_fortune', 'gros_michel', 'cavendish',
    'parking', 'halu',
}

-- Seeds actually present in the data, with 'halu<N>' variants merged into 'halu'.
function RS.prob_seed_list()
    local list = {}
    for _, seed in ipairs(PROB_REGISTRY) do list[#list + 1] = seed end
    local s = RS.stats()
    if s and s.probs then
        local known = {}
        for _, seed in ipairs(PROB_REGISTRY) do known[seed] = true end
        local extras = {}
        for seed, e in pairs(s.probs) do
            local canonical = (type(seed) == 'string' and seed:sub(1, 4) == 'halu') and 'halu' or seed
            if not known[canonical] then
                extras[canonical] = (extras[canonical] or 0) + (e.rolls or 0)
            end
        end
        local sorted = {}
        for seed, rolls in pairs(extras) do sorted[#sorted + 1] = { seed = seed, rolls = rolls } end
        table.sort(sorted, function(a, b) return a.rolls > b.rolls end)
        for i, ex in ipairs(sorted) do
            if i > 6 then break end
            list[#list + 1] = ex.seed
        end
    end
    return list
end

-- Sliced roll/hit counts for one probability seed ('halu' aggregates variants).
function RS.prob_sliced(seed)
    local s = RS.stats()
    local rolls, hits, num, den = 0, 0, nil, nil
    if not s then return rolls, hits, num, den end
    local function add(entry)
        if entry then
            rolls, hits = rolls + (entry.rolls or 0), hits + (entry.hits or 0)
            if entry.den then num, den = entry.num or 1, entry.den end
        end
    end
    local function is_seed(k)
        return (seed == 'halu')
            and (type(k) == 'string' and k:sub(1, 4) == 'halu')
            or (k == seed)
    end
    if RS.slice_is_full() then
        for k, e in pairs(s.probs or {}) do
            if is_seed(k) then add(e) end
        end
    else
        for a, bucket in pairs(s.per_ante or {}) do
            if RS.in_slice(a) then
                for k, e in pairs(bucket.probs or {}) do
                    if is_seed(k) then add(e) end
                end
            end
        end
    end
    return rolls, hits, num, den
end

-- Row: name | listed odds | success case | measured rate
local function prob_row(seed)
    local key = 'p_' .. seed
    return { n = G.UIT.R, config = { align = 'cm', padding = 0.025, r = 0.1, colour = darken(G.C.JOKER_GREY, 0.1), emboss = 0.05 }, nodes = {
        { n = G.UIT.C, config = { align = 'cl', padding = 0.04, minw = 1.6, maxw = 1.6 }, nodes = {
            { n = G.UIT.T, config = { ref_table = RS._probview, ref_value = key .. '_name',
                scale = 0.25, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
        } },
        { n = G.UIT.C, config = { align = 'cm', minw = 1.2, maxw = 1.2 }, nodes = {
            { n = G.UIT.T, config = { ref_table = RS._probview, ref_value = key .. '_odds',
                scale = 0.25, colour = G.C.BLUE, shadow = true } },
        } },
        { n = G.UIT.C, config = { align = 'cl', padding = 0.04, minw = 1.15, maxw = 1.15 }, nodes = {
            { n = G.UIT.T, config = { ref_table = RS._probview, ref_value = key .. '_case',
                scale = 0.25, colour = G.C.UI.TEXT_DARK, shadow = true } },
        } },
        { n = G.UIT.C, config = { align = 'cr', padding = 0.04, minw = 1.85, maxw = 1.85 }, nodes = {
            { n = G.UIT.T, config = { ref_table = RS._probview, ref_value = key,
                scale = 0.25, colour = G.C.YELLOW, shadow = true } },
        } },
    } }
end

local function probabilities_columns()
    RS.rebuild_probview()
    local seeds = RS.prob_seed_list()
    local half = math.ceil(#seeds / 2)
    local c1, c2 = {}, {}
    for i, seed in ipairs(seeds) do
        local target = (i <= half) and c1 or c2
        target[#target + 1] = prob_row(seed)
    end
    local function col(nodes)
        local t = {}
        for _, r in ipairs(nodes) do t[#t + 1] = r end
        return { n = G.UIT.C, config = { align = 'tm', padding = 0.06 }, nodes = t }
    end
    return {
        { n = G.UIT.R, config = { align = 'ct' }, nodes = { col(c1), col(c2) } },
    }
end

function RS.rebuild_probview()
    for _, seed in ipairs(RS.prob_seed_list()) do
        local key = 'p_' .. seed
        local rolls, hits = RS.prob_sliced(seed)
        local meta = PROB_META[seed]
        local eff_num, eff_den = RS.current_probability(seed)
        RS._probview[key .. '_name'] = RS.prob_seed_name(seed)
        RS._probview[key .. '_odds'] = eff_den and (tostring(eff_num) .. ' in ' .. tostring(eff_den)) or '--'
        RS._probview[key .. '_case'] = meta and meta.case or '--'
        RS._probview[key] = hits .. '/' .. rolls .. ' (' .. fmt_pct(hits, rolls) .. ')'
    end
end

-- ------------------------------------------------------------
-- Menu assembly (tabs: Summary | Trends | Probabilities | Cards)
-- ------------------------------------------------------------

RS._tab = 'stats'
RS._trend_view = 'overview'
local TREND_VIEWS = { 'overview', 'analysis', 'economy', 'deck' }
local TREND_LABELS = { overview = 'Overview', analysis = 'Analysis', economy = 'Economy', deck = 'Deck' }

G.FUNCS.runstats_trend_view = function()
    local index = 1
    for i, view in ipairs(TREND_VIEWS) do if RS._trend_view == view then index = i; break end end
    RS._trend_view = TREND_VIEWS[index % #TREND_VIEWS + 1]
    RS.show_menu()
end

G.FUNCS.runstats_deck_mode = function()
    RS._deck_mode = (RS._deck_mode or 1) % #DECK_MODES + 1
    RS.show_menu()
end

-- End-of-run screens keep their normal actions; stats returns to the same screen.
safe_wrap(_G, 'create_UIBox_generic_options', function(ref)
    return function(args, ...)
        if RS._building_result and RS.stats() and args and args.contents then
            args.contents[#args.contents + 1] = UIBox_button{
                label = { 'Run Stats' }, button = 'runstats_open_' .. RS._building_result,
                minw = 5, minh = 0.5, scale = 0.4, colour = G.C.BLUE,
            }
        end
        return ref(args, ...)
    end
end)

for _, screen in ipairs({ 'win', 'game_over' }) do
    safe_wrap(_G, 'create_UIBox_' .. screen, function(ref)
        return function(...)
            local previous = RS._building_result
            RS._building_result = screen
            local definition = ref(...)
            RS._building_result = previous
            return definition
        end
    end)
    G.FUNCS['runstats_open_' .. screen] = function()
        if not RS.stats() then return end
        RS._return_screen, RS._tab, RS._ante_sel = screen, 'stats', 0
        RS.show_menu()
    end
end

function RS.show_menu()
    RS.capture_snapshot()
    if G.STATE == G.STATES.SHOP and G.shop then RS.capture_shop_stock() end
    G.FUNCS.overlay_menu{
        definition = create_UIBox_runstats(), config = { no_esc = RS._return_screen ~= nil },
    }
end

local function trend_controls()
    local nodes = { UIBox_button{
        label = { 'View: ' .. (TREND_LABELS[RS._trend_view] or 'Overview') },
        button = 'runstats_trend_view', minw = 3, minh = 0.4, scale = 0.3, colour = G.C.BLUE, col = true,
    } }
    if RS._trend_view == 'deck' then
        nodes[#nodes + 1] = UIBox_button{label = { 'Group: ' .. DECK_MODES[RS._deck_mode or 1] },
            button = 'runstats_deck_mode', minw = 3.4, minh = 0.4, scale = 0.3, colour = G.C.GREEN, col = true}
    end
    return {n = G.UIT.R, config = {align = 'cm', padding = 0.04}, nodes = nodes}
end

G.FUNCS.runstats_return_to_result = function()
    local screen = RS._return_screen
    if not screen then return end
    RS._return_screen = nil
    G.FUNCS.overlay_menu{ definition = _G['create_UIBox_' .. screen](), config = { no_esc = true } }
end

-- Cards-tab slicers: click to cycle; overlay rebuilds and shows the new value.
G.FUNCS.runstats_cards_suit = function(e)
    RS._card_suit = (RS._card_suit or 1) % #CARD_SUIT_OPTS + 1
    RS.show_menu()
end

G.FUNCS.runstats_cards_rank = function(e)
    RS._card_rank = (RS._card_rank or 1) % #CARD_RANK_OPTS + 1
    RS.show_menu()
end

G.FUNCS.runstats_cards_mode = function(e)
    RS._card_mode = (RS._card_mode or 1) % #CARD_MODE_OPTS + 1
    RS.show_menu()
end

G.FUNCS.runstats_cards_reset = function(e)
    RS._card_suit = 1
    RS._card_rank = 1
    RS._card_mode = 1
    RS._show_scoring_triggers, RS._show_held_triggers = true, true
    RS.show_menu()
end

G.FUNCS.runstats_cards_scoring_triggers = function()
    RS._show_scoring_triggers = not RS._show_scoring_triggers
    RS.show_menu()
end
G.FUNCS.runstats_cards_held_triggers = function()
    RS._show_held_triggers = not RS._show_held_triggers
    RS.show_menu()
end

local function cards_slicer_row()
    return { n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = {
        UIBox_button{ label = { 'Mode: ' .. CARD_MODE_OPTS[RS._card_mode or 1] },
            button = 'runstats_cards_mode', col = true, minw = 2.2, minh = 0.46, scale = 0.3, colour = G.C.RED },
        UIBox_button{ label = { 'Suit: ' .. CARD_SUIT_OPTS[RS._card_suit or 1] },
            button = 'runstats_cards_suit', col = true, minw = 2.2, minh = 0.46, scale = 0.3, colour = G.C.BLUE },
        UIBox_button{ label = { 'Rank: ' .. CARD_RANK_OPTS[RS._card_rank or 1] },
            button = 'runstats_cards_rank', col = true, minw = 2.2, minh = 0.46, scale = 0.3, colour = G.C.PURPLE },
        UIBox_button{ label = { 'All cards' },
            button = 'runstats_cards_reset', col = true, minw = 1.8, minh = 0.46, scale = 0.3, colour = G.C.GREEN },
        { n = G.UIT.T, config = { text = 'Deck additions merge into their base card (52 entries)',
            scale = 0.2, colour = G.C.UI.TEXT_DARK, shadow = true } },
    } }
end

local function cards_tab()
    local contents = {cards_slicer_row()}
    if CARD_MODE_OPTS[RS._card_mode or 1] == 'Triggers' then
        contents[#contents + 1] = {n = G.UIT.R, config = {align = 'cm', padding = 0.04}, nodes = {
            UIBox_button{label = {'Scoring Triggers: ' .. (RS._show_scoring_triggers and 'On' or 'Off')},
                button = 'runstats_cards_scoring_triggers', col = true, minw = 3.7, minh = 0.4, scale = 0.28,
                colour = RS._show_scoring_triggers and G.C.BLUE or G.C.UI.BACKGROUND_INACTIVE},
            UIBox_button{label = {'Held In Hand: ' .. (RS._show_held_triggers and 'On' or 'Off')},
                button = 'runstats_cards_held_triggers', col = true, minw = 3.7, minh = 0.4, scale = 0.28,
                colour = RS._show_held_triggers and G.C.BLUE or G.C.UI.BACKGROUND_INACTIVE},
        }}
    end
    contents[#contents + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
            { n = G.UIT.O, config = { w = 13.4, h = 4.6, object = RSCardChart({
                w = 13.4, h = 4.6,
                data = RS.card_chart_data,
            }) } },
        } }
    local data = RS.card_chart_data()
    if data.rate then
        contents[#contents + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = {
            { n = G.UIT.T, config = { text = data.played_total .. ' / ' .. data.drawn_total
                .. ' tracked draws played (' .. fmt_pct(data.played_total, data.drawn_total)
                .. '). Each draw counts once; blank bars have no tracked draws.',
                scale = 0.23, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
        } }
    end
    return contents
end

RS._shop_view, RS._shop_page, RS._shop_category = 'history', 1, 'Joker'
local SHOP_CATEGORIES = {Joker = 'Jokers', Planet = 'Planets', Tarot = 'Tarots', Playing = 'Playing Cards', Spectral = 'Spectral Cards'}

function RS.shop_categories()
    local categories = {'Joker', 'Planet', 'Tarot'}
    local game = G.GAME or {}
    local vouchers = game.used_vouchers or {}
    local playing = vouchers.v_magic_trick or vouchers.v_illusion
    local back = game.selected_back or {}
    local spectral = game.selected_back_key == 'b_ghost' or back.name == 'Ghost Deck'
        or (((back.effect or {}).center or {}).key == 'b_ghost')
    -- Preserve access to offers seen through modded shop rules, too.
    for _, group in ipairs((RS.stats() or {}).shop_stock or {}) do
        for _, offer in ipairs(group.cards) do
            if offer.category == 'Playing' then playing = true end
            if offer.category == 'Spectral' then spectral = true end
        end
    end
    if playing then categories[#categories + 1] = 'Playing' end
    if spectral then categories[#categories + 1] = 'Spectral' end
    return categories
end

function RS.shop_history_pages()
    local stock = (RS.stats() or {}).shop_stock or {}
    local pages, page, count = {}, {}, 0
    local function flush()
        if #page > 0 then pages[#pages + 1] = page; page, count = {}, 0 end
    end
    for index = #stock, 1, -1 do
        local group = stock[index]
        if RS.in_slice(group.ante) then
            local size = #group.cards
            for first = 1, size, 12 do
                local last = math.min(size, first + 11)
                local n = last - first + 1
                if count + n > 12 then flush() end
                page[#page + 1] = {group = group, first = first, last = last}
                count = count + n
            end
        end
    end
    flush()
    return pages
end

function RS.shop_frequency(category)
    local counts, rows = {}, {}
    for _, group in ipairs((RS.stats() or {}).shop_stock or {}) do
        if RS.in_slice(group.ante) then
            for _, offer in ipairs(group.cards) do
                if offer.category == category then
                    local row = counts[offer.key]
                    if not row then row = {key = offer.key, name = offer.name, count = 0}; counts[offer.key] = row end
                    row.count = row.count + 1
                end
            end
        end
    end
    for _, row in pairs(counts) do rows[#rows + 1] = row end
    table.sort(rows, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        if a.name ~= b.name then return a.name < b.name end
        return a.key < b.key
    end)
    while #rows > 5 do table.remove(rows) end
    return rows
end

function RS.voucher_history_pages()
    local history, antes, pages, page = (RS.stats() or {}).shop_vouchers or {}, {}, {}, {}
    for ante in pairs(history) do if RS.in_slice(ante) then antes[#antes + 1] = ante end end
    table.sort(antes, function(a, b) return a > b end)
    for _, ante in ipairs(antes) do
        for _, voucher in ipairs(history[ante]) do
            if #page == 8 then pages[#pages + 1] = page; page = {} end
            page[#page + 1] = {ante = ante, voucher = voucher}
        end
    end
    if #page > 0 then pages[#pages + 1] = page end
    return pages
end

function RS.shop_edition_label(edition)
    if edition == nil then return 'Not recorded' end -- older saved offers
    if edition == 'base' then return 'Base' end
    local key = 'e_' .. edition
    if G.localization and ((G.localization.descriptions or {}).Edition or {})[key] then
        return localize{type = 'name_text', set = 'Edition', key = key}
    end
    local labels = {foil = 'Foil', holo = 'Holographic', polychrome = 'Polychrome', negative = 'Negative'}
    return labels[edition] or (edition:gsub('_', ' '):gsub('^%l', string.upper))
end

G.FUNCS.runstats_shop_view = function()
    RS._shop_view = ({history = 'frequency', frequency = 'vouchers', vouchers = 'history'})[RS._shop_view] or 'history'
    RS.show_menu()
end
G.FUNCS.runstats_shop_category = function()
    local categories, index = RS.shop_categories(), 0
    for i, category in ipairs(categories) do if category == RS._shop_category then index = i; break end end
    RS._shop_category = categories[index % #categories + 1]
    RS.show_menu()
end
G.FUNCS.runstats_shop_older = function()
    if RS._shop_view == 'vouchers' then
        RS._voucher_page = math.min((RS._voucher_page or 1) + 1, math.max(1, #RS.voucher_history_pages()))
    else
        RS._shop_page = math.min((RS._shop_page or 1) + 1, math.max(1, #RS.shop_history_pages()))
    end
    RS.show_menu()
end
G.FUNCS.runstats_shop_newer = function()
    if RS._shop_view == 'vouchers' then RS._voucher_page = math.max(1, (RS._voucher_page or 1) - 1)
    else RS._shop_page = math.max(1, (RS._shop_page or 1) - 1) end
    RS.show_menu()
end

local function shop_text(text, colour, scale, padding, align)
    return {n = G.UIT.R, config = {align = align or 'cl', padding = padding or 0.04}, nodes = {
        {n = G.UIT.T, config = {text = text, scale = scale or 0.27, colour = colour or G.C.UI.TEXT_LIGHT, shadow = true}},
    }}
end

local function shop_tab()
    local controls = {UIBox_button{label = {'View: ' .. (({history = 'History', frequency = 'Top 5 Seen', vouchers = 'Vouchers'})[RS._shop_view] or 'History')},
        button = 'runstats_shop_view', col = true, minw = 3, minh = 0.4, scale = 0.3, colour = G.C.BLUE}}
    local contents = {{n = G.UIT.R, config = {align = 'cm', padding = 0.04}, nodes = controls}}
    if RS._shop_view == 'frequency' then
        local categories, valid = RS.shop_categories(), false
        for _, category in ipairs(categories) do if category == RS._shop_category then valid = true end end
        if not valid then RS._shop_category = categories[1] end
        controls[#controls + 1] = UIBox_button{label = {'Type: ' .. SHOP_CATEGORIES[RS._shop_category]},
            button = 'runstats_shop_category', col = true, minw = 3.5, minh = 0.4, scale = 0.3, colour = G.C.GREEN}
        local rows = RS.shop_frequency(RS._shop_category)
        local nodes = {section_title('Most Seen ' .. SHOP_CATEGORIES[RS._shop_category])}
        for rank, row in ipairs(rows) do
            nodes[#nodes + 1] = shop_text(rank .. '. ' .. row.name .. '   -   ' .. row.count .. ' seen', G.C.WHITE, 0.31)
        end
        if #rows == 0 then nodes[#nodes + 1] = shop_text('No offers recorded for this type yet.') end
        contents[#contents + 1] = {n = G.UIT.R, config = {align = 'cm', padding = 0.12, minh = 4.4, minw = 12.8,
            colour = G.C.BLACK, r = 0.1}, nodes = {{n = G.UIT.C, config = {align = 'tm'}, nodes = nodes}}}
    elseif RS._shop_view == 'vouchers' then
        local pages = RS.voucher_history_pages()
        RS._voucher_page = math.max(1, math.min(RS._voucher_page or 1, math.max(1, #pages)))
        for _, spec in ipairs({{'Newer', 'runstats_shop_newer', RS._voucher_page > 1},
            {'Older', 'runstats_shop_older', RS._voucher_page < #pages}}) do
            controls[#controls + 1] = UIBox_button{label = {spec[1]}, button = spec[3] and spec[2] or 'nil', col = true,
                minw = 1.6, minh = 0.4, scale = 0.3, colour = spec[3] and G.C.GREEN or G.C.UI.BACKGROUND_INACTIVE}
        end
        controls[#controls + 1] = {n = G.UIT.T, config = {text = 'Page ' .. RS._voucher_page .. ' / ' .. math.max(1, #pages),
            scale = 0.26, colour = G.C.UI.TEXT_LIGHT}}
        local previous, nodes
        for _, entry in ipairs(pages[RS._voucher_page] or {}) do
            if previous ~= entry.ante then
                previous, nodes = entry.ante, {shop_text('Ante ' .. entry.ante, G.C.FILTER, 0.23, 0.01, 'cm')}
                contents[#contents + 1] = {n = G.UIT.R, config = {align = 'cm', padding = 0.015}, nodes = {
                    {n = G.UIT.C, config = {align = 'cm', minw = 9, padding = 0.01, colour = G.C.BLACK, r = 0.1}, nodes = nodes},
                }}
            end
            local row = entry.voucher
            nodes[#nodes + 1] = shop_text(row.name .. '   $' .. number_format(row.paid or row.cost)
                .. '   |   ' .. (row.bought and 'Bought' or 'Not bought'), row.bought and G.C.GREEN or G.C.WHITE, 0.25, 0.01, 'cm')
        end
        if not previous then contents[#contents + 1] = shop_text('Visit a shop to start recording voucher offers.') end
    else
        local pages = RS.shop_history_pages()
        RS._shop_page = math.max(1, math.min(RS._shop_page or 1, math.max(1, #pages)))
        for _, spec in ipairs({{'Newer', 'runstats_shop_newer', RS._shop_page > 1},
            {'Older', 'runstats_shop_older', RS._shop_page < #pages}}) do
            controls[#controls + 1] = UIBox_button{label = {spec[1]}, button = spec[3] and spec[2] or 'nil', col = true,
                minw = 1.6, minh = 0.4, scale = 0.3, colour = spec[3] and G.C.GREEN or G.C.UI.BACKGROUND_INACTIVE}
        end
        controls[#controls + 1] = {n = G.UIT.T, config = {text = 'Page ' .. RS._shop_page .. ' / ' .. math.max(1, #pages),
            scale = 0.26, colour = G.C.UI.TEXT_LIGHT}}
        local panes = pages[RS._shop_page] or {}
        for _, pane in ipairs(panes) do
            local nodes, group = {}, pane.group
            for j = pane.first, pane.last do
                local offer = group.cards[j]
                local label = offer.name .. '  [' .. RS.shop_edition_label(offer.edition) .. ']   $' .. number_format(offer.cost)
                nodes[#nodes + 1] = shop_text(label, G.C.WHITE, math.min(0.25, 15 / math.max(1, #label)), 0.01, 'cm')
            end
            contents[#contents + 1] = {n = G.UIT.R, config = {align = 'cm', padding = 0.015}, nodes = {
                {n = G.UIT.C, config = {align = 'cm', padding = 0.01, minw = 9, colour = G.C.BLACK, r = 0.1}, nodes = nodes},
            }}
        end
        if #panes == 0 then contents[#contents + 1] = shop_text('Visit a shop to start recording offers.') end
    end
    return contents
end

local function tab_button(label, tab_id, tab_key)
    local active = (RS._tab == tab_key)
    return UIBox_button{
        label = { label },
        button = tab_id,
        minw = 2.2,
        minh = 0.5,
        scale = 0.38,
        col = true,
        colour = active and G.C.BLUE or G.C.UI.BACKGROUND_INACTIVE,
        shadow = true,
    }
end

local function tabs_row()
    return { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
        tab_button('Summary', 'runstats_tab_stats', 'stats'),
        tab_button('Trends', 'runstats_tab_dash', 'dashboard'),
        tab_button('Prob', 'runstats_tab_prob', 'probabilities'),
        tab_button('Cards', 'runstats_tab_cards', 'cards'),
        tab_button('Shop', 'runstats_tab_shop', 'shop'),
    } }
end

-- Ante selector: one field ('All' or a single ante) stepped by up/down.
G.FUNCS.runstats_ante_up = function(e)
    RS.normalize_ante_selection()
    for _, ante in ipairs(RS.played_antes()) do
        if ante > RS._ante_sel then RS._ante_sel = ante; break end
    end
    RS.rebuild_kpis()
    RS.rebuild_sliceview()
    RS.show_menu()
end

G.FUNCS.runstats_ante_down = function(e)
    RS.normalize_ante_selection()
    local previous = 0
    for _, ante in ipairs(RS.played_antes()) do
        if ante >= RS._ante_sel then break end
        previous = ante
    end
    RS._ante_sel = previous
    RS.rebuild_kpis()
    RS.rebuild_sliceview()
    RS.show_menu()
end

local function ante_row()
    local down_enabled = (RS._ante_sel or 0) > 0
    local up_enabled = (RS._ante_sel or 0) < RS.max_ante()
    return { n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = {
        { n = G.UIT.T, config = { text = 'Ante:', scale = 0.3, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
        UIBox_button{ label = { '<' }, button = down_enabled and 'runstats_ante_down' or 'nil', col = true,
            minw = 0.7, minh = 0.46, scale = 0.34,
            colour = down_enabled and G.C.RED or G.C.UI.BACKGROUND_INACTIVE },
        UIBox_button{ label = { RS.ante_sel_label() }, button = 'runstats_ante_reset', col = true,
            minw = 1.4, minh = 0.46, scale = 0.34, colour = G.C.BLUE },
        UIBox_button{ label = { '>' }, button = up_enabled and 'runstats_ante_up' or 'nil', col = true,
            minw = 0.7, minh = 0.46, scale = 0.34,
            colour = up_enabled and G.C.GREEN or G.C.UI.BACKGROUND_INACTIVE },
        { n = G.UIT.T, config = { text = RS.ante_in_progress(current_ante())
                and ('Ante ' .. current_ante() .. ': In progress (*). Click value for All.')
                or 'Click the value to reset to All',
            scale = 0.2, colour = G.C.UI.TEXT_DARK, shadow = true } },
    } }
end

G.FUNCS.runstats_ante_reset = function(e)
    RS._ante_sel = 0
    RS.rebuild_kpis()
    RS.rebuild_sliceview()
    RS.show_menu()
end

function create_UIBox_runstats()
    RS.normalize_ante_selection()
    local contents = { tabs_row(), ante_row() }

    if RS._tab == 'dashboard' then
        contents[#contents + 1] = trend_controls()
        contents[#contents + 1] = kpi_row()
        if RS._trend_view == 'analysis' then
            contents[#contents + 1] = analysis_summary()
            contents[#contents + 1] = analysis_grid()
            contents[#contents + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = {
                { n = G.UIT.T, config = { text = 'Score metrics use tracked hands. Other / Earlier includes unclassified money losses.',
                    scale = 0.23, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
            } }
        elseif RS._trend_view == 'economy' then
            local income, earned = RS.income_summary()
            contents[#contents + 1] = economy_grid()
            contents[#contents + 1] = {n = G.UIT.R, config = {align = 'cm', padding = 0.04}, nodes = {
                {n = G.UIT.T, config = {text = 'Earned: ' .. localize('$') .. number_format(earned)
                    .. '   Interest: ' .. localize('$') .. number_format(income.interest or 0)
                    .. '   Sales: ' .. localize('$') .. number_format(income.sales or 0),
                    scale = 0.27, colour = G.C.UI.TEXT_LIGHT, shadow = true}},
            }}
            contents[#contents + 1] = {n = G.UIT.R, config = {align = 'cm', padding = 0.04}, nodes = {
                {n = G.UIT.T, config = {text = 'Other includes unclassified/earlier income. Levels show latest per-ante snapshots; missing history is blank.',
                    scale = 0.21, colour = G.C.UI.TEXT_LIGHT, shadow = true}},
            }}
        elseif RS._trend_view == 'deck' then
            contents[#contents + 1] = deck_grid()
            contents[#contents + 1] = {n = G.UIT.R, config = {align = 'cm', padding = 0.04}, nodes = {
                {n = G.UIT.T, config = {text = 'Latest snapshot per ante. Suits/ranks use base identities. History groups rarer categories under Other types.',
                    scale = 0.21, colour = G.C.UI.TEXT_LIGHT, shadow = true}},
            }}
        else
            local charts = chart_grid()
            contents[#contents + 1] = summary_line()
            contents[#contents + 1] = charts[1]
            contents[#contents + 1] = charts[2]
        end
        contents[#contents + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.02 }, nodes = {
            { n = G.UIT.T, config = { text = RS._trend_view == 'overview'
                    and 'Blind labels: ante + S / B / BOSS. * In progress / partial history. New history starts when tracked.'
                    or '* In progress. New history starts when tracked.',
                scale = 0.19, colour = G.C.UI.TEXT_DARK, shadow = true } },
        } }
    elseif RS._tab == 'probabilities' then
        for _, row in ipairs(probabilities_columns()) do
            contents[#contents + 1] = row
        end
    elseif RS._tab == 'cards' then
        for _, row in ipairs(cards_tab()) do
            contents[#contents + 1] = row
        end
    elseif RS._tab == 'shop' then
        for _, row in ipairs(shop_tab()) do contents[#contents + 1] = row end
    else
        local cols = stats_tab_columns()
        contents[#contents + 1] = { n = G.UIT.R, config = { align = 'ct' }, nodes = cols }
        for _, row in ipairs(joker_target_columns()) do contents[#contents + 1] = row end
    end

    return create_UIBox_generic_options({
        full_width = true, contents = contents,
        back_func = RS._return_screen and 'runstats_return_to_result' or 'exit_overlay_menu',
    })
end

G.FUNCS.runstats_open = function(e)
    if not RS.stats() then return end
    RS._return_screen = nil
    RS._tab = 'stats'
    RS.show_menu()
end

G.FUNCS.runstats_tab_stats = function(e)
    RS._tab = 'stats'
    RS.show_menu()
end

G.FUNCS.runstats_tab_dash = function(e)
    RS._tab = 'dashboard'
    RS.show_menu()
end

G.FUNCS.runstats_tab_prob = function(e)
    RS._tab = 'probabilities'
    RS.show_menu()
end

G.FUNCS.runstats_tab_cards = function(e)
    RS._tab = 'cards'
    RS.show_menu()
end

G.FUNCS.runstats_tab_shop = function()
    RS._tab = 'shop'
    RS._shop_page = 1
    RS._voucher_page = 1
    RS.show_menu()
end

return RS
