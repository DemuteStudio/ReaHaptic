--[[
 * ReaScript Name: ReaHaptic_DeleteSelectedHaptic
 * Description: deletes  the selected haptic files.
 * Author: Florian Heynen
 * Version: 1.0
--]]

function rename_selected_item(item, new_name)
    -- Get the current item name (stored in item notes)
    local _, current_name = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
    
    if new_name ~= "" then
        reaper.GetSetMediaItemInfo_String(item, "P_NOTES", new_name, true) -- Set new name
        reaper.UpdateArrange() -- Refresh arrange view
    end
end

function findAndRename_matching_items()
    local num_selected_items = reaper.CountSelectedMediaItems(0)
    
    for i = 0, num_selected_items - 1 do
        local reference_item = reaper.GetSelectedMediaItem(0, i)
        if reference_item ~= nil then
            reference_groupId = reaper.GetMediaItemInfo_Value(reference_item, "I_GROUPID")
            local _, current_name = reaper.GetSetMediaItemInfo_String(reference_item, "P_NOTES", "", false)
            local retval, new_name = reaper.GetUserInputs("Rename Item", 1, "New name:", current_name or "")
            local num_items = reaper.CountMediaItems(0)
            -- Iterate backwards to avoid index-shifting issues
            for i = num_items - 1, 0, -1 do
                local item = reaper.GetMediaItem(0, i)
                if item ~= nil then
                    if item ~= reference_item then -- Skip the reference item
                        item_groupId = reaper.GetMediaItemInfo_Value(item, "I_GROUPID")
                        if item_groupId == reference_groupId then
                            rename_selected_item(item,new_name)
                        end
                    end
                end
            end
            rename_selected_item(reference_item,new_name)
        end
        return
    end
    reaper.UpdateArrange()
end

-- Main loop
function main()
    findAndRename_matching_items()
end

main()