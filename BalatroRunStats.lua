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
    hand_types = {},
    hand_scores = {},
    spending = {},
    usage_drawn = {},
    usage_played = {},
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
        local result = ref(self, blind, reset, ...)
        if not reset and blind and blind.name and G.GAME.blind == self and RS.stats() then
            -- set_blind is called once at the start of each played blind.
            local s = RS.stats()
            local previous = (s.blinds or {})[s.current_blind or 0]
            if previous then previous.completed = true end
            RS.blind_record(true)
        end
        return result
    end
end)

safe_wrap(_G, 'end_round', function(ref)
    return function(...)
        local record = RS.blind_record(true)
        if record then
            local round = G.GAME.current_round
            record.target = G.GAME.blind.chips
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
        if s and type(mod) == 'number' and mod ~= 0 then
            local pa = RS.pa() or new_pa()
            if mod < 0 then
                s.money_spent = s.money_spent - mod
                pa.spent = pa.spent - mod
            else
                s.money_earned = s.money_earned + mod
                pa.earned = pa.earned + mod
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

local function record_card_keys(bucket, field, cards)
    if not bucket then return end
    local t = bucket[field]
    if not t then t = {}; bucket[field] = t end
    for _, c in ipairs(cards) do
        local k = RS.card_key(c)
        if k then t[k] = (t[k] or 0) + 1 end
    end
end

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
    -- Legend wraps to two lines if needed.
    local lx, ly = 0.08, 0.02
    for _, ser in ipairs(series) do
        local width = 0.2 + self.font.FONT:getWidth(ser.name) * (0.18 * self.font.FONTSCALE / G.TILESIZE)
        if lx + width > w and lx > 0.08 then lx, ly = 0.08, ly + 0.15 end
        graphics.setColor(ser.colour)
        graphics.rectangle('fill', lx, ly + 0.02, 0.09, 0.09)
        self:_text(ser.name, lx + 0.13, ly, 0.18, {1, 1, 1, 0.85})
        lx = lx + width + 0.12
    end
    if horizontal then
        local slot = ph / #labels
        local maxv = math.max(1, hi)
        for i, label in ipairs(labels) do
            local value = series[1].values[i] or 0
            local cy = top + (i - 1) * slot
            self:_text(tostring(label), 0.06, cy, math.min(0.19, slot * 1.05), {1, 1, 1, 0.85})
            graphics.setColor(series[1].colour)
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
RS._card_mode = 1 -- 1 = Played, 2 = Discarded, 3 = Drawn, 4 = Use rate

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
local CARD_MODE_OPTS = { 'Played', 'Discarded', 'Drawn', 'Use rate' }
local CARD_MODE_FIELDS = { Played = 'cards_played', Discarded = 'cards_discarded', Drawn = 'cards_drawn' }
local CARD_RANK_ID = { J = 11, Q = 12, K = 13, A = 14 }

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
    local agg, usage_drawn, usage_played = {}, {}, {}
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
            end
        end
    end

    local labels, suits_shown, cols = {}, {}, {}
    for _, su in ipairs(suits) do
        suits_shown[#suits_shown + 1] = su
        cols[#cols + 1] = CARD_SUIT_COLOURS[su]
    end
    local values, drawn_total, played_total = {}, 0, 0
    for ri, id in ipairs(ranks) do
        labels[ri] = RS.card_rank_label(id)
        values[ri] = {}
        for si, su in ipairs(suits_shown) do
            local key = su .. ':' .. id
            if mode == 'Use rate' then
                local drawn, played = usage_drawn[key] or 0, usage_played[key] or 0
                values[ri][si] = drawn > 0 and (100 * played / drawn) or false
                drawn_total, played_total = drawn_total + drawn, played_total + played
            else
                values[ri][si] = agg[key] or 0
            end
        end
    end
    return { ranks = ranks, labels = labels, suits = suits_shown, cols = cols,
        values = values, mode = mode, rate = mode == 'Use rate', drawn_total = drawn_total, played_total = played_total }
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
                if type(v) == 'number' then
                    local bh = math.max(v / maxv * ph, v > 0 and 0.02 or 0.004)
                    love.graphics.setColor(data.cols[si])
                    love.graphics.rectangle('fill', pad_l + (ri - 1) * slot + slot / 2 - (bw * m) / 2 + (si - 1) * bw,
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
    v.earned = localize('$') .. number_format(RS.career_sliced('c_dollars_earned'))
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
    local labels, best, targets = {}, {}, {}
    for _, r in ipairs(blind_history()) do
        labels[#labels + 1] = r.label .. (r.partial and '*' or '')
        best[#best + 1] = r.best or 0
        targets[#targets + 1] = r.target or 0
    end
    return { antes = labels, series = {
        series_of('Best hand', G.C.RED, best), series_of('Blind target', G.C.BLUE, targets),
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

G.FUNCS.runstats_trend_view = function()
    RS._trend_view = RS._trend_view == 'analysis' and 'overview' or 'analysis'
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
    G.FUNCS.overlay_menu{
        definition = create_UIBox_runstats(), config = { no_esc = RS._return_screen ~= nil },
    }
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
    local contents = {
        cards_slicer_row(),
        { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
            { n = G.UIT.O, config = { w = 13.4, h = 4.6, object = RSCardChart({
                w = 13.4, h = 4.6,
                data = RS.card_chart_data,
            }) } },
        } },
    }
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
        contents[#contents + 1] = UIBox_button{
            label = { 'View: ' .. (RS._trend_view == 'analysis' and 'Analysis' or 'Overview') },
            button = 'runstats_trend_view', minw = 3, minh = 0.4, scale = 0.3, colour = G.C.BLUE,
        }
        contents[#contents + 1] = kpi_row()
        if RS._trend_view == 'analysis' then
            contents[#contents + 1] = analysis_summary()
            contents[#contents + 1] = analysis_grid()
            contents[#contents + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = {
                { n = G.UIT.T, config = { text = 'Score metrics use tracked hands. Other / Earlier includes unclassified money losses.',
                    scale = 0.23, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
            } }
        else
            local charts = chart_grid()
            contents[#contents + 1] = summary_line()
            contents[#contents + 1] = charts[1]
            contents[#contents + 1] = charts[2]
        end
        contents[#contents + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.02 }, nodes = {
            { n = G.UIT.T, config = { text = 'Blind labels: ante + S / B / BOSS. * In progress / partial history. New history starts when tracked.',
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
    else
        local cols = stats_tab_columns()
        contents[#contents + 1] = { n = G.UIT.R, config = { align = 'ct' }, nodes = cols }
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

return RS
