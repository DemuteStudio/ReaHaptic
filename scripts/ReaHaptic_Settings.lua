--[[
 * ReaScript Name: ReaHaptic_Settings
 * Description: Reahaptic Settings
 * Author: Florian Heynen
 * Version: 2.0
--]]

if not reaper.ImGui_GetBuiltinPath then
    return reaper.MB('ReaImGui is not installed or too old.', 'My script', 0)
end

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.9.3'

-- Create fonts
local font = ImGui.CreateFont('sans-serif', 13)
local fontBold = ImGui.CreateFont('sans-serif', 13, ImGui.FontFlags_Bold)
local fontSmall = ImGui.CreateFont('sans-serif', 11)
local ctx = ImGui.CreateContext('ReaHaptic Settings')
ImGui.Attach(ctx, font)
ImGui.Attach(ctx, fontBold)
ImGui.Attach(ctx, fontSmall)

-- ── Common shared libraries ────────────────────────────────────────────────

local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])")
local DEMUTE_ROOT = script_path:match("^(.*[/\\])[^/\\]+[/\\]$")
local COMMON      = DEMUTE_ROOT .. "Common/Scripts/"
dofile(COMMON .. "DM_Colors.lua")
dofile(COMMON .. "DM_Theme.lua")
dofile(COMMON .. "DM_StringUtils.lua")
dofile(COMMON .. "DM_ImageUtils.lua")

-- logo
local logo_image, logo_width, logo_height = LoadDemuteLogo()
logo_width  = logo_width  or 0
logo_height = logo_height or 0

-- Color aliases from shared theme
local C = Theme.C

-- Defaults
local default_ip = "127.0.0.1"
local default_port = "7401"
local default_exportPath = ""
local default_hapticType = 0
local default_InportOffset = 1
local default_transientMinSpacing = 0.1
local default_ampMin = 0.0
local default_ampMultiplier = 0.7
local default_lowEndMax = 250
local default_frequencyBlend = 0.3
local default_transientSensitivity = 0.5
local default_envelopeSimplification = 0.1

retval, project_path = reaper.EnumProjects(-1, "")
if retval and project_path ~= "" then
    project_dir = project_path:match("(.*)[/\\]")
    if project_dir then
        default_exportPath = project_dir .. "/RenderedHaptics"
    end
end

-- Load settings
local ip = reaper.GetExtState("ReaHaptics", "IP")
local port = reaper.GetExtState("ReaHaptics", "Port")
local exportPath = reaper.GetExtState("ReaHaptics", "ExportPath")
local selectedIndex = reaper.GetExtState("ReaHaptics", "HapticType")
local InportOffset = reaper.GetExtState("ReaHaptics", "InportOffset")
local transientMinSpacing = tonumber(reaper.GetExtState("ReaHaptics", "TransientMinSpacing")) or default_transientMinSpacing
local ampMin = tonumber(reaper.GetExtState("ReaHaptics", "AmplitudeMin")) or default_ampMin
local lowEndMax = tonumber(reaper.GetExtState("ReaHaptics", "LowEndMax")) or default_lowEndMax
local frequencyBlend = tonumber(reaper.GetExtState("ReaHaptics", "FrequencyBlend")) or default_frequencyBlend
local transientSensitivity = tonumber(reaper.GetExtState("ReaHaptics", "TransientSensitivity")) or default_transientSensitivity
local envelopeSimplification = tonumber(reaper.GetExtState("ReaHaptics", "EnvelopeSimplification")) or default_envelopeSimplification
local ampMultiplier = tonumber(reaper.GetExtState("ReaHaptics", "AmplitudeMultiplier")) or default_ampMultiplier

if ip == "" then ip = default_ip end
if port == "" then port = default_port end
if exportPath == "" then exportPath = default_exportPath end
if selectedIndex == "" then selectedIndex = default_hapticType end
if InportOffset == "" then InportOffset = default_InportOffset end

-- split() is provided by Common/Scripts/DM_StringUtils.lua

local function loadIPList()
    local saved = reaper.GetExtState("ReaHaptics", "IPList")
    if saved == "" then return {default_ip} end
    return split(saved, ",")
end

