--[[
 * ReaScript Name: ReaHaptic_ItemController
 * Description: enables all items of a haptic item to move and resize together
 * Author: Florian Heynen
 * Version: 1.0
--]]

local cmd_id = reaper.NamedCommandLookup("_MY_CUSTOM_SCRIPT_ID")

local state = reaper.GetToggleCommandState(cmd_id)

local new_state = state == 1 and 0 or 1
reaper.SetToggleCommandState(0, cmd_id, new_state)

reaper.RefreshToolbar2(0, cmd_id)

local function get_item_notes(item)
    local _, notes = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
    return notes
end

local function findAndSync_matching_items()
    local num_selected_items = reaper.CountSelectedMediaItems(0)
    local valid_track_names = {["haptics"] = true, ["amplitude"] = true, ["frequency"] = true, ["emphasis"] = true}
     -- Track processed groups

    for i = 0, num_selected_items - 1 do
        local reference_item = reaper.GetSelectedMediaItem(0, i)
        local reference_groupId = reaper.GetMediaItemInfo_Value(reference_item, "I_GROUPID")

        if reference_groupId > 0 then
            local num_tracks = reaper.CountTracks(0)
            for t = 0, num_tracks - 1 do
                local track = reaper.GetTrack(0, t)
                local _, track_name = reaper.GetTrackName(track, "")
                if valid_track_names[track_name] then
                    local num_items = reaper.CountTrackMediaItems(track)
                    for j = 0, num_items - 1 do
                        local item = reaper.GetTrackMediaItem(track, j)
                        if item ~= reference_item then
                            local item_groupId = reaper.GetMediaItemInfo_Value(item, "I_GROUPID")
                            local item_groupName = get_item_notes(item)
                            if item_groupId == reference_groupId and item_groupName ~= "" then
                                local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                                local hasMarker = reaper.SetProjectMarker(item_groupId, false, item_pos,item_pos,item_groupName)--boolean reaper.SetProjectMarker(integer markrgnindexnumber, boolean isrgn, number pos, number rgnend, string name)
                                if not hasMarker then
                                    reaper.AddProjectMarker(0, false, item_pos, item_pos, item_groupName, item_groupId)
                                end
                                reaper.SetMediaItemSelected(item, true)
                            end
                        end
                    end
                end
            end
        end
    end
end

local function main()
    _, _, _, cmd_id = reaper.get_action_context()
    reaper.SetToggleCommandState(0, cmd_id, 1)
    reaper.RefreshToolbar2(0, cmd_id)

    findAndSync_matching_items()
    reaper.defer(main)
end

reaper.defer(main)

local function on_script_exit()
    reaper.SetToggleCommandState(0, cmd_id, 0)
    reaper.RefreshToolbar2(0, cmd_id)
end

reaper.atexit(on_script_exit)