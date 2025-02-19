--[[
 * ReaScript Name: ReaHaptic_ContinuousSender
 * Description: Sends OSC messages containing the hapticdata when the cursor reaches a haptic Item
 * Author: Florian Heynen
 * Version: 1.3
--]]

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

package.cpath = package.cpath .. ";" .. resourcePath .. "/Scripts/ReaHapticScripts/LUA Sockets/socket module/?."..extension
package.path = package.path .. ";" .. resourcePath .. "/Scripts/ReaHapticScripts/LUA Sockets/socket module/?.lua"

dofile(resourcePath .. "/Scripts/ReaHapticScripts/scripts/ReaHaptic_FunctionsLibrary.lua")

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

-- Get socket and osc modules
local socket = require('socket.core')
local osc = require('osc')

-- Define and save the ip, port
local host = "localhost"
local port = reaper.GetExtState("ReaHaptics", "Port")
local ip = reaper.GetExtState("ReaHaptics", "IP")
if ip == "" then
  ip = Common.getEthernetIP()
end
if port == "" then
  port = '7401'
end

local udp = assert(socket.udp())
local isInPlayback = false
local prevPlayPos = reaper.GetPlayPosition()
local canPlayHaptic = false

function set_playback(startStopAdress)
    if (reaper.GetPlayState() & 1) == 1 then
        if isInPlayback == false then
            send_OSC_message(startStopAdress, "started", ip, port, udp)
            canPlayHaptic = true
        end
        isInPlayback = true
    else
        if isInPlayback == true then
            send_OSC_message(startStopAdress, "stopped", ip, port, udp)
            canPlayHaptic = false
        end
        isInPlayback = false
    end
end

function check_cursor_movement(startStopAdress)
    local currentPlayPos = get_position()
    if isInPlayback then
        if math.abs(currentPlayPos - prevPlayPos) > 0.1 then  -- Adjust threshold as needed
            send_OSC_message(startStopAdress, "moved", ip, port, udp)
            canPlayHaptic = true
        end 
    end
    prevPlayPos = currentPlayPos
end

function main()
    local HapicsAdress = '/HapticJson'
    local TimeAdress = '/CursorPos'
    local startStopAdress = '/StartStop'
    local cursorPos = get_position()
    set_playback(startStopAdress)
    check_cursor_movement(startStopAdress)
    local lookaheadTime = 0.1  -- 100ms lookahead
    
    -- Get the track named "haptics"
    local trackCount = reaper.CountTracks(0)
    local hapticsTrack = nil
    for i = 0, reaper.CountTracks(0)-1 do
        local currentTrack = reaper.GetTrack(0, i)
        local _, trackName = reaper.GetTrackName(currentTrack)
        if trackName == "haptics" then
            hapticsTrack = currentTrack
        end
    end
    
    if hapticsTrack then
        local isInItem = false
        local itemCount = reaper.CountTrackMediaItems(hapticsTrack)
        for i = 0, itemCount - 1 do
            local item = reaper.GetTrackMediaItem(hapticsTrack, i)
            local itemPos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local itemLength = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            local item_name = get_item_notes(item)
            local end_pos = itemPos + itemLength
            if end_pos > cursorPos + lookaheadTime and itemPos < cursorPos + lookaheadTime then
                if canPlayHaptic then
                    local isInsideItem = false
                    if itemPos < cursorPos then isInsideItem = true end
                    local start_pos = (isInsideItem) and cursorPos or itemPos
                    local hapticData = process_HapticItem(start_pos, end_pos, item_name, isInsideItem)
                    local HapticDataWithTime = "SendTime: " .. start_pos .. "\n" .. hapticData
                    send_OSC_message(HapicsAdress, HapticDataWithTime, ip, port, udp)
                    --reaper.ShowConsoleMsg(HapticDataWithTime)
                    canPlayHaptic = false
                end
                isInItem = true
                --return
            end
        end
        if isInItem == false then
            canPlayHaptic = true
        end
    end
    if isInPlayback then send_OSC_message(TimeAdress, cursorPos, ip, port, udp) end
    reaper.defer(main)
end


reaper.defer(main)