local function saveIPList(list)
    reaper.SetExtState("ReaHaptics", "IPList", table.concat(list, ","), true)
end

local ip_list = loadIPList()
local new_ip = ""
local current_ip_idx = 0

-- UI Helper: Styled tooltip
local function Tooltip(text)
    if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_DelayShort) then
        ImGui.BeginTooltip(ctx)
        ImGui.PushTextWrapPos(ctx, 300)
        ImGui.TextColored(ctx, C.text_dim, text)
        ImGui.PopTextWrapPos(ctx)
        ImGui.EndTooltip(ctx)
    end
end


-- UI Helper: Parameter row with label and control
local function ParamLabel(label, tooltip)
    ImGui.TableNextRow(ctx)
    ImGui.TableNextColumn(ctx)
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.Text(ctx, label)
    if tooltip then Tooltip(tooltip) end
    ImGui.TableNextColumn(ctx)
end

-- Collapsible section card helpers (OOP ImGui.* API, mirrors Theme.SectionBegin/End)
local _sx0, _sx1 = 0, 0

local function SectionBegin(label, default_open)
    ImGui.Spacing(ctx)
    ImGui.PushStyleColor(ctx, ImGui.Col_Header,        C.child_bg)
    ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered, C.titlebar_act)
    ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive,  0x494949FF)
    ImGui.BeginGroup(ctx)
    if default_open ~= nil then
        ImGui.SetNextItemOpen(ctx, default_open, ImGui.Cond_Once)
    end
    local open = ImGui.CollapsingHeader(ctx, label)
    _sx0, _ = ImGui.GetItemRectMin(ctx)
    _sx1, _ = ImGui.GetItemRectMax(ctx)
    ImGui.PopStyleColor(ctx, 3)
    if open then
        ImGui.Dummy(ctx, 0, 3)
        ImGui.Indent(ctx, 8)
    end
    return open
end

local function SectionEnd(open)
    if open then
        ImGui.Unindent(ctx, 8)
        ImGui.Dummy(ctx, 0, 4)
    end
    ImGui.EndGroup(ctx)
    local _, y0 = ImGui.GetItemRectMin(ctx)
    local _, y1 = ImGui.GetItemRectMax(ctx)
    local dl = ImGui.GetWindowDrawList(ctx)
    ImGui.DrawList_AddRect(dl, _sx0, y0, _sx1, y1, C.border, 4)
end

-- Window-level styling (mirrors Theme.PushWindow for OOP ImGui API)
local function PushWindow()
    ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg,         C.bg)
    ImGui.PushStyleColor(ctx, ImGui.Col_Border,            C.border)
    ImGui.PushStyleColor(ctx, ImGui.Col_TitleBg,           C.titlebar)
    ImGui.PushStyleColor(ctx, ImGui.Col_TitleBgActive,     C.titlebar_act)
    ImGui.PushStyleColor(ctx, ImGui.Col_TitleBgCollapsed,  C.titlebar)
    ImGui.PushStyleVar  (ctx, ImGui.StyleVar_WindowRounding,   10)
    ImGui.PushStyleVar  (ctx, ImGui.StyleVar_WindowBorderSize, 1)
    ImGui.PushStyleVar  (ctx, ImGui.StyleVar_WindowPadding,    16, 6)
end

local function PopWindow()
    ImGui.PopStyleVar  (ctx, 3)
    ImGui.PopStyleColor(ctx, 5)
end

-- Widget-level styling (mirrors Theme.PushUI for OOP ImGui API)
local function PushUI()
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg,           C.input_bg)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered,    C.input_bg_hov)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive,     C.input_bg_act)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button,            C.accent)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered,     C.accent_hov)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive,      C.accent_act)
    ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrab,        C.accent)
    ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrabActive,  C.accent_hov)
    ImGui.PushStyleColor(ctx, ImGui.Col_Header,            C.item_hl)
    ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered,     C.item_hl_hov)
    ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive,      C.item_hl_act)
    ImGui.PushStyleColor(ctx, ImGui.Col_CheckMark,         C.accent)
    ImGui.PushStyleVar  (ctx, ImGui.StyleVar_FrameRounding,  4)
    ImGui.PushStyleVar  (ctx, ImGui.StyleVar_GrabRounding,   4)
    ImGui.PushStyleVar  (ctx, ImGui.StyleVar_FramePadding,   5, 3)
    ImGui.PushStyleVar  (ctx, ImGui.StyleVar_ItemSpacing,    7, 4)
