# Folder-Safe REAPER Track Sorter

Folder-safe derivative of X-Raym's "Sort selected tracks order according to their first item positions" ReaScript.

The script sorts selected tracks by the first media item on each track, while preserving REAPER folder structure. Folder tracks are treated as whole blocks at their parent level, and selected children inside a folder can be sorted within that folder without being pulled out of it.

## Install

1. Download `Scripts/Sort selected tracks by first item position folder-safe.lua`.
2. In REAPER, open `Actions > Show action list`.
3. Choose `New Action > Load ReaScript`.
4. Select the Lua file.

No SWS extension is required.

## Behavior

- Flat selected tracks sort by their earliest media item position.
- A selected folder track moves together with all of its descendants.
- Tracks selected inside the same folder sort only within that folder.
- Selecting a child track does not select or move its parent folder block.
- Folder sort position is the earliest media item on the folder track or any descendant track.
- Empty tracks and empty folders sort at position `0`, matching the original script behavior.
- Ties keep the original sibling order.

The script moves tracks with REAPER's native `ReorderSelectedTracks` API and restores the original track selection after running.

## Attribution

Derived from:

- `X-Raym_Sort selected tracks order according to their first item positions.lua`
- Original author: X-Raym
- Original repository: <https://github.com/X-Raym/REAPER-ReaScripts>

## License

GPL v3. See `LICENSE`.
