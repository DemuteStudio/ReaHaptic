
-- Load the socket module
local opsys = reaper.GetOS()
local extension 
if opsys:match('Win') then
  extension = 'dll'
else -- Linux and Macos
  extension = 'so'
end

local info = debug.getinfo(1, 'S');
local resourcePath = reaper.GetResourcePath()
package.cpath = package.cpath .. ";" .. resourcePath .. "/Scripts/ReaHaptic/LUA Sockets/socket module/?."..extension  -- Add current folder/socket module for looking at .dll (need for loading basic luasocket)
package.path = package.path .. ";" .. resourcePath .. "/Scripts/Reahaptic/LUA Sockets/socket module/?.lua" -- Add current folder/socket module for looking at .lua ( Only need for loading the other functions packages lua osc.lua, url.lua etc... You can change those files path and update this line)ssssssssssssssssssssssssssssssssssss

loadfile(.. "ReaHaptic_FunctionsLibrary.lua")()

--TEMP CHANGES
local function getCurrentScriptDirectory()
  local info = debug.getinfo(1, 'S')
  local scriptPath = info.source:match("@(.*)$")
  return scriptPath:match("(.*[/\\])")
end

local scriptDirectory = getCurrentScriptDirectory()
local libraryPath = scriptDirectory .. "ReaHaptic_FunctionsLibrary.lua"
local loadLibrary = loadfile(libraryPath)
-- END TEMP CHANGES

local selected_file_type = ".haptic"

-- Get socket and osc modules
local socket = require('socket.core')
local osc = require('osc')

-- Define and save the ip, port
local host = "localhost"
local port = reaper.GetExtState("ReaHaptics", "Port")
local ip = reaper.GetExtState("ReaHaptics", "IPAddress")
if ip == "" then
  ip = getEthernetIP()
end
if port == "" then
  port = '7401'
end

local udp = assert(socket.udp())
local haptic_name = "reaper_haptic"

function getSelectedHapticData()
	local project_dir = get_project_dir()

	local selected_items = get_selected_media_items()
    local nrOfItems = 0
	for _, item in ipairs(selected_items) do
        nrOfItems = nrOfItems + 1
		local start_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
		local end_pos = start_pos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
		local item_name = "reaper_haptic"
		local take = reaper.GetMediaItemTake(item, 0)
		local track = reaper.GetMediaItem_Track(item)
		local _, track_name = reaper.GetTrackName(track, "")

		if track_name == "haptics" then
			if not item_name then
				if take then
					local _, take_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
					item_name = take_name
				end
			end
            haptic_name = get_item_notes(item)
            local hapticData = process_HapticItem(start_pos, end_pos, item_name)
			return hapticData
		end
	end
    if nrOfItems > 0 then
        reaper.ShowConsoleMsg("No Items Selected, please select a item on the haptics track.\n")
    else
        reaper.ShowConsoleMsg("No Items Selected on the haptics track.\n")
    end
    return ""
end

function main()
    local Adress = '/InstantHapticJson'
    local hapticData = getSelectedHapticData()
    if hapticData ~= "" then
        local HapticDataWithName = "name: " .. haptic_name .. "\n" .. hapticData
        reaper.ShowMessageBox(HapticDataWithName, "Data Output", 0)

        send_OSC_message(Adress, HapticDataWithName, ip , port, udp)
    end
end

main()