# Stack Bar Forever

Add spell stacks to the 12 slots of Action Bar 1 in World of Warcraft: Forever. Each stack uses the slot's existing keybinds and keeps its own place in the sequence.

## Install

1. Download the install ZIP from [Releases](https://github.com/Ruben03x/StackBarForever/releases) when one is available. For a development install, clone this repository into a folder named `StackBarForever`.
2. Place that folder inside `World of Warcraft/_forever_/Interface/AddOns`. The client should see `Interface/AddOns/StackBarForever/StackBarForever.toc`.
3. Enable **Stack Bar Forever** on the AddOns screen. Restart WoW if it was open when you installed the addon. When updating, overwrite the addon files in the same folder to keep using your saved stacks.

## Use

1. Type `/stackbar` out of combat and open your spellbook.
2. Find the column for the Action Bar 1 key you want to extend. For example, if `Q` already casts Overpower, drop Mortal Strike into the lowest extra slot in the `Q` column.
3. Click **Done**. The first tap of `Q` tries Overpower, the second tries Mortal Strike, and the sequence repeats.

The gold key label marks the original action as next. A gold line marks an extra spell as next. Each tap advances the stack, even if the cast fails. A stack can hold up to four extra spells.

Reopen `/stackbar` to move the overlay by its header, replace an extra spell by dropping another onto it, or remove an extra with a right-click. Removing the last extra gives the key back to the original bar. Use `/stackbar off` to pause all stacks and `/stackbar on` to resume.

Stacks are saved per character and follow their Action Bar 1 slots when you rebind a key. Each populated slot uses a temporary override. On upgrade from 0.1, earlier stacks carry over by slot position. A first spell that matches the existing bar action is represented by that action.

## Development and releases

The addon targets Forever 1.60.1 (interface `16001`). The repository root is the addon folder. It uses Lua and a TOC file with no external dependencies.

Before releasing, test in-game with Blizzard's bar and EllesmereUI. Check that a fresh install preserves the normal bindings, then interleave two stacks in combat using custom keys. Rebind one slot, remove its last extra, and confirm the slot goes back to normal. Live client testing is pending.

Set the version in `StackBarForever.toc`, commit it, and push a matching tag such as `v0.2.0`. GitHub Actions packages the install ZIP and attaches it to a draft release. Review the draft after testing.
