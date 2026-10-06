# ArtMaps ReaPack

Articulation Map Creator for REAPER: build maps where each articulation sends a
keyswitch note, a CC value, or both. Maps save to `Data/ArticulationMaps/*.artmap`.

## Publish as a ReaPack repository
1. Edit `@author` in `Scripts/ArtMaps/ArtMaps_Articulation Map Creator.lua`.
2. Push this folder to a GitHub repo.
3. Install [reapack-index](https://github.com/cfillion/reapack-index) and run in the repo root:
   `reapack-index --scan --commit --amend`  (first time: `reapack-index --scan` then commit `index.xml`)
4. In REAPER: Extensions > ReaPack > Import repositories, paste:
   `https://github.com/<you>/<repo>/raw/master/index.xml`
5. Releasing an update: bump `@version`, add a `@changelog` line, commit, re-run reapack-index.

## Use
Install ReaImGui (ReaTeam Extensions repo), then run the script from the Action List.
