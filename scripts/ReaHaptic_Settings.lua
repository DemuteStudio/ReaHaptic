-- @version 1.0
-- @author Florian Heynen

if not reaper.ImGui_GetBuiltinPath then
    return reaper.MB('ReaImGui is not installed or too old.', 'My script', 0)
end

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.9.3'

local font = ImGui.CreateFont('sans-serif', 13)
local ctx = ImGui.CreateContext('My script')
ImGui.Attach(ctx, font)

-- Define default values
local default_ip = "127.0.0.1"
local default_port = "7401"
local default_color = 0xFFFFFF  -- Default to white

-- Load saved settings or use defaults
local ip = reaper.GetExtState("ReaHapticSettings", "IP")
local port = reaper.GetExtState("ReaHapticSettings", "Port")
local saved_color_hapticsTrack = reaper.GetExtState("ReaHapticSettings", "haptics Track Color")
local saved_color_amplitudeTrack = reaper.GetExtState("ReaHapticSettings", "amplitude Track Color")
local saved_color_frequencyTrack = reaper.GetExtState("ReaHapticSettings", "frequency Track Color")
local saved_color_emphasisTrack = reaper.GetExtState("ReaHapticSettings", "emphasis Track Color")

if ip == "" then ip = default_ip end
if port == "" then port = default_port end

local function getHapticsTrack(name)
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local _, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
        if track_name == name then
            return track
        end
    end
    return nil
end

local function convertRGBtoBGR(rgb_color)
    local r = (rgb_color & 0xFF0000) >> 16
    local g = (rgb_color & 0x00FF00) >> 8
    local b = (rgb_color & 0x0000FF)
    -- Convert to BGR
    return (b << 16) | (g << 8) | r
end

local function setTrackColor(track, color)
    if track then
        reaper.SetMediaTrackInfo_Value(track, "I_CUSTOMCOLOR", convertRGBtoBGR(color) | 0x1000000)
        reaper.UpdateArrange()
    end
end

local function SetTrackColorByName(name, saved_color)
    local track = getHapticsTrack(name)
    if track then
        local changed, new_color  = ImGui.ColorEdit3(ctx, name .. " Track Color", tonumber(saved_color))
        if changed then
            setTrackColor(track, new_color)
            reaper.SetExtState("ReaHapticSettings", name .. "Track Color", tostring(new_color), true)
            return new_color
        end
        return reaper.GetExtState("ReaHapticSettings", name .. "Track Color")
    else
        ImGui.Text(ctx, "No track named 'Haptics' found.")
        return saved_color
    end
end

local function myWindow()
    local rv

    -- IP Input Field
    rv, ip = ImGui.InputText(ctx, 'IP', ip)
    if rv then
        reaper.SetExtState("ReaHapticSettings", "IP", ip, true)
    end

    -- Port Input Field
    rv, port = ImGui.InputText(ctx, 'Port', port)
    if rv then
        reaper.SetExtState("ReaHapticSettings", "Port", port, true)
    end
    -- track color settings
    if ImGui.CollapsingHeader(ctx, " Track Color Settings") then
        saved_color_hapticsTrack = SetTrackColorByName("haptics", saved_color_hapticsTrack)
        saved_color_amplitudeTrack = SetTrackColorByName("amplitude", saved_color_amplitudeTrack)
        saved_color_frequencyTrack = SetTrackColorByName("frequency", saved_color_frequencyTrack)
        saved_color_emphasisTrack = SetTrackColorByName("emphasis", saved_color_emphasisTrack)
    end

    -- Reset Button
    if ImGui.Button(ctx, 'Reset to Defaults') then
        ip = default_ip
        port = default_port
        reaper.SetExtState("ReaHapticSettings", "IP", ip, true)
        reaper.SetExtState("ReaHapticSettings", "Port", port, true)
    end
end

local function loop()
    ImGui.PushFont(ctx, font)
    ImGui.SetNextWindowSize(ctx, 400, 120, ImGui.Cond_FirstUseEver)
    local visible, open = ImGui.Begin(ctx, 'ReaHaptic Settings', true)
    if visible then
        myWindow()
        ImGui.End(ctx)
    end
    ImGui.PopFont(ctx)

    if open then
        reaper.defer(loop)
    end
end

reaper.defer(loop)