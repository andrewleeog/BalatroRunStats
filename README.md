# Balatro Run Stats

A Balatro mod by **andrewleeog** for tracking the current run, with summaries, charts, card usage, and probability hit rates.

## Installation

Requires [Lovely](https://github.com/ethangreen-dev/lovely-injector). [Steamodded](https://github.com/Steamodded/smods) is optional.

1. Download `BalatroRunStats.zip` from the [latest release](https://github.com/andrewleeog/BalatroRunStats/releases/latest), or clone this repository.
2. Place the repository's contents in a `BalatroRunStats` folder inside your Balatro `Mods` directory. `manifest.json`, `BalatroRunStats.lua`, and `lovely/` should be directly inside that folder.
3. Restart Balatro.

Open **Run Stats** from the pause menu or the win/game-over screen. After viewing a completed run, Back returns to the result screen.

Run Stats uses flat, dark table rows and disables its own text shadows for readability at small UI scales. These adjustments apply only to its menu.

## Pages

- **Summary:** records, run totals, purchases, all five booster pack families, average/median hand scores, and current-deck target chances for The Idol (top four rank/suit combinations) and Castle (suits). Target rows show copies / eligible cards and percentage; Stone cards are excluded, Wild cards use their base suit, and the ante filter does not affect these live deck counts. Steamodded suitless/rankless enhancements are excluded from the appropriate target pools.
- **Trends:** use the View button to cycle through four views:
  - **Overview:** best hand and total round score versus blind targets, hands needed to win, earnings/spending, shop cash reserves, poker hands, and consumable use. Total round score updates during the current blind and is saved when the round ends; older completed rounds without recorded totals appear as gaps in that line.
  - **Analysis:** score consistency and spending categories.
  - **Economy:** income sources by ante and progression for every poker hand. The Income button switches from Categories to Detailed: ranked bars for individual Jokers, consumables, Gold Seals, Lucky Cards, Gold Cards, sales, and other named income sources. Detailed bars total the selected antes, with eight sources per page and arrows to see the rest. Combined Gold Seal/Lucky payouts are split from the existing scoring result without additional random rolls. Older amounts without source detail remain earlier/unclassified income. Matching hand levels share a line: All hands when all match, Other hands for the remaining level-one group after hands diverge, and combined labels such as Straight + High Card for other overlaps. Shared segments split and rejoin as levels change.
  - **Deck:** composition history and a detailed breakdown of the latest snapshot in the selected ante range. The Group button cycles through suits, ranks, enhancements, seals, and editions. History shows the four most common categories plus Other types; the detail chart shows all categories.
- **Probabilities:** observed hits/rolls alongside current listed probabilities. Listed probabilities reflect Oops! All Sixes and use the same calculation as card tooltips.
- **Deck:** rank/suit charts with Played, Discarded, Drawn, Use rate, and Triggers modes. Triggers counts each activation, including retriggers, with independent Scoring Triggers and Held In Hand filters. Bars retain the four suit colors: scoring uses the base shade and held effects stack in a lighter shade. Held effects include end-of-round activations (such as Gold cards and Blue Seals); cards with no applied effect are not counted. Trigger history starts when this version is installed and follows the ante filter.
- **Consumables:** four bar charts show individual card usage for Tarot, Planet, Spectral, and all types together. Each chart title includes its total use count; the combined chart labels each card's type and uses the same type colors as the individual charts. Lists show six cards per page, with independent arrows to browse every used card. All four charts follow the ante filter. Existing run-wide card counts remain available on All; older ante totals without card-level history show Earlier / unclassified.
- **Shop:** History shows the newest stock first, with Newer/Older paging through up to 12 offers per page. Opening stock and each reroll have separate list panes, preserving the two-, three-, or four-slot rows from Overstock upgrades. Free rerolls count too, and purchases do not erase offers. Top 5 Seen ranks offers by appearance count; use Type to cycle Jokers, Planets, and Tarots, plus Playing Cards with Magic Trick and Spectral Cards on Ghost Deck. Conditional lists also stay available if those types appeared through other shop rules. Editions share one frequency entry; playing cards merge by base rank and suit. Both views follow the ante filter and retain recorded history after the run. Tracking starts with this version; reopening or loading a recorded shop does not add sightings.

Shop History uses a single column and shows each card's edition (Base, Foil, Holographic, Polychrome, or Negative). Older offers without saved edition data show Not recorded. The Shop View button also opens Vouchers: a paged list grouped by the ante when each voucher was offered, with Bought / Not bought status. Repeated offers in the same ante merge; purchases, including free redemptions, update only that ante's entry. Voucher tracking begins with this update and persists with the run; earlier unrecorded offers cannot be reconstructed.

The Shop tab shows observed Joker edition rates, including counts and percentages for Foil, Holographic, Polychrome, and Negative. A separate playing-card field appears with Magic Trick or its Illusion upgrade. Rates use all recorded offers in the selected antes, including rerolls and purchased cards, and count each stock offer once. Offers with missing edition data are explicitly excluded from the denominator. These are observed appearance rates, rather than the game's theoretical edition odds.

The shared ante selector offers played antes, skips gaps, and supports endless runs beyond ante 8. Select **All** to show the whole run. An asterisk marks an ante in progress or partial score history.

## Tracking behavior

Stats are saved with the run. The mod does not keep a separate archive after you leave the result screen or start another run.

New metrics begin recording when the relevant mod version is installed. Missing historical data is not reconstructed. Unclassified spending and older pack totals appear under **Other / Earlier**.

Income separates blind rewards, unused-hand rewards, interest, Jokers, Cards, sales, and Other, each with a distinct colour. Jokers includes direct joker effects and end-of-round bonuses. Cards includes playing-card effects (such as Lucky/Gold cards and Gold seals) and money-producing consumables. Sales remains separate. Payout components are credited when cash-out is claimed, to the ante of the blind that earned them. Other includes tag/discard rewards, unclassified income, and older income without a recorded source. Adjusted payouts that cannot be split reliably are also kept under Other.

Deck composition and hand levels keep the latest observed snapshot for each played ante, refreshed at blind transitions, after hand-level changes, and when opening stats. The Deck detail chart shows the latest snapshot within the selected range. Suit and rank counts use base card identities, including the base identity of enhanced cards.

**Use rate** measures the share of tracked deck-to-hand draws that were later played at least once. Replaying a card without drawing it again does not increase that rate. A new draw of the same card counts as a new opportunity. Blank bars mean there were no tracked draws for that rank/suit.

Without Steamodded, Lovely loads the mod directly and the probability tracker observes Balatro's existing rolls for its built-in chance effects. It does not generate extra random samples. When Steamodded is installed, the mod uses its probability API instead, including supported modded effects. Both paths reflect Oops! All Sixes and preserve existing run-stat saves.

## Development checks

Requires LuaJIT and Python 3.11+. Run the standalone suite from this repository's root:

```sh
RUNSTATS_TEST_MODE=vanilla luajit tests/dashboard.lua
RUNSTATS_TEST_MODE=vanilla python3 tests/check_patches.py
```

For Steamodded integration checks, also provide a Steamodded source checkout:

```sh
SMODS_DIR=/path/to/smods luajit tests/dashboard.lua
SMODS_DIR=/path/to/smods python3 tests/check_patches.py
```

`SMODS_DIR` defaults to `../smods-stable`. Tests use Steamodded's probability helper to check behavior against its tooltip calculation.

The patch checks also validate and compile game sources when available:

- `BALATRO_GAME_SRC`: extracted sources from your own Balatro installation; defaults to `../game-src`.
- `BALATRO_MODS_DIR`: your Balatro Mods directory, used to find `lovely/dump`. Defaults to the standard Linux Steam/Proton location.

Game sources and loader dependencies are not included in this repository.

## License

[MIT](LICENSE). Redistribution and mod-manager distribution are permitted under this license.