end

local function PopUI()
    ImGui.PopStyleVar  (ctx, 4)
    ImGui.PopStyleColor(ctx, 12)
end

-- Focus border (mirrors Theme.DrawFocusBorder for OOP ImGui API)
local function DrawFocusBorder()
    if ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_RootAndChildWindows) then
        local wx, wy = ImGui.GetWindowPos(ctx)
        local ww, wh = ImGui.GetWindowSize(ctx)
        local dl = ImGui.GetForegroundDrawList(ctx)
        ImGui.DrawList_AddRect(dl, wx, wy, wx + ww, wy + wh, C.focus_border, 10, nil, 2)
    end
end

-- Reset functions for each section
local function ResetNetwork()
    ip = default_ip
    port = default_port
    ip_list = {default_ip}
    current_ip_idx = 0
    new_ip = ""
    reaper.SetExtState("ReaHaptics", "IPList", default_ip, true)
    reaper.SetExtState("ReaHaptics", "IP", default_ip, true)
    reaper.SetExtState("ReaHaptics", "Port", default_port, true)
end

local function ResetImportExport()
    exportPath = default_exportPath
    selectedIndex = default_hapticType
    InportOffset = default_InportOffset
    reaper.SetExtState("ReaHaptics", "ExportPath", default_exportPath, true)
    reaper.SetExtState("ReaHaptics", "HapticType", tostring(default_hapticType), true)
    reaper.SetExtState("ReaHaptics", "InportOffset", tostring(default_InportOffset), true)
end

local function ResetAudioToHaptic()
    ampMin = default_ampMin
    ampMultiplier = default_ampMultiplier
    lowEndMax = default_lowEndMax
    frequencyBlend = default_frequencyBlend
    transientSensitivity = default_transientSensitivity
    transientMinSpacing = default_transientMinSpacing
    envelopeSimplification = default_envelopeSimplification
    reaper.SetExtState("ReaHaptics", "AmplitudeMin", tostring(default_ampMin), true)
    reaper.SetExtState("ReaHaptics", "AmplitudeMultiplier", tostring(default_ampMultiplier), true)
    reaper.SetExtState("ReaHaptics", "LowEndMax", tostring(default_lowEndMax), true)
    reaper.SetExtState("ReaHaptics", "FrequencyBlend", tostring(default_frequencyBlend), true)
    reaper.SetExtState("ReaHaptics", "TransientSensitivity", tostring(default_transientSensitivity), true)
    reaper.SetExtState("ReaHaptics", "TransientMinSpacing", tostring(default_transientMinSpacing), true)
    reaper.SetExtState("ReaHaptics", "EnvelopeSimplification", tostring(default_envelopeSimplification), true)
end

local function ResetAllDefaults()
    ResetNetwork()
    ResetImportExport()
    ResetAudioToHaptic()
end

