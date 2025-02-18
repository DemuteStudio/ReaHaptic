-- @version 1.0
-- @author Florian Heynen

-- Load the socket module
local opsys = reaper.GetOS()
local extension 
if opsys:match('Win') then
  extension = 'dll'
else -- Linux and Macos
  extension = 'so'
end

--dofile("C:/Users/DEMUTE-PROG2/Reaper_Scripts/HapticsFunctionsLuaLibrary.lua")

local info = debug.getinfo(1, 'S');
local resourcePath = reaper.GetResourcePath()
package.cpath = package.cpath .. ";" .. resourcePath .. "/Scripts/ReaHaptic/LUA Sockets/socket module/?."..extension  -- Add current folder/socket module for looking at .dll (need for loading basic luasocket)
package.path = package.path .. ";" .. resourcePath .. "/Scripts/Reahaptic/LUA Sockets/socket module/?.lua" -- Add current folder/socket module for looking at .lua ( Only need for loading the other functions packages lua osc.lua, url.lua etc... You can change those files path and update this line)ssssssssssssssssssssssssssssssssssss

--loadfile(resourcePath .. "/Scripts/Reahaptic/HapticsFunctionsLuaLibrary.lua")()
loadfile("HapticsFunctionsLuaLibrary.lua")()

-- Get socket and osc modules
local socket = require('socket.core')
local osc = require('osc')

-- Define and save the ip, port
local host = "localhost"
local port = reaper.c("ReaHaptics", "LastPort")
local ip = reaper.GetExtState("ReaHaptics", "LastIPAddress")
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
