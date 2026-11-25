# Stack Bar Forever

An extension to Action Bar 1 in World of Warcraft: Forever 1.60.1. You can add up to four extra spells to any of its 12 slots.

## Install

1. Extract the `StackBarForever` folder into the Forever client's `Interface/AddOns` folder. Overwrite the addon files if you're updating. The resulting path should be `Interface/AddOns/StackBarForever/StackBarForever.toc`.
2. Enable **Stack Bar Forever** on the AddOns screen. Restart the game if you installed it while the game was running.

## Try two stacks

1. Type `/stackbar` out of combat and open your spellbook.
2. If Overpower is already in Action Bar 1's `Q` slot, drop Mortal Strike into the lowest extra slot in the `Q` column. Drop another spell above a different slot and click **Done**.
3. Tap `Q` twice. The first tap attempts the existing action, Overpower, and the next tap attempts Mortal Strike. Each stack remembers its own place.

Each tap advances from the existing action through the added spells, bottom to top, even when a cast fails. The gold key label marks the existing action as next. A gold line marks an extra spell as next. Stack positions and spells are saved per character.

Reopen `/stackbar` to move the bar by its header, replace a spell by dropping another onto it, or remove a spell by right-clicking its slot. Slots above a removed spell slide down.

## Keybinds

Stacks inherit the slot's existing keybinds, including custom keys and modifiers. A slot's sequence stays with that slot when you change the key. Empty stacks leave their slots alone. Your saved keybinds, actions and layout stay as they are. Remove the last extra spell from a column to return that slot to normal, or use `/stackbar off` to pause every stack and `/stackbar on` to resume. Drag the overlay by its header to line it up above your existing action bar.

When upgrading from 0.1, existing sequences follow their original numbered slot positions. Added spells are kept, and a first spell that matches the existing bar action is represented by that action.