local function myWindow()
    local rv
    local contentWidth = ImGui.GetContentRegionAvail(ctx)

    -- ── Network ──────────────────────────────────────────────────────────────
    local sec_net = SectionBegin("Network", true)
    if sec_net then
        if ImGui.BeginTable(ctx, "NetworkTable", 2, ImGui.TableFlags_None) then
            ImGui.TableSetupColumn(ctx, "Label", ImGui.TableColumnFlags_WidthFixed, 90)
            ImGui.TableSetupColumn(ctx, "Control", ImGui.TableColumnFlags_WidthStretch)

            ParamLabel("Target IP", "Device IP address for haptic output")
            local ip_combo_str = table.concat(ip_list, "\0") .. "\0"
            ImGui.SetNextItemWidth(ctx, -1)
            rv, current_ip_idx = ImGui.Combo(ctx, "##TargetIP", current_ip_idx, ip_combo_str)
            if rv and ip_list[current_ip_idx + 1] then
                ip = ip_list[current_ip_idx + 1]
                reaper.SetExtState("ReaHaptics", "IP", ip, true)
            end

            ParamLabel("Manage IPs", "Add or remove IP addresses")
            ImGui.SetNextItemWidth(ctx, -77)
            rv, new_ip = ImGui.InputTextWithHint(ctx, "##NewIP", "New IP...", new_ip)
            ImGui.SameLine(ctx)
            if ImGui.Button(ctx, "+##addip", 28, 0) and new_ip ~= "" then
                table.insert(ip_list, new_ip)
                saveIPList(ip_list)
                current_ip_idx = #ip_list - 1
                ip = new_ip
                reaper.SetExtState("ReaHaptics", "IP", ip, true)
                new_ip = ""
            end
            ImGui.SameLine(ctx)
            ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x803030FF)
            ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0xA04040FF)
            if ImGui.Button(ctx, "-##removeip", 28, 0) and #ip_list > 1 then
                table.remove(ip_list, current_ip_idx + 1)
                saveIPList(ip_list)
                if current_ip_idx >= #ip_list then current_ip_idx = #ip_list - 1 end
                ip = ip_list[current_ip_idx + 1]
                reaper.SetExtState("ReaHaptics", "IP", ip, true)
            end
            ImGui.PopStyleColor(ctx, 2)

            ParamLabel("Port", "Network port (Default: 7401)")
            ImGui.SetNextItemWidth(ctx, 80)
            rv, port = ImGui.InputText(ctx, "##Port", port)
            if rv then reaper.SetExtState("ReaHaptics", "Port", port, true) end

            ImGui.EndTable(ctx)
        end
        ImGui.Spacing(ctx)
        ImGui.PushStyleColor(ctx, ImGui.Col_Button,        C.cancel)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, C.cancel_hov)
        if ImGui.SmallButton(ctx, "Reset Network##net") then ResetNetwork() end
        ImGui.PopStyleColor(ctx, 2)
    end
    SectionEnd(sec_net)

    -- ── Import / Export ───────────────────────────────────────────────────────
    local sec_ie = SectionBegin("Import / Export", true)
    if sec_ie then
        if ImGui.BeginTable(ctx, "ImportExportTable", 2, ImGui.TableFlags_None) then
            ImGui.TableSetupColumn(ctx, "Label", ImGui.TableColumnFlags_WidthFixed, 90)
            ImGui.TableSetupColumn(ctx, "Control", ImGui.TableColumnFlags_WidthStretch)

            ParamLabel("Export Path", "Directory for haptic files")
            ImGui.SetNextItemWidth(ctx, -55)
            rv, exportPath = ImGui.InputText(ctx, "##ExportPath", exportPath)
            if rv then reaper.SetExtState("ReaHaptics", "ExportPath", exportPath, true) end
            ImGui.SameLine(ctx)
            if ImGui.Button(ctx, "...", 50, 0) then
                local retval, selectedPath = reaper.JS_Dialog_BrowseForFolder("Select Export Directory", exportPath)
                if retval and selectedPath ~= "" then
                    exportPath = selectedPath
                    reaper.SetExtState("ReaHaptics", "ExportPath", exportPath, true)
                end
            end

            ParamLabel("File Type", "Export format")
            local hapticTypes = ".haptic\0.haps\0"
            selectedIndex = tonumber(reaper.GetExtState("ReaHaptics", "HapticType")) or 0
            ImGui.SetNextItemWidth(ctx, 100)
            rv, selectedIndex = ImGui.Combo(ctx, "##FileType", selectedIndex, hapticTypes)
            if rv then reaper.SetExtState("ReaHaptics", "HapticType", tostring(selectedIndex), true) end

            ParamLabel("Import Offset", "Track index offset for import")
            ImGui.SetNextItemWidth(ctx, 60)
            rv, InportOffset = ImGui.InputText(ctx, "##ImportOffset", tostring(InportOffset))
            if rv then reaper.SetExtState("ReaHaptics", "InportOffset", InportOffset, true) end

            ImGui.EndTable(ctx)
        end
        ImGui.Spacing(ctx)
        ImGui.PushStyleColor(ctx, ImGui.Col_Button,        C.cancel)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, C.cancel_hov)
        if ImGui.SmallButton(ctx, "Reset Import/Export##ie") then ResetImportExport() end
        ImGui.PopStyleColor(ctx, 2)
    end
    SectionEnd(sec_ie)

    -- ── Audio to Haptic ───────────────────────────────────────────────────────
    local sec_a2h = SectionBegin("Audio to Haptic", true)
    if sec_a2h then
        if ImGui.BeginTable(ctx, "AudioParams", 4, ImGui.TableFlags_None) then
            ImGui.TableSetupColumn(ctx, "Label1",    ImGui.TableColumnFlags_WidthFixed,   95)
            ImGui.TableSetupColumn(ctx, "Control1",  ImGui.TableColumnFlags_WidthStretch)
            ImGui.TableSetupColumn(ctx, "Label2",    ImGui.TableColumnFlags_WidthFixed,   95)
            ImGui.TableSetupColumn(ctx, "Control2",  ImGui.TableColumnFlags_WidthStretch)

            ImGui.TableNextRow(ctx)
            ImGui.TableNextColumn(ctx) ImGui.TextColored(ctx, C.accent, "Amplitude")
            ImGui.TableNextColumn(ctx)
            ImGui.TableNextColumn(ctx) ImGui.TextColored(ctx, C.accent, "Frequency")
            ImGui.TableNextColumn(ctx)

            ImGui.TableNextRow(ctx)
            ImGui.TableNextColumn(ctx) ImGui.AlignTextToFramePadding(ctx) ImGui.Text(ctx, "Min Threshold") Tooltip("Minimum amplitude for output")
            ImGui.TableNextColumn(ctx) ImGui.SetNextItemWidth(ctx, -1)
            rv, ampMin = ImGui.SliderDouble(ctx, "##AmpMin", ampMin, 0.0, 1.0, "%.2f")
            if rv then reaper.SetExtState("ReaHaptics", "AmplitudeMin", tostring(ampMin), true) end
            ImGui.TableNextColumn(ctx) ImGui.AlignTextToFramePadding(ctx) ImGui.Text(ctx, "Low End Max") Tooltip("Bass frequency cutoff (Hz)")
            ImGui.TableNextColumn(ctx) ImGui.SetNextItemWidth(ctx, -1)
            rv, lowEndMax = ImGui.SliderDouble(ctx, "##LowEndMax", lowEndMax, 100, 500, "%.0f Hz")
            if rv then reaper.SetExtState("ReaHaptics", "LowEndMax", tostring(lowEndMax), true) end

            ImGui.TableNextRow(ctx)
            ImGui.TableNextColumn(ctx) ImGui.AlignTextToFramePadding(ctx) ImGui.Text(ctx, "Multiplier") Tooltip("Intensity scale factor")
            ImGui.TableNextColumn(ctx) ImGui.SetNextItemWidth(ctx, -1)
            rv, ampMultiplier = ImGui.SliderDouble(ctx, "##AmpMult", ampMultiplier, 0.0, 2.0, "%.2f")
            if rv then reaper.SetExtState("ReaHaptics", "AmplitudeMultiplier", tostring(ampMultiplier), true) end
            ImGui.TableNextColumn(ctx) ImGui.AlignTextToFramePadding(ctx) ImGui.Text(ctx, "Freq Blend") Tooltip("0=Bass, 1=Full spectrum")
            ImGui.TableNextColumn(ctx) ImGui.SetNextItemWidth(ctx, -1)
            rv, frequencyBlend = ImGui.SliderDouble(ctx, "##FreqBlend", frequencyBlend, 0.0, 1.0, "%.2f")
            if rv then reaper.SetExtState("ReaHaptics", "FrequencyBlend", tostring(frequencyBlend), true) end

            ImGui.TableNextRow(ctx)
            ImGui.TableNextColumn(ctx) ImGui.TextColored(ctx, C.accent, "Transients")
            ImGui.TableNextColumn(ctx)
            ImGui.TableNextColumn(ctx) ImGui.TextColored(ctx, C.accent, "Envelope")
            ImGui.TableNextColumn(ctx)

            ImGui.TableNextRow(ctx)
            ImGui.TableNextColumn(ctx) ImGui.AlignTextToFramePadding(ctx) ImGui.Text(ctx, "Sensitivity") Tooltip("0=Strong only, 1=Subtle")
            ImGui.TableNextColumn(ctx) ImGui.SetNextItemWidth(ctx, -1)
            rv, transientSensitivity = ImGui.SliderDouble(ctx, "##TransSens", transientSensitivity, 0.0, 1.0, "%.2f")
            if rv then reaper.SetExtState("ReaHaptics", "TransientSensitivity", tostring(transientSensitivity), true) end
            ImGui.TableNextColumn(ctx) ImGui.AlignTextToFramePadding(ctx) ImGui.Text(ctx, "Simplification") Tooltip("0=Keep all, 1=Max reduce")
            ImGui.TableNextColumn(ctx) ImGui.SetNextItemWidth(ctx, -1)
            rv, envelopeSimplification = ImGui.SliderDouble(ctx, "##EnvSimp", envelopeSimplification, 0.0, 1.0, "%.2f")
            if rv then reaper.SetExtState("ReaHaptics", "EnvelopeSimplification", tostring(envelopeSimplification), true) end

            ImGui.TableNextRow(ctx)
            ImGui.TableNextColumn(ctx) ImGui.AlignTextToFramePadding(ctx) ImGui.Text(ctx, "Min Spacing") Tooltip("Min time between transients (s)")
            ImGui.TableNextColumn(ctx) ImGui.SetNextItemWidth(ctx, -1)
            rv, transientMinSpacing = ImGui.InputDouble(ctx, "##MinSpacing", transientMinSpacing, 0.01, 0.1, "%.2f s")
            if rv then reaper.SetExtState("ReaHaptics", "TransientMinSpacing", tostring(transientMinSpacing), true) end
            ImGui.TableNextColumn(ctx) ImGui.TableNextColumn(ctx)

            ImGui.EndTable(ctx)
        end
        ImGui.Spacing(ctx)
        ImGui.PushStyleColor(ctx, ImGui.Col_Button,        C.cancel)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, C.cancel_hov)
        if ImGui.SmallButton(ctx, "Reset Audio to Haptic##a2h") then ResetAudioToHaptic() end
        ImGui.PopStyleColor(ctx, 2)
    end
    SectionEnd(sec_a2h)

    -- SECTION: Logo (pinned to bottom)
    if logo_image then
        local logo_display_width = 120
        local logo_display_height = logo_display_width * (logo_height / logo_width)

        -- Get window dimensions
        local windowHeight = ImGui.GetWindowHeight(ctx)
        local windowWidth = ImGui.GetContentRegionAvail(ctx)
        local windowPadding = 8  -- Bottom padding

        -- Position at bottom of window
        local bottomY = windowHeight - logo_display_height - windowPadding - 25  -- 25 for title bar
        local currentY = ImGui.GetCursorPosY(ctx)

        -- Only move down if we need to (content doesn't fill window)
        if bottomY > currentY then
            ImGui.SetCursorPosY(ctx, bottomY)
        end

        -- Center horizontally and draw
        ImGui.SetCursorPosX(ctx, (windowWidth - logo_display_width) / 2 + 12)
        ImGui.Image(ctx, logo_image, logo_display_width, logo_display_height)
    end

    ImGui.SameLine(ctx, contentWidth - 70)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, C.cancel)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, C.cancel_hov)
    if ImGui.Button(ctx, "Reset All", 70, 0) then
        ResetAllDefaults()
    end
    Tooltip("Reset all settings to defaults")
    ImGui.PopStyleColor(ctx, 2)
end

local function loop()
    ImGui.PushFont(ctx, font)
    ImGui.SetNextWindowSize(ctx, 540, 480, ImGui.Cond_FirstUseEver)

    PushWindow()
    local visible, open = ImGui.Begin(ctx, 'ReaHaptic Settings', true)
    PopWindow()

    if visible then
        DrawFocusBorder()
        PushUI()
        myWindow()
        PopUI()
        ImGui.End(ctx)
    end

    ImGui.PopFont(ctx)

    if open then
        reaper.defer(loop)
    end
end

reaper.defer(loop)
