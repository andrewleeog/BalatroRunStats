"""Validate Lovely charge hooks against vanilla and the installed modded source."""
from pathlib import Path
import json
import os
import re
import subprocess
import tempfile
import tomllib

root = Path(__file__).resolve().parents[1]
entries = tomllib.loads((root / 'lovely/patches.toml').read_text())['patches']
patches = [entry['pattern'] for entry in entries if 'pattern' in entry]
regex_patches = [entry['regex'] for entry in entries if 'regex' in entry]
modules = [entry['module'] for entry in entries if 'module' in entry]
assert len(modules) == 1 and modules[0]['name'] == 'runstats.runtime' and modules[0]['before'] == 'main.lua'
assert (root / modules[0]['source']).is_file()
mods = Path(os.environ.get('BALATRO_MODS_DIR', str(Path.home() / '.local/share/Steam/steamapps/compatdata/2379780/pfx/drive_c/users/steamuser/AppData/Roaming/Balatro/Mods')))
dump = mods / 'lovely/dump'
game_src = Path(os.environ.get('BALATRO_GAME_SRC', str(root.parent / 'game-src')))
compiled = []
with tempfile.TemporaryDirectory(prefix='runstats-patches-') as temp:
    for label, source in [('vanilla', game_src), ('installed-mods', dump)]:
        if not source.exists():
            continue
        targets = {}
        for patch in patches:
            if label == 'installed-mods' and 'run_stats_button' in patch['payload']:
                continue  # pause-menu patches are already present in the dump
            target = patch['target']
            text = targets.get(target, (source / target).read_text())
            pattern = re.compile(r'(?m)^(?P<indent>[ \t]*)' + re.escape(patch['pattern']) + r'[ \t]*$')
            matches = list(pattern.finditer(text))
            assert len(matches) == patch.get('times', 1), (label, target, patch['pattern'], len(matches))
            def replace(match):
                payload = '\n'.join(match['indent'] + line for line in patch['payload'].splitlines())
                if patch['position'] == 'before':
                    return payload + '\n' + match[0]
                assert patch['position'] == 'after'
                return match[0] + '\n' + payload
            targets[target] = pattern.sub(replace, text)
        for patch in regex_patches:
            target = patch['target']
            text = targets.get(target, (source / target).read_text())
            expression = re.sub(r'\(\?<([a-z_]+)>', r'(?P<\1>', patch['pattern'])
            pattern = re.compile(expression)
            matches = list(pattern.finditer(text))
            if label == 'vanilla' or target == 'card.lua':
                assert matches, (label, target, 'missing income payment sites')
            def replace_regex(match):
                payload = re.sub(r'\$([a-z_]+)', lambda name: match[name[1]] or '', patch['payload'])
                prepend = re.sub(r'\$([a-z_]+)', lambda name: match[name[1]] or '', patch.get('line_prepend', ''))
                assert patch['position'] == 'at'
                return '\n'.join(prepend + line for line in payload.splitlines())
            targets[target] = pattern.sub(replace_regex, text)
        for target, text in targets.items():
            path = Path(temp) / label / target
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
            compiled.append(path)
    script = '\n'.join('assert(loadfile(' + json.dumps(str(path)) + '))' for path in compiled)
    subprocess.run(['luajit', '-'], input=script, text=True, check=True, cwd=root)

# Execute the exact injected payloads, not a reimplementation of their logic.
script = """
dofile('tests/dashboard.lua')
local RS = RunStats
G.GAME.run_stats = RS.fresh_stats()
G.GAME.round_resets.ante = 1
RS._ante_sel = 0
local bucket = RS.pa()
bucket.spent = 26
"""
charge_patches = [p for p in patches if 'record_spend' in p['payload']]
for patch in charge_patches:
    payload = patch['payload']
    if 'c1.cost' in patch['pattern']:
        script += "do local c1 = {ability = {set = 'Joker'}, cost = 7}; " + payload + " end\n"
    elif 'reroll_cost' in patch['pattern']:
        script += "G.GAME.current_round.reroll_cost = 4; " + payload + "\n"
    else:
        for kind, cost in [('Booster', 5), ('Voucher', 10), ('Booster', 0), ('Voucher', -3)]:
            script += f"do local self = {{ability = {{set = '{kind}'}}, cost = {cost}}}; " + payload + " end\n"
script += """
local values, total = RS.spending_summary()
assert(total == 26 and values.jokers == 7 and values.rerolls == 4 and values.packs == 5 and values.vouchers == 10 and values.other == 0)
print('Lovely patch checks passed: vanilla and installed source targets, Lua compilation and exact charge payloads')
"""
income_patches = [p for p in patches if 'prepare_cashout_income' in p['payload'] or "prepare_income('sales')" in p['payload']]
script += """
G.GAME.run_stats = RS.fresh_stats()
G.GAME.round_resets.ante = 1
local bucket = RS.pa()
G.GAME.run_stats.round_income = {ante = 1, categories = {blinds = 5, hands = 2, interest = 3}}
"""
for patch in income_patches:
    if 'prepare_cashout_income' in patch['payload']:
        script += patch['payload'] + "\nease_dollars(12)\n"
    else:
        script += "do local self = {sell_cost = 7}; " + patch['payload'] + "; ease_dollars(self.sell_cost) end\n"
script += """
local income, total = RS.income_summary()
assert(total == 19 and income.blinds == 5 and income.hands == 2 and income.interest == 3 and income.sales == 7 and income.other == 2)
print('Income patch checks passed: actual cash-out preparation and sale-credit payloads')
"""
card_payment = next(p['payload'] for p in regex_patches if p['target'] == 'card.lua')
effect_payment = next(p['payload'] for p in regex_patches if p['target'] == 'functions/state_events.lua')
script += """
G.GAME.run_stats = RS.fresh_stats()
G.GAME.round_resets.ante = 1
"""
for kind, amount in [('Joker', 9), ('Tarot', 4)]:
    script += f"do local self = {{ability = {{set = '{kind}', extra = {amount}}}}}; " + card_payment.replace('$args', 'self.ability.extra') + " end\n"
for effect, amount in [("{card = {ability = {set = 'Joker'}}}", 6), ('{}', 3)]:
    script += f"do local effects = {{{effect}}}; local ii = 1; effects[ii].dollars = {amount}; " + effect_payment.replace('$args', 'effects[ii].dollars') + " end\n"
script += """
local income, total = RS.income_summary()
assert(total == 22 and income.jokers == 15 and income.cards == 7 and income.other == 0)
print('Income source patches passed: direct/deferred card payments and returned vanilla effects')
"""
bootstrap = next(p['payload'] for p in patches if 'runstats.runtime' in p['payload'])
script += f"local boot = assert(loadstring({json.dumps(bootstrap)}))\n"
script += """
local calls = 0
local loader = function(name) assert(name == 'runstats.runtime'); calls = calls + 1 end
setfenv(boot, {require = loader})()
assert(calls == 1, 'Lovely must load the mod when Steamodded is absent')
setfenv(boot, {SMODS = {}, require = loader})()
assert(calls == 1, 'Steamodded owns initialization when installed')
print('Lovely bootstrap checks passed: standalone module loading and Steamodded coexistence')
"""
subprocess.run(['luajit', '-'], input=script, text=True, check=True, cwd=root)
