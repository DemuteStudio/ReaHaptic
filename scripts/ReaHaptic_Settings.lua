--[[
 * ReaScript Name: ReaHaptic_Settings
 * Description: Reahaptic Settings
 * Author: Florian Heynen
 * Version: 1.0
--]]

if not reaper.ImGui_GetBuiltinPath then
    return reaper.MB('ReaImGui is not installed or too old.', 'My script', 0)
end

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.9.3'

local font = ImGui.CreateFont('sans-serif', 13)
local ctx = ImGui.CreateContext('My script')
ImGui.Attach(ctx, font)

local default_ip = "127.0.0.1"
local default_port = "7401"
local default_color = 0xFFFFFF
local default_exportPath = ""
local default_hapticType = 0
local default_InportOffset = 1
local default_transientThreshold = 0.2
local default_transientMinSpacing = 0.1
local default_ampMin = 0.0
local default_ampMax = 1.0
local default_freqMin = 20
local default_freqMax = 20000
retval, project_path = reaper.EnumProjects(-1, "")

if retval and project_path ~= "" then
    project_dir = project_path:match("(.*)[/\\]") 
    if project_dir then
        default_exportPath = project_dir .. "/RenderedHaptics"
    else
        reaper.ShowConsoleMsg("Error: Could not determine project directory.\n")
    end
else
    reaper.ShowConsoleMsg("Error: Project not saved yet.\n")
end

local ip = reaper.GetExtState("ReaHaptics", "IP")
local port = reaper.GetExtState("ReaHaptics", "Port")
local exportPath = reaper.GetExtState("ReaHaptics", "ExportPath")
local saved_color_hapticsTrack = reaper.GetExtState("ReaHaptics", "haptics Track Color")
local saved_color_amplitudeTrack = reaper.GetExtState("ReaHaptics", "amplitude Track Color")
local saved_color_frequencyTrack = reaper.GetExtState("ReaHaptics", "frequency Track Color")
local saved_color_emphasisTrack = reaper.GetExtState("ReaHaptics", "emphasis Track Color")
local selectedIndex = reaper.GetExtState("ReaHaptics", "HapticType")
local InportOffset = reaper.GetExtState("ReaHaptics", "InportOffset")
local transientThreshold = tonumber(reaper.GetExtState("ReaHaptics", "TransientThreshold")) or default_transientThreshold
local transientMinSpacing = tonumber(reaper.GetExtState("ReaHaptics", "TransientMinSpacing")) or default_transientMinSpacing
local ampMin = tonumber(reaper.GetExtState("ReaHaptics", "AmplitudeMin")) or default_ampMin
local ampMax = tonumber(reaper.GetExtState("ReaHaptics", "AmplitudeMax")) or default_ampMax
local freqMin = tonumber(reaper.GetExtState("ReaHaptics", "FrequencyMin")) or default_freqMin
local freqMax = tonumber(reaper.GetExtState("ReaHaptics", "FrequencyMax")) or default_freqMax

if ip == "" then ip = default_ip end
if port == "" then port = default_port end
if exportPath == "" then exportPath = default_exportPath end
if selectedIndex == "" then selectedIndex = default_hapticType end
if InportOffset == "" then InportOffset = default_InportOffset end

-- Split a string by delimiter
local function split(str, delimiter)
    local result = {}
    for match in (str .. delimiter):gmatch("(.-)" .. delimiter) do
        table.insert(result, match)
    end
    return result
end

-- Load IP list
local function loadIPList()
    local saved = reaper.GetExtState("ReaHaptics", "IPList")
    if saved == "" then return {default_ip} end
    return split(saved, ",")
end

-- Save IP list
local function saveIPList(ip_list)
    reaper.SetExtState("ReaHaptics", "IPList", table.concat(ip_list, ","), true)
end

local ip_list = loadIPList()
local new_ip = "" -- For adding new IP

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
            reaper.SetExtState("ReaHaptics", name .. "Track Color", tostring(new_color), true)
            return new_color
        end
        return reaper.GetExtState("ReaHaptics", name .. "Track Color")
    else
        ImGui.Text(ctx, "No track named 'Haptics' found.")
        return saved_color
    end
end

