--[[
 * ReaScript Name: Sort selected tracks by first item position (folder-safe)
 * Description: Sorts selected sibling track blocks by their first item position while preserving folder structure.
 * Author: X-Raym; folder-safe derivative by dennech
 * Original Repository URI: https://github.com/X-Raym/REAPER-ReaScripts
 * Licence: GPL v3
 * REAPER: 5.90
 * Version: 1.0.1
--]]

--[[
 * Changelog:
 * v1.0.1 (2026-04-29)
  # Keep unselected sibling slots anchored during the execution phase.
 * v1.0.0 (2026-04-29)
  + Folder-safe derivative of X-Raym's selected track sorter.
  + Treats folder tracks as movable blocks and sorts selected children within each folder separately.
--]]

local M = {}

local function selected_set(selected_tracks)
  local set = {}
  for _, track in ipairs(selected_tracks) do
    set[track] = true
  end
  return set
end

local function direct_first_position(spec)
  if spec.firstPos ~= nil then
    return spec.firstPos, true
  end

  local positions = spec.itemPositions or {}
  local first_pos = nil

  for _, pos in ipairs(positions) do
    if first_pos == nil or pos < first_pos then
      first_pos = pos
    end
  end

  return first_pos, first_pos ~= nil
end

function M.build_tree(track_specs)
  local root = {
    id = "__root",
    isRoot = true,
    children = {},
  }

  local stack = { root }

  for index, spec in ipairs(track_specs) do
    local parent = stack[#stack] or root
    local folder_depth = spec.folderDepth or 0
    local node = {
      id = spec.id or index,
      spec = spec,
      track = spec.track,
      index = index,
      folderDepth = folder_depth,
      selected = spec.selected and true or false,
      parent = parent,
      children = {},
      originalSiblingIndex = #parent.children + 1,
    }

    parent.children[#parent.children + 1] = node

    if folder_depth > 0 then
      for _ = 1, folder_depth do
        stack[#stack + 1] = node
      end
    elseif folder_depth < 0 then
      for _ = 1, -folder_depth do
        if #stack > 1 then
          stack[#stack] = nil
        end
      end
    end
  end

  return root
end

function M.annotate_sort_positions(node)
  local has_item = false
  local sort_pos = 0

  if not node.isRoot then
    local direct_pos, has_direct_item = direct_first_position(node.spec)
    if has_direct_item then
      has_item = true
      sort_pos = direct_pos
    end
  end

  for _, child in ipairs(node.children) do
    M.annotate_sort_positions(child)

    if child.hasAnyItem and (not has_item or child.sortPos < sort_pos) then
      has_item = true
      sort_pos = child.sortPos
    end
  end

  node.hasAnyItem = has_item
  node.sortPos = has_item and sort_pos or 0
end

function M.compute_desired_children(node)
  local changed = false

  for _, child in ipairs(node.children) do
    if M.compute_desired_children(child) then
      changed = true
    end
  end

  local desired = {}
  local selected_children = {}
  local selected_slots = {}

  for index, child in ipairs(node.children) do
    desired[index] = child
    if child.selected then
      selected_children[#selected_children + 1] = child
      selected_slots[#selected_slots + 1] = index
    end
  end

  table.sort(selected_children, function(a, b)
    if a.sortPos ~= b.sortPos then
      return a.sortPos < b.sortPos
    end
    return a.originalSiblingIndex < b.originalSiblingIndex
  end)

  for index, slot in ipairs(selected_slots) do
    desired[slot] = selected_children[index]
  end

  for index, child in ipairs(node.children) do
    if desired[index] ~= child then
      changed = true
      break
    end
  end

  node.desiredChildren = desired
  return changed
end

local function linearize_desired(node, out)
  if not node.isRoot then
    out[#out + 1] = node
  end

  for _, child in ipairs(node.desiredChildren or node.children) do
    linearize_desired(child, out)
  end
end

function M.get_desired_nodes(track_specs)
  local root = M.build_tree(track_specs)
  M.annotate_sort_positions(root)
  local changed = M.compute_desired_children(root)
  local nodes = {}
  linearize_desired(root, nodes)
  return nodes, root, changed
end

function M.get_desired_track_ids(track_specs)
  local nodes = M.get_desired_nodes(track_specs)
  local ids = {}

  for _, node in ipairs(nodes) do
    ids[#ids + 1] = node.id
  end

  return ids
end

function M.save_selected_tracks(r)
  local tracks = {}
  local count = r.CountSelectedTracks(0)

  for index = 0, count - 1 do
    tracks[#tracks + 1] = r.GetSelectedTrack(0, index)
  end

  return tracks
end

function M.unselect_all_tracks(r)
  r.Main_OnCommand(40297, 0) -- Track: Unselect all tracks
end

function M.restore_selected_tracks(r, tracks)
  M.unselect_all_tracks(r)

  for _, track in ipairs(tracks) do
    r.SetTrackSelected(track, true)
  end
end

local function get_track_number(r, track)
  return math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") + 0.5)
end

local function get_track_first_item_position(r, track)
  local count = r.GetTrackNumMediaItems(track)
  local first_pos = nil

  for index = 0, count - 1 do
    local item = r.GetTrackMediaItem(track, index)
    local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")

    if first_pos == nil or pos < first_pos then
      first_pos = pos
    end
  end

  return first_pos
end

function M.collect_project_track_specs(r, selected_tracks)
  local selected = selected_set(selected_tracks)
  local specs = {}
  local count = r.CountTracks(0)

  for index = 0, count - 1 do
    local track = r.GetTrack(0, index)
    specs[#specs + 1] = {
      id = index + 1,
      track = track,
      folderDepth = math.floor(r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") + 0.5),
      selected = selected[track] and true or false,
      firstPos = get_track_first_item_position(r, track),
    }
  end

  return specs
end

local function subtree_tracks(node, out)
  out[#out + 1] = node.track

  for _, child in ipairs(node.children) do
    subtree_tracks(child, out)
  end
end

local function select_node_block(r, node)
  local tracks = {}
  subtree_tracks(node, tracks)

  M.unselect_all_tracks(r)

  for _, track in ipairs(tracks) do
    r.SetTrackSelected(track, true)
  end
end

local function current_children(r, parent)
  local children = {}

  for index, child in ipairs(parent.children) do
    children[index] = child
  end

  table.sort(children, function(a, b)
    return get_track_number(r, a.track) < get_track_number(r, b.track)
  end)

  return children
end

local function index_of_node(children, node)
  for index, child in ipairs(children) do
    if child == node then return index end
  end
  return nil
end

local function current_block_end_track_number(r, node)
  local tracks = {}
  subtree_tracks(node, tracks)

  local last = 0
  for _, track in ipairs(tracks) do
    local number = get_track_number(r, track)
    if number > last then last = number end
  end

  return last
end

local function insertion_mode(r, parent, before_node)
  if parent.isRoot then
    return 0
  end

  if not before_node then
    return 2
  end

  local children = current_children(r, parent)
  if before_node == children[1] then
    return 1
  end

  return 0
end

local function insertion_index(r, parent, before_node)
  if before_node then
    return get_track_number(r, before_node.track) - 1
  end

  if parent.isRoot then
    return r.CountTracks(0)
  end

  return current_block_end_track_number(r, parent)
end

local function move_node_before(r, parent, node, before_node)
  select_node_block(r, node)
  return r.ReorderSelectedTracks(
    insertion_index(r, parent, before_node),
    insertion_mode(r, parent, before_node)
  )
end

function M.reorder_scope(r, parent)
  local desired = parent.desiredChildren or parent.children

  for desired_index = #desired, 1, -1 do
    local desired_node = desired[desired_index]

    if desired_node.selected then
      local children = current_children(r, parent)
      local current_index = index_of_node(children, desired_node)
      local before_node = desired[desired_index + 1]
      local before_index = before_node and index_of_node(children, before_node) or nil

      if current_index then
        local should_move = false

        if before_node then
          should_move = before_index ~= current_index + 1
        else
          should_move = current_index ~= #children
        end

        if should_move then
          move_node_before(r, parent, desired_node, before_node)
        end
      end
    end
  end
end

function M.execute_sort(r, root)
  for _, child in ipairs(root.children) do
    M.execute_sort(r, child)
  end

  M.reorder_scope(r, root)
end

function M.run(r)
  r = r or reaper
  if not r then return false end

  local selected_tracks = M.save_selected_tracks(r)
  if #selected_tracks <= 1 then return false end

  local undo_name = "Sort selected tracks by first item position (folder-safe)"

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)

  local ok, err = xpcall(function()
    local specs = M.collect_project_track_specs(r, selected_tracks)
    local _, root, changed = M.get_desired_nodes(specs)

    if changed then
      M.execute_sort(r, root)
    end

    M.restore_selected_tracks(r, selected_tracks)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
  end, debug.traceback)

  if not ok then
    M.restore_selected_tracks(r, selected_tracks)
  end

  r.PreventUIRefresh(-1)
  r.Undo_EndBlock(undo_name, -1)

  if not ok then
    if r.ShowMessageBox then
      r.ShowMessageBox(tostring(err), undo_name, 0)
    else
      error(err)
    end
    return false
  end

  return true
end

if reaper then
  M.run(reaper)
end

return M
