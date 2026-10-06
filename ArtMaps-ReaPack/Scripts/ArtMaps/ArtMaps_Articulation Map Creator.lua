-- @description Articulation Map Creator (keyswitch + CC)
-- @author Ben Randall
-- @version 0.1.0
-- @changelog
--   + Initial release
-- @about
--   # Articulation Map Creator
--   Build articulation maps for sample libraries. Each articulation can send a
--   keyswitch note, a CC value, or both. Maps are saved as plain-text .artmap files in
--   <REAPER resource path>/Data/ArticulationMaps.
--
--   * Test an articulation (sends via the virtual MIDI keyboard - arm a track with
--     input set to "Virtual MIDI keyboard" or "All MIDI inputs")
--   * Insert an articulation's keyswitch/CC at the edit cursor in the active MIDI take
--   * Requires ReaImGui (install via ReaPack, ReaTeam Extensions repository)

if not reaper.ImGui_CreateContext then
  reaper.MB("This script needs ReaImGui.\nInstall it via ReaPack (ReaTeam Extensions repository).",
            "Articulation Map Creator", 0)
  return
end
package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.9'

---------------------------------------------------------------- paths / state
local SEP = package.config:sub(1, 1)
local MAP_DIR = reaper.GetResourcePath() .. SEP .. "Data" .. SEP .. "ArticulationMaps"
reaper.RecursiveCreateDirectory(MAP_DIR, 0)

local ctx = ImGui.CreateContext('Articulation Map Creator')
local map = { name = "New Map", arts = {} }
local status = ""
local pending_off = {}   -- scheduled note-offs for Test button
local NOTE_NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }

local function note_name(n)
  return NOTE_NAMES[(n % 12) + 1] .. tostring(math.floor(n / 12) - 1)
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function new_art()
  return { name = "Articulation", chan = 1,
           ks_on = true, ks = 24, cc_on = false, cc = 32, ccval = 0 }
end

---------------------------------------------------------------- file handling
local function clean(s) return (s:gsub("[\t\r\n]", " ")) end
local function file_safe(s) return (s:gsub('[<>:"/\\|%?%*]', "_")) end

local function save_map()
  local path = MAP_DIR .. SEP .. file_safe(map.name) .. ".artmap"
  local f = io.open(path, "w")
  if not f then status = "Could not write " .. path return end
  f:write("MAP\t", clean(map.name), "\n")
  for _, a in ipairs(map.arts) do
    f:write(table.concat({
      "ART", clean(a.name), a.chan,
      a.ks_on and 1 or 0, a.ks,
      a.cc_on and 1 or 0, a.cc, a.ccval }, "\t"), "\n")
  end
  f:close()
  status = "Saved " .. path
end

