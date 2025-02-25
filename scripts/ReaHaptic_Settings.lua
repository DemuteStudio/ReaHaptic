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

if ip == "" then ip = default_ip end
if port == "" then port = default_port end
if exportPath == "" then exportPath = default_exportPath end
if selectedIndex == "" then selectedIndex = default_hapticType end
if InportOffset == "" then InportOffset = default_InportOffset end

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

    ImGui.Text(ctx, "OSC Settings")
    rv, ip = ImGui.InputText(ctx, 'IP', ip)
    if rv then
        reaper.SetExtState("ReaHaptics", "IP", ip, true)
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
    if ImGui.Button(ctx, 'Reset to Defaults') then
        ip = default_ip
        port = default_port
        exportPath = default_exportPath
        selectedIndex = default_hapticType

        reaper.SetExtState("ReaHaptics", "IP", ip, true)
        reaper.SetExtState("ReaHaptics", "Port", port, true)
        reaper.SetExtState("ReaHaptics", "HapticType", selectedIndex, true)
        reaper.SetExtState("ReaHaptics", "ExportPath", exportPath, true)
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