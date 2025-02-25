--[[
 * ReaScript Name: ReaHaptic_DeleteSelectedHaptic
 * Description: deletes  the selected haptic files.
 * Author: Florian Heynen
 * Version: 1.0
--]]

function delete_automation_items_in_range(envelope, start_time, end_time)
    if not envelope then return end

    local num_auto_items = reaper.CountAutomationItems(envelope)
    for i = num_auto_items - 1, 0, -1 do 
        local item_start = reaper.GetSetAutomationItemInfo(envelope, i, "D_POSITION", 0, false)
        local item_length = reaper.GetSetAutomationItemInfo(envelope, i, "D_LENGTH", 0, false)
        local item_end = item_start + item_length

        if item_start >= start_time and item_start <= end_time then
            reaper.GetSetAutomationItemInfo(envelope, i, "D_UISEL", 1, true) -- Select the automation item
        end
    end
    reaper.Main_OnCommand(42086, 0) -- "Remove selected automation items"
end

local function deleteItem(item)
	if not item then return end
	local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
	local itemLength = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
	local itemEnd = itemStart + itemLength

	local track = reaper.GetMediaItemTrack(item)
	if not track then return end

	local envelope = reaper.GetTrackEnvelopeByName(track, "Pan")
    local _,name = reaper.GetTrackName(track)

	if envelope then
		reaper.DeleteEnvelopePointRange(envelope, itemStart - 0.001, itemEnd)
        delete_automation_items_in_range(envelope, itemStart, itemEnd)
	end

	reaper.DeleteTrackMediaItem(track, item)
end

function findAndDelete_matching_items()
    local num_selected_items = reaper.CountSelectedMediaItems(0)
    
    for i = num_selected_items - 1, 0, -1 do
        local reference_item = reaper.GetSelectedMediaItem(0, i)
        if reference_item ~= nil then
            reference_groupId = reaper.GetMediaItemInfo_Value(reference_item, "I_GROUPID")
            
            local num_items = reaper.CountMediaItems(0)
            for i = num_items - 1, 0, -1 do
                local item = reaper.GetMediaItem(0, i)
                if item ~= nil then
                    if item ~= reference_item then
                        item_groupId = reaper.GetMediaItemInfo_Value(item, "I_GROUPID")
                        if item_groupId == reference_groupId then
                            deleteItem(item)
                        end
                    end
                end
            end
            deleteItem(reference_item)
        end
    end
    reaper.UpdateArrange()
end

function main()
    findAndDelete_matching_items()
end

main()