local function load_map(filename)
  local f = io.open(MAP_DIR .. SEP .. filename, "r")
  if not f then status = "Could not open " .. filename return end
  local m = { name = filename:gsub("%.artmap$", ""), arts = {} }
  for line in f:lines() do
    local p = {}
    for field in (line .. "\t"):gmatch("(.-)\t") do p[#p + 1] = field end
    if p[1] == "MAP" then
      m.name = p[2] or m.name
    elseif p[1] == "ART" then
      m.arts[#m.arts + 1] = {
        name = p[2] or "", chan = tonumber(p[3]) or 1,
        ks_on = p[4] == "1", ks = tonumber(p[5]) or 24,
        cc_on = p[6] == "1", cc = tonumber(p[7]) or 32, ccval = tonumber(p[8]) or 0 }
    end
  end
  f:close()
  map = m
  status = "Loaded " .. filename
end

local function list_maps()
  local out, i = {}, 0
  while true do
    local fn = reaper.EnumerateFiles(MAP_DIR, i)
    if not fn then break end
    if fn:match("%.artmap$") then out[#out + 1] = fn end
    i = i + 1
  end
  table.sort(out)
  return out
end

---------------------------------------------------------------- MIDI actions
local function test_art(a)
  local ch = a.chan - 1
  if a.cc_on then
    reaper.StuffMIDIMessage(0, 0xB0 + ch, a.cc, a.ccval)
  end
  if a.ks_on then
    reaper.StuffMIDIMessage(0, 0x90 + ch, a.ks, 100)
    pending_off[#pending_off + 1] = { t = reaper.time_precise() + 0.15, status = 0x80 + ch, d1 = a.ks }
  end
end

local function get_target_take()
  local ed = reaper.MIDIEditor_GetActive()
  if ed then
    local t = reaper.MIDIEditor_GetTake(ed)
    if t then return t end
  end
  local item = reaper.GetSelectedMediaItem(0, 0)
  if item then
    local t = reaper.GetActiveTake(item)
    if t and reaper.TakeIsMIDI(t) then return t end
  end
end

local function insert_art(a)
  local take = get_target_take()
  if not take then status = "Open a MIDI editor or select a MIDI item first." return end
  reaper.Undo_BeginBlock()
  local ppq = reaper.MIDI_GetPPQPosFromProjTime(take, reaper.GetCursorPosition())
  local ch = a.chan - 1
  if a.cc_on then
    reaper.MIDI_InsertCC(take, false, false, ppq, 0xB0, ch, a.cc, a.ccval)
  end
  if a.ks_on then
    reaper.MIDI_InsertNote(take, false, false, ppq, ppq + 240, ch, a.ks, 100, true)
  end
  reaper.MIDI_Sort(take)
  reaper.Undo_EndBlock("Insert articulation: " .. a.name, -1)
  status = "Inserted '" .. a.name .. "' at edit cursor"
end

---------------------------------------------------------------- UI
local function int_cell(label, v, lo, hi)
  ImGui.SetNextItemWidth(ctx, -1)
  local changed, nv = ImGui.InputInt(ctx, label, v, 0, 0)
  if changed then v = clamp(nv, lo, hi) end
  return v
end

local function draw()
  -- map name + file controls
  ImGui.SetNextItemWidth(ctx, 260)
  local ch, v = ImGui.InputText(ctx, "Map name", map.name)
  if ch then map.name = v end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Save") then save_map() end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "New") then map = { name = "New Map", arts = {} } status = "" end
  ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 200)
  if ImGui.BeginCombo(ctx, "Load", "Choose map...") then
    for _, fn in ipairs(list_maps()) do
      if ImGui.Selectable(ctx, fn, false) then load_map(fn) end
    end
    ImGui.EndCombo(ctx)
  end

  ImGui.Separator(ctx)
  if ImGui.Button(ctx, "+ Add articulation") then
    map.arts[#map.arts + 1] = new_art()
  end
  ImGui.SameLine(ctx)
  ImGui.TextDisabled(ctx, "Keyswitch notes are shown as REAPER names (C4 = 60).")

  local flags = ImGui.TableFlags_Borders | ImGui.TableFlags_RowBg | ImGui.TableFlags_SizingStretchProp
  if ImGui.BeginTable(ctx, "arts", 9, flags) then
    ImGui.TableSetupColumn(ctx, "Name", ImGui.TableColumnFlags_WidthStretch, 3)
    ImGui.TableSetupColumn(ctx, "Ch", ImGui.TableColumnFlags_WidthStretch, 1)
    ImGui.TableSetupColumn(ctx, "KS", ImGui.TableColumnFlags_WidthStretch, 0.7)
    ImGui.TableSetupColumn(ctx, "Note", ImGui.TableColumnFlags_WidthStretch, 1.5)
    ImGui.TableSetupColumn(ctx, "CC", ImGui.TableColumnFlags_WidthStretch, 0.7)
    ImGui.TableSetupColumn(ctx, "CC #", ImGui.TableColumnFlags_WidthStretch, 1)
    ImGui.TableSetupColumn(ctx, "Value", ImGui.TableColumnFlags_WidthStretch, 1)
    ImGui.TableSetupColumn(ctx, "Send", ImGui.TableColumnFlags_WidthStretch, 2)
    ImGui.TableSetupColumn(ctx, "Edit", ImGui.TableColumnFlags_WidthStretch, 2)
    ImGui.TableHeadersRow(ctx)

    local del, up, down
    for i, a in ipairs(map.arts) do
      ImGui.PushID(ctx, i)
      ImGui.TableNextRow(ctx)

      ImGui.TableNextColumn(ctx)
      ImGui.SetNextItemWidth(ctx, -1)
      local c, nv = ImGui.InputText(ctx, "##name", a.name)
      if c then a.name = nv end

      ImGui.TableNextColumn(ctx)
      a.chan = int_cell("##ch", a.chan, 1, 16)

      ImGui.TableNextColumn(ctx)
      local _, kon = ImGui.Checkbox(ctx, "##kson", a.ks_on)
      a.ks_on = kon

      ImGui.TableNextColumn(ctx)
      a.ks = int_cell("##ks", a.ks, 0, 127)
      ImGui.TextDisabled(ctx, note_name(a.ks))

      ImGui.TableNextColumn(ctx)
      local _, con = ImGui.Checkbox(ctx, "##ccon", a.cc_on)
      a.cc_on = con

      ImGui.TableNextColumn(ctx)
      a.cc = int_cell("##cc", a.cc, 0, 127)

      ImGui.TableNextColumn(ctx)
      a.ccval = int_cell("##ccv", a.ccval, 0, 127)

      ImGui.TableNextColumn(ctx)
      if ImGui.SmallButton(ctx, "Test") then test_art(a) end
      ImGui.SameLine(ctx)
      if ImGui.SmallButton(ctx, "Insert") then insert_art(a) end

      ImGui.TableNextColumn(ctx)
      if ImGui.SmallButton(ctx, "Up") then up = i end
      ImGui.SameLine(ctx)
      if ImGui.SmallButton(ctx, "Dn") then down = i end
      ImGui.SameLine(ctx)
      if ImGui.SmallButton(ctx, "Del") then del = i end

      ImGui.PopID(ctx)
    end
    ImGui.EndTable(ctx)

    if del then table.remove(map.arts, del)
    elseif up and up > 1 then map.arts[up], map.arts[up - 1] = map.arts[up - 1], map.arts[up]
    elseif down and down < #map.arts then map.arts[down], map.arts[down + 1] = map.arts[down + 1], map.arts[down] end
  end

  if status ~= "" then ImGui.Separator(ctx) ImGui.TextWrapped(ctx, status) end
end

local function loop()
  -- release any test notes that are due
  local now = reaper.time_precise()
  for i = #pending_off, 1, -1 do
    local p = pending_off[i]
    if now >= p.t then
      reaper.StuffMIDIMessage(0, p.status, p.d1, 0)
      table.remove(pending_off, i)
    end
  end

  ImGui.SetNextWindowSize(ctx, 760, 420, ImGui.Cond_FirstUseEver)
  local visible, open = ImGui.Begin(ctx, "Articulation Map Creator", true)
  if visible then
    draw()
    ImGui.End(ctx)
  end
  if open then reaper.defer(loop) end
end

reaper.defer(loop)
