local sorter = assert(loadfile("Scripts/Sort selected tracks by first item position folder-safe.lua"))()

local function join(values)
  local parts = {}
  for index, value in ipairs(values) do
    parts[index] = tostring(value)
  end
  return table.concat(parts, ",")
end

local function assert_equal(name, actual, expected)
  local actual_text = join(actual)
  local expected_text = join(expected)

  if actual_text ~= expected_text then
    error(name .. "\nexpected: " .. expected_text .. "\nactual:   " .. actual_text, 2)
  end
end

local function assert_order(name, tracks, expected)
  assert_equal(name, sorter.get_desired_track_ids(tracks), expected)
end

local function track(id, folder_depth, positions, selected)
  return {
    id = id,
    folderDepth = folder_depth or 0,
    itemPositions = positions or {},
    selected = selected and true or false,
  }
end

assert_order("flat selected tracks sort by first item position", {
  track("A", 0, { 10 }, true),
  track("B", 0, { 5 }, true),
  track("C", 0, { 20 }, true),
}, { "B", "A", "C" })

assert_order("selected top-level folder moves as a single block", {
  track("Folder", 1, {}, true),
  track("Child A", 0, { 20 }, false),
  track("Child B", -1, { 30 }, false),
  track("Lead", 0, { 5 }, true),
}, { "Lead", "Folder", "Child A", "Child B" })

assert_order("selected children sort only inside their current folder", {
  track("Folder", 1, {}, false),
  track("Late", 0, { 10 }, true),
  track("Early", -1, { 5 }, true),
}, { "Folder", "Early", "Late" })

assert_order("nested folders preserve hierarchy while sorting each level", {
  track("Folder", 1, {}, false),
  track("Nested", 1, {}, true),
  track("Nested Late", 0, { 30 }, true),
  track("Nested Early", -1, { 10 }, true),
  track("Folder Early", -1, { 5 }, true),
  track("After", 0, { 1 }, false),
}, { "Folder", "Folder Early", "Nested", "Nested Early", "Nested Late", "After" })

assert_order("partial folder selection does not pull children out of folders", {
  track("Top Late", 0, { 10 }, true),
  track("Folder", 1, {}, false),
  track("Inner Early", -1, { 1 }, true),
  track("Top Early", 0, { 5 }, true),
}, { "Top Early", "Folder", "Inner Early", "Top Late" })

assert_order("empty tracks sort at zero like the original script", {
  track("Has Item", 0, { 5 }, true),
  track("Empty A", 0, {}, true),
  track("Empty B", 0, {}, true),
}, { "Empty A", "Empty B", "Has Item" })

assert_order("ties keep original sibling order", {
  track("A", 0, { 5 }, true),
  track("B", 0, { 5 }, true),
  track("C", 0, { 1 }, true),
}, { "C", "A", "B" })

local function make_mock_reaper(tracks, options)
  options = options or {}

  local mock = {
    tracks = tracks,
    reorderCalls = {},
    preserveFolderDepthsOnReorder = options.preserveFolderDepthsOnReorder and true or false,
  }

  local function track_index(track)
    for index, candidate in ipairs(mock.tracks) do
      if candidate == track then return index end
    end
    return nil
  end

  local function build_tree()
    local root = { isRoot = true, children = {} }
    local stack = { root }
    local node_by_track = {}

    for _, tr in ipairs(mock.tracks) do
      local parent = stack[#stack]
      local node = {
        track = tr,
        parent = parent,
        children = {},
      }

      parent.children[#parent.children + 1] = node
      node_by_track[tr] = node

      local folder_depth = tr.folderDepth or 0
      if folder_depth > 0 then
        for _ = 1, folder_depth do
          stack[#stack + 1] = node
        end
      elseif folder_depth < 0 then
        for _ = 1, -folder_depth do
          if #stack > 1 then stack[#stack] = nil end
        end
      end
    end

    return root, node_by_track
  end

  local function flatten_nodes(root)
    local nodes = {}

    local function visit(parent)
      for _, node in ipairs(parent.children) do
        nodes[#nodes + 1] = node
        visit(node)
      end
    end

    visit(root)
    return nodes
  end

  local function flatten_tree(root)
    local tracks_out = {}

    local function visit(parent)
      for _, node in ipairs(parent.children) do
        if not mock.preserveFolderDepthsOnReorder then
          node.track.folderDepth = #node.children > 0 and 1 or 0
        end

        tracks_out[#tracks_out + 1] = node.track
        visit(node)

        if not mock.preserveFolderDepthsOnReorder and #node.children > 0 then
          tracks_out[#tracks_out].folderDepth = tracks_out[#tracks_out].folderDepth - 1
        end
      end
    end

    visit(root)
    mock.tracks = tracks_out
  end

  local function child_index(parent, node)
    for index, child in ipairs(parent.children) do
      if child == node then return index end
    end
    return nil
  end

  local function remove_child(parent, node)
    local index = child_index(parent, node)
    if not index then error("selected block is not in its parent") end
    table.remove(parent.children, index)
  end

  local function is_ancestor_selected(node, selected)
    local parent = node.parent

    while parent and not parent.isRoot do
      if selected[parent.track] then return true end
      parent = parent.parent
    end

    return false
  end

  local function mark_subtree(node, selected)
    selected[node.track] = true
    for _, child in ipairs(node.children) do
      mark_subtree(child, selected)
    end
  end

  local function find_node_index(nodes, node)
    for index, candidate in ipairs(nodes) do
      if candidate == node then return index end
    end
    return nil
  end

  function mock.CountSelectedTracks()
    local count = 0
    for _, tr in ipairs(mock.tracks) do
      if tr.selected then count = count + 1 end
    end
    return count
  end

  function mock.GetSelectedTrack(_, selected_index)
    local seen = 0
    for _, tr in ipairs(mock.tracks) do
      if tr.selected then
        if seen == selected_index then return tr end
        seen = seen + 1
      end
    end
    return nil
  end

  function mock.CountTracks()
    return #mock.tracks
  end

  function mock.GetTrack(_, index)
    return mock.tracks[index + 1]
  end

  function mock.GetMediaTrackInfo_Value(tr, key)
    if key == "IP_TRACKNUMBER" then return track_index(tr) end
    if key == "I_FOLDERDEPTH" then return tr.folderDepth end
    return 0
  end

  function mock.GetTrackNumMediaItems(tr)
    return #tr.items
  end

  function mock.GetTrackMediaItem(tr, index)
    return tr.items[index + 1]
  end

  function mock.GetMediaItemInfo_Value(item, key)
    if key == "D_POSITION" then return item.pos end
    return 0
  end

  function mock.Main_OnCommand(command)
    if command == 40297 then
      for _, tr in ipairs(mock.tracks) do tr.selected = false end
    end
  end

  function mock.SetTrackSelected(tr, selected)
    tr.selected = selected and true or false
  end

  function mock.SetMediaTrackInfo_Value(tr, key, value)
    if key == "I_FOLDERDEPTH" then
      tr.folderDepth = value
      return true
    end

    return false
  end

  function mock.ReorderSelectedTracks(before_track_index, make_prev_folder)
    mock.reorderCalls[#mock.reorderCalls + 1] = {
      beforeTrackIdx = before_track_index,
      makePrevFolder = make_prev_folder,
    }

    local root, node_by_track = build_tree()
    local selected = {}
    for _, tr in ipairs(mock.tracks) do
      if tr.selected then selected[tr] = true end
    end

    local moving_roots = {}
    for _, tr in ipairs(mock.tracks) do
      if selected[tr] then
        local node = node_by_track[tr]
        if not is_ancestor_selected(node, selected) then
          moving_roots[#moving_roots + 1] = node
        end
      end
    end

    local complete_selection = {}
    for _, node in ipairs(moving_roots) do
      mark_subtree(node, complete_selection)
    end

    for tr in pairs(selected) do
      if not complete_selection[tr] then
        error("mock ReorderSelectedTracks received a partial folder selection")
      end
    end

    for tr in pairs(complete_selection) do
      if not selected[tr] then
        error("mock ReorderSelectedTracks did not receive a complete folder block")
      end
    end

    local anchor_track = mock.tracks[before_track_index + 1]
    local anchor_node = anchor_track and not selected[anchor_track] and node_by_track[anchor_track] or nil

    for _, node in ipairs(moving_roots) do
      remove_child(node.parent, node)
    end

    local remaining_nodes = flatten_nodes(root)
    local anchor_index = anchor_node and find_node_index(remaining_nodes, anchor_node) or (#remaining_nodes + 1)
    local previous_node = remaining_nodes[anchor_index - 1]
    local target_parent
    local insert_at

    if make_prev_folder == 1 then
      target_parent = previous_node or root
      insert_at = 1
    elseif make_prev_folder == 2 then
      target_parent = previous_node and previous_node.parent or root
      insert_at = previous_node and (child_index(target_parent, previous_node) + 1) or (#target_parent.children + 1)
    else
      target_parent = anchor_node and anchor_node.parent or root
      insert_at = anchor_node and child_index(target_parent, anchor_node) or (#target_parent.children + 1)
    end

    for offset, node in ipairs(moving_roots) do
      node.parent = target_parent
      table.insert(target_parent.children, insert_at + offset - 1, node)
    end

    flatten_tree(root)
    return true
  end

  function mock.Undo_BeginBlock() end
  function mock.Undo_EndBlock() end
  function mock.PreventUIRefresh() end
  function mock.TrackList_AdjustWindows() end
  function mock.UpdateArrange() end

  return mock
end

local function values(tracks, key)
  local out = {}
  for index, tr in ipairs(tracks) do
    out[index] = tr[key]
  end
  return out
end

local function selected_tracks(mock)
  local out = {}
  for _, tr in ipairs(mock.tracks) do
    if tr.selected then out[#out + 1] = tr end
  end
  return out
end

local function assert_same_selection(name, actual, expected)
  if #actual ~= #expected then
    error(name .. "\nexpected selected count: " .. #expected .. "\nactual selected count:   " .. #actual, 2)
  end

  for _, expected_track in ipairs(expected) do
    local found = false
    for _, actual_track in ipairs(actual) do
      if actual_track == expected_track then found = true end
    end
    if not found then error(name .. "\nmissing restored track: " .. expected_track.id, 2) end
  end
end

local function assert_run(name, tracks, expected_ids, expected_depths, expected_modes, options)
  local mock = make_mock_reaper(tracks, options)
  local initial_selection = selected_tracks(mock)

  assert(sorter.run(mock) == true)
  assert_equal(name .. " order", values(mock.tracks, "id"), expected_ids)

  if expected_depths then
    assert_equal(name .. " folderDepth", values(mock.tracks, "folderDepth"), expected_depths)
  end

  if expected_modes then
    local modes = {}
    for index, call in ipairs(mock.reorderCalls) do
      modes[index] = call.makePrevFolder
    end
    assert_equal(name .. " makePrevFolder calls", modes, expected_modes)
  end

  assert_same_selection(name .. " restored selection", selected_tracks(mock), initial_selection)
end

assert_run("execution keeps unselected sibling slot anchored", {
  { id = "A", folderDepth = 0, selected = true, items = { { pos = 30 } } },
  { id = "U", folderDepth = 0, selected = false, items = { { pos = 0 } } },
  { id = "B", folderDepth = 0, selected = true, items = { { pos = 10 } } },
  { id = "C", folderDepth = 0, selected = true, items = { { pos = 20 } } },
}, { "B", "U", "C", "A" }, { 0, 0, 0, 0 }, { 0, 0 })

assert_run("execution keeps selected folder as a whole block", {
  { id = "Folder", folderDepth = 1, selected = true, items = {} },
  { id = "Child A", folderDepth = 0, selected = false, items = { { pos = 20 } } },
  { id = "Child B", folderDepth = -1, selected = false, items = { { pos = 30 } } },
  { id = "Lead", folderDepth = 0, selected = true, items = { { pos = 5 } } },
}, { "Lead", "Folder", "Child A", "Child B" }, { 0, 1, 0, -1 }, { 0 })

assert_run("execution repairs folder depths when appending a moved child", {
  { id = "Folder", folderDepth = 1, selected = false, items = {} },
  { id = "Late", folderDepth = 0, selected = true, items = { { pos = 10 } } },
  { id = "Early", folderDepth = -1, selected = true, items = { { pos = 5 } } },
}, { "Folder", "Early", "Late" }, { 1, 0, -1 }, { 2 })

assert_run("execution repairs folder depths when moving before the first child", {
  { id = "Folder", folderDepth = 1, selected = false, items = {} },
  { id = "A", folderDepth = 0, selected = true, items = { { pos = 30 } } },
  { id = "U", folderDepth = 0, selected = false, items = { { pos = 0 } } },
  { id = "B", folderDepth = -1, selected = true, items = { { pos = 10 } } },
}, { "Folder", "B", "U", "A" }, { 1, 0, 0, -1 }, { 2, 1 })

assert_run("execution uses normal folder mode before a later child", {
  { id = "Folder", folderDepth = 1, selected = false, items = {} },
  { id = "A", folderDepth = 0, selected = true, items = { { pos = 30 } } },
  { id = "U1", folderDepth = 0, selected = false, items = { { pos = 0 } } },
  { id = "B", folderDepth = 0, selected = true, items = { { pos = 10 } } },
  { id = "U2", folderDepth = -1, selected = false, items = { { pos = 40 } } },
}, { "Folder", "B", "U1", "A", "U2" }, { 1, 0, 0, 0, -1 }, { 0, 1 })

assert_run("execution repairs nested folder closure after moving a folder block", {
  { id = "SFX", folderDepth = 1, selected = true, items = {} },
  { id = "Intro", folderDepth = 1, selected = true, items = {} },
  { id = "Late A", folderDepth = 0, selected = true, items = { { pos = 30 } } },
  { id = "Late B", folderDepth = 0, selected = true, items = { { pos = 40 } } },
  { id = "Swoosh Folder", folderDepth = 1, selected = true, items = { { pos = 10 } } },
  { id = "Swoosh Child", folderDepth = -2, selected = true, items = { { pos = 12 } } },
  { id = "After Intro", folderDepth = -1, selected = true, items = { { pos = 50 } } },
}, {
  "SFX",
  "Intro",
  "Swoosh Folder",
  "Swoosh Child",
  "Late A",
  "Late B",
  "After Intro",
}, { 1, 1, 1, -1, 0, -1, -1 }, nil, {
  preserveFolderDepthsOnReorder = true,
})

print("ok")
