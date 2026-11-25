# Stack Bar Forever

Add spell stacks to any enabled action bar in World of Warcraft: Forever. Each stack uses the slot's existing keybinds and keeps its own place in the sequence.

## Install

1. Download the install ZIP from [Releases](https://github.com/Ruben03x/StackBarForever/releases) when one is available. For a development install, clone this repository into a folder named `StackBarForever`.
2. Place that folder inside `World of Warcraft/_forever_/Interface/AddOns`. The client should see `Interface/AddOns/StackBarForever/StackBarForever.toc`.
3. Enable **Stack Bar Forever** on the AddOns screen. Restart WoW if it was open when you installed the addon. When updating, overwrite the addon files in the same folder to keep using your saved stacks.

## Use

1. Type `/stackbar` out of combat and open your spellbook.
2. Pick an enabled action bar in the editor, then find the column for the slot you want to extend. If `Q` already casts Overpower, drop Mortal Strike into the lowest extra slot in the `Q` column.
3. Click **Done**. The first tap of `Q` tries Overpower, the second tries Mortal Strike, and the sequence repeats.

The gold key label marks the original action as next. A gold line marks an extra spell as next. Each tap advances the stack, even if the cast fails. A stack can hold up to four extra spells.

The extra icons line up with their existing slots. You can replace an extra spell by dropping another onto it in the editor, or remove one with a right-click. Removing the last extra gives the key back to the original bar. Use `/stackbar off` to pause all stacks and `/stackbar on` to resume.

Stacks are saved per character and follow their slots when you rebind a key. Disabling a bar pauses its stacks and preserves their spells. Earlier stacks carry over to Action Bar 1. On upgrades from 0.1, a first spell that matches the existing bar action is represented by that action.

## Development and releases

The addon targets Forever 1.60.1 (interface `16001`). The repository root is the addon folder. It uses Lua and a TOC file with no external dependencies.

The editor supports Blizzard's eight action bars and checks for EllesmereUI's additional bars 9 and 10. Before releasing, test both layouts in-game. Interleave two stacks on different bars, then disable one bar and confirm its keys return to normal. Live client testing is pending.

Set the version in `StackBarForever.toc`, commit it, and push a matching tag such as `v0.3.0`. GitHub Actions packages the install ZIP and attaches it to a draft release. Review the draft after testing.