local function myWindow()
    local rv

    ImGui.Text(ctx, "Saved IP Addresses:")
    for i, addr in ipairs(ip_list) do
        ImGui.Text(ctx, addr)
        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, "Delete##" .. i) then
            table.remove(ip_list, i)
            saveIPList(ip_list)
        end
    end

    ImGui.Separator(ctx)
    local rv
    rv, new_ip = ImGui.InputText(ctx, "Add IP", new_ip)
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Add") and new_ip ~= "" then
        table.insert(ip_list, new_ip)
        saveIPList(ip_list)
        new_ip = ""
    end


    rv, port = ImGui.InputText(ctx, 'Port', port)
    if rv then
        reaper.SetExtState("ReaHaptics", "Port", port, true)
    end

    ImGui.Text(ctx, "Import/Export Settings")
    rv, InportOffset = ImGui.InputText(ctx, 'Inport Offset', InportOffset)
    if rv then
        reaper.SetExtState("ReaHaptics", "InportOffset", InportOffset, true)
    end
    rv, exportPath = ImGui.InputText(ctx, 'Export path', exportPath)
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Browse") then
        local retval, selectedPath = reaper.JS_Dialog_BrowseForFolder("Select Export Directory", exportPath)
        if retval and selectedPath ~= "" then
            exportPath = selectedPath
            reaper.SetExtState("ReaHaptics", "ExportPath", exportPath, true)
        end
    end
    local hapticTypesTable = {".Haptic", ".haps"}
    local hapticTypes = ".Haptic\0.haps\0"
    selectedIndex = reaper.GetExtState("ReaHaptics", "HapticType")
    selectedIndex = tonumber(selectedIndex)
    if not selectedIndex or selectedIndex ~= math.floor(selectedIndex) then
        selectedIndex = 0
    end
    rv, selectedIndex = reaper.ImGui_Combo(ctx, "Haptic Type", selectedIndex, hapticTypes)
    
    if rv then
        reaper.SetExtState("ReaHaptics", "HapticType", selectedIndex, true)
    end

    ImGui.Text(ctx, "Misc")
    if ImGui.CollapsingHeader(ctx, " Track Color Settings") then
        saved_color_hapticsTrack = SetTrackColorByName("haptics", saved_color_hapticsTrack)
        saved_color_amplitudeTrack = SetTrackColorByName("amplitude", saved_color_amplitudeTrack)
        saved_color_frequencyTrack = SetTrackColorByName("frequency", saved_color_frequencyTrack)
        saved_color_emphasisTrack = SetTrackColorByName("emphasis", saved_color_emphasisTrack)
    end

    ImGui.Text(ctx, "Audio to haptic")
    -- Amplitude Range
    rv, ampMin = ImGui.SliderDouble(ctx, "Amplitude Min", ampMin, 0.0, 1)
    if rv then reaper.SetExtState("ReaHaptics", "AmplitudeMin", tostring(ampMin), true) end

    rv, ampMax = ImGui.SliderDouble(ctx, "Amplitude Max", ampMax, 0, 1.0)
    if rv then reaper.SetExtState("ReaHaptics", "AmplitudeMax", tostring(ampMax), true) end

    -- Frequency Range
    rv, freqMin = ImGui.SliderDouble(ctx, "Frequency Min (Hz)", freqMin, 20, 20)
    if rv then reaper.SetExtState("ReaHaptics", "FrequencyMin", tostring(freqMin), true) end

    rv, freqMax = ImGui.SliderDouble(ctx, "Frequency Max (Hz)", freqMax, 20, 20000)
    if rv then reaper.SetExtState("ReaHaptics", "FrequencyMax", tostring(freqMax), true) end

    rv, transientThreshold = ImGui.InputDouble(ctx, "Transient Threshold", transientThreshold or 0.2, 0.01, 1.0, "%.2f")
    if rv then
        reaper.SetExtState("ReaHaptics", "TransientThreshold", tostring(transientThreshold), true)
    end
    rv, transientMinSpacing = ImGui.InputDouble(ctx, "Min Spacing Between Transients", transientMinSpacing or 0.1, 0.01, 1.0, "%.2f")
    if rv then
        reaper.SetExtState("ReaHaptics", "TransientMinSpacing", tostring(transientMinSpacing), true)
    end

    if ImGui.Button(ctx, 'Reset to Defaults') then
        ip = default_ip
        port = default_port
        exportPath = default_exportPath
        selectedIndex = default_hapticType
        transientThreshold = default_transientThreshold
        transientMinSpacing = default_transientMinSpacing
        reaper.SetExtState("ReaHaptics", "IPList", ip, true)
        reaper.SetExtState("ReaHaptics", "Port", port, true)
        reaper.SetExtState("ReaHaptics", "HapticType", selectedIndex, true)
        reaper.SetExtState("ReaHaptics", "ExportPath", exportPath, true)
        reaper.SetExtState("ReaHaptics", "TransientThreshold", tostring(default_transientThreshold), true)
        reaper.SetExtState("ReaHaptics", "TransientMinSpacing", tostring(default_transientMinSpacing), true)
        reaper.SetExtState("ReaHaptics", "AmplitudeMin", tostring(default_ampMin), true)
        reaper.SetExtState("ReaHaptics", "AmplitudeMax", tostring(default_ampMax), true)
        reaper.SetExtState("ReaHaptics", "FrequencyMin", tostring(default_freqMin), true)
        reaper.SetExtState("ReaHaptics", "FrequencyMax", tostring(default_freqMax), true)
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