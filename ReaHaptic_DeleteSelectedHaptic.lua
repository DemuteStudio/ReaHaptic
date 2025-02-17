
local function deleteItem(item)
	if not item then return end

	-- Get item start and end times
	local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
	local itemLength = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
	local itemEnd = itemStart + itemLength

	-- Get the track that the item is on
	local track = reaper.GetMediaItemTrack(item)
	if not track then return end

	-- Get the pan automation envelope
	local envelope = reaper.GetTrackEnvelopeByName(track, "Pan")
	if envelope then
		-- Remove envelope points between item start and end times
		reaper.DeleteEnvelopePointRange(envelope, itemStart, itemEnd)
	end

	-- Delete the item
	reaper.DeleteTrackMediaItem(track, item)
end

function findAndDelete_matching_items()
    local num_selected_items = reaper.CountSelectedMediaItems(0)
    
    for i = 0, num_selected_items - 1 do
        local reference_item = reaper.GetSelectedMediaItem(0, i)
        if reference_item ~= nil then
            reference_groupId = reaper.GetMediaItemInfo_Value(reference_item, "I_GROUPID")
            
            local num_items = reaper.CountMediaItems(0)
            -- Iterate backwards to avoid index-shifting issues
            for i = num_items - 1, 0, -1 do
                local item = reaper.GetMediaItem(0, i)
                if item ~= nil then
                    if item ~= reference_item then -- Skip the reference item
                        item_groupId = reaper.GetMediaItemInfo_Value(item, "I_GROUPID")
                        if item_groupId == reference_groupId then
                            deleteItem(item)
                        end
                    end
                end
            end
            local track = reaper.GetMediaItemTrack(reference_item)
            reaper.DeleteTrackMediaItem(track, reference_item)
        end
    end
    reaper.UpdateArrange()
end

-- Main loop
function main()
    findAndDelete_matching_items()
end

main()