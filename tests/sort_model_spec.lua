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

local function make_mock_reaper()
  local mock = {}
  mock.tracks = {
    { id = "Late", folderDepth = 0, selected = true, items = { { pos = 10 } } },
    { id = "Early", folderDepth = 0, selected = true, items = { { pos = 5 } } },
    { id = "Other", folderDepth = 0, selected = false, items = {} },
  }

  local function track_index(track)
    for index, candidate in ipairs(mock.tracks) do
      if candidate == track then return index end
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

  function mock.ReorderSelectedTracks(before_track_index)
    local moving = {}
    local staying = {}

    for _, tr in ipairs(mock.tracks) do
      if tr.selected then
        moving[#moving + 1] = tr
      else
        staying[#staying + 1] = tr
      end
    end

    local insert_at = before_track_index + 1
    if insert_at < 1 then insert_at = 1 end
    if insert_at > #staying + 1 then insert_at = #staying + 1 end

    local reordered = {}
    for index = 1, insert_at - 1 do reordered[#reordered + 1] = staying[index] end
    for _, tr in ipairs(moving) do reordered[#reordered + 1] = tr end
    for index = insert_at, #staying do reordered[#reordered + 1] = staying[index] end
    mock.tracks = reordered
    return true
  end

  function mock.Undo_BeginBlock() end
  function mock.Undo_EndBlock() end
  function mock.PreventUIRefresh() end
  function mock.TrackList_AdjustWindows() end
  function mock.UpdateArrange() end

  return mock
end

local mock = make_mock_reaper()
local initial_selection = { mock.tracks[1], mock.tracks[2] }
assert(sorter.run(mock) == true)
assert_equal("script executes the planned flat reorder", {
  mock.tracks[1].id,
  mock.tracks[2].id,
  mock.tracks[3].id,
}, { "Early", "Late", "Other" })

local selected_after_run = {}
for _, tr in ipairs(mock.tracks) do
  if tr.selected then selected_after_run[#selected_after_run + 1] = tr end
end

if #selected_after_run ~= #initial_selection then
  error("script restores the original selected track count")
end

for _, tr in ipairs(initial_selection) do
  local found = false
  for _, selected in ipairs(selected_after_run) do
    if selected == tr then found = true end
  end
  if not found then error("script restores the original selected track handles") end
end

print("ok")
