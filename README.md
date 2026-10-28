# Balatro Run Stats

A Balatro mod by **andrewleeog** for tracking the current run, with summaries, charts, card usage, and probability hit rates.

## Installation

Requires [Lovely](https://github.com/ethangreen-dev/lovely-injector). [Steamodded](https://github.com/Steamodded/smods) is optional.

1. Download `BalatroRunStats.zip` from the [latest release](https://github.com/andrewleeog/BalatroRunStats/releases/latest), or clone this repository.
2. Place the repository's contents in a `BalatroRunStats` folder inside your Balatro `Mods` directory. `manifest.json`, `BalatroRunStats.lua`, and `lovely/` should be directly inside that folder.
3. Restart Balatro.

Open **Run Stats** from the pause menu or the win/game-over screen. After viewing a completed run, Back returns to the result screen.

## Pages

- **Summary:** records, run totals, purchases, all five booster pack families, and average/median hand scores.
- **Trends:** scoring versus blind targets, hands needed to win, earnings/spending, shop cash reserves, poker hands, and consumable use. Switch **View: Overview** to **Analysis** for score consistency and spending categories.
- **Prob:** observed hits/rolls alongside current listed probabilities. Listed probabilities reflect Oops! All Sixes and use the same calculation as card tooltips.
- **Cards:** rank/suit charts with Played, Discarded, Drawn, and Use rate modes.

The shared ante selector offers played antes, skips gaps, and supports endless runs beyond ante 8. Select **All** to show the whole run. An asterisk marks an ante in progress or partial score history.

## Tracking behavior

Stats are saved with the run. The mod does not keep a separate archive after you leave the result screen or start another run.

New metrics begin recording when the relevant mod version is installed. Missing historical data is not reconstructed. Unclassified spending and older pack totals appear under **Other / Earlier**.

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
