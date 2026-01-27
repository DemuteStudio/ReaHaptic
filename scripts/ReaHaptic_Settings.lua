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

-- logo
local logo_image = nil
local logo_width = 0
local logo_height = 0

-- Load logo (call once during initialization)
local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])")
local function LoadLogo()
    local logo_path = script_path .. "../images/Demute_Home_Logo.png"  -- Or wherever your logo is
    logo_image = reaper.ImGui_CreateImage(logo_path)
    if logo_image then
        logo_width, logo_height = reaper.ImGui_Image_GetSize(logo_image)
    end
end
LoadLogo()

-- Color palette
local colors = {
    accent = 0x4A9FFFFF,
    accentHover = 0x6BB3FFFF,
    accentDark = 0x3A7FDFFF,
    headerBg = 0x2A2A2AFF,
    sectionBg = 0x1E1E1EFF,
    border = 0x3A3A3AFF,
    text = 0xE0E0E0FF,
    textDim = 0x808080FF,
    resetBtn = 0x404040FF,
    resetBtnHover = 0x505050FF,
}

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

-- Helper functions
local function split(str, delimiter)
    local result = {}
    for match in (str .. delimiter):gmatch("(.-)" .. delimiter) do
        table.insert(result, match)
    end
    return result
end

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
        ImGui.TextColored(ctx, colors.textDim, text)
        ImGui.PopTextWrapPos(ctx)
        ImGui.EndTooltip(ctx)
    end
end

-- UI Helper: Section header with reset button
local function SectionHeader(label, contentWidth)
    ImGui.PushFont(ctx, fontBold)
    ImGui.TextColored(ctx, colors.accent, label)
    ImGui.PopFont(ctx)

    -- Reset button on the right
    ImGui.SameLine(ctx, contentWidth - 45)
    ImGui.PushFont(ctx, fontSmall)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, colors.resetBtn)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, colors.resetBtnHover)
    local resetClicked = ImGui.SmallButton(ctx, "Reset##" .. label)
    ImGui.PopStyleColor(ctx, 2)
    ImGui.PopFont(ctx)
    Tooltip("Reset " .. label .. " to defaults")

    return resetClicked
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

-- UI Helper: Begin a card-style section
local function BeginCard()
    ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, 0x252525FF)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ChildRounding, 2)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ChildBorderSize, 1)
    ImGui.PushStyleColor(ctx, ImGui.Col_Border, colors.border)
end

local function EndCard()
    ImGui.PopStyleColor(ctx, 2)
    ImGui.PopStyleVar(ctx, 2)
end

-- Apply custom styling
local function PushStyle()
    ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, 0x1A1A1AFF)
    ImGui.PushStyleColor(ctx, ImGui.Col_TitleBg, colors.headerBg)
    ImGui.PushStyleColor(ctx, ImGui.Col_TitleBgActive, colors.headerBg)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0x303030FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, 0x404040FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, 0x505050FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, colors.accent)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, colors.accentHover)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, colors.accentDark)
    ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrab, colors.accent)
    ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrabActive, colors.accentHover)
    ImGui.PushStyleColor(ctx, ImGui.Col_Header, 0x303030FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered, 0x404040FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive, 0x505050FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_Separator, colors.border)

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 2)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_GrabRounding, 2)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, 3)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 8, 6)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, 10, 8)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 12, 8)
end

local function PopStyle()
    ImGui.PopStyleVar(ctx, 6)
    ImGui.PopStyleColor(ctx, 15)
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

    -- ═══════════════════════════════════════════════════════════════
    -- NETWORK SECTION
    -- ═══════════════════════════════════════════════════════════════
    if SectionHeader("Network", contentWidth) then
        ResetNetwork()
    end

    BeginCard()
    if ImGui.BeginChild(ctx, "NetworkCard", -1, 95, ImGui.ChildFlags_Border) then
        if ImGui.BeginTable(ctx, "NetworkTable", 2, ImGui.TableFlags_None) then
            ImGui.TableSetupColumn(ctx, "Label", ImGui.TableColumnFlags_WidthFixed, 90)
            ImGui.TableSetupColumn(ctx, "Control", ImGui.TableColumnFlags_WidthStretch)

            -- Target IP
            ParamLabel("Target IP", "Device IP address for haptic output")
            local ip_combo_str = table.concat(ip_list, "\0") .. "\0"
            ImGui.SetNextItemWidth(ctx, -1)
            rv, current_ip_idx = ImGui.Combo(ctx, "##TargetIP", current_ip_idx, ip_combo_str)
            if rv and ip_list[current_ip_idx + 1] then
                ip = ip_list[current_ip_idx + 1]
                reaper.SetExtState("ReaHaptics", "IP", ip, true)
            end

            -- Add/Remove IP
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

            -- Port
            ParamLabel("Port", "Network port (Default: 7401)")
            ImGui.SetNextItemWidth(ctx, 80)
            rv, port = ImGui.InputText(ctx, "##Port", port)
            if rv then reaper.SetExtState("ReaHaptics", "Port", port, true) end

            ImGui.EndTable(ctx)
        end
        ImGui.EndChild(ctx)
    end
    EndCard()

    -- ═══════════════════════════════════════════════════════════════
    -- IMPORT/EXPORT SECTION
    -- ═══════════════════════════════════════════════════════════════
    if SectionHeader("Import / Export", contentWidth) then
        ResetImportExport()
    end

    BeginCard()
    if ImGui.BeginChild(ctx, "ImportExportCard", -1, 95, ImGui.ChildFlags_Border) then
        if ImGui.BeginTable(ctx, "ImportExportTable", 2, ImGui.TableFlags_None) then
            ImGui.TableSetupColumn(ctx, "Label", ImGui.TableColumnFlags_WidthFixed, 90)
            ImGui.TableSetupColumn(ctx, "Control", ImGui.TableColumnFlags_WidthStretch)

            -- Export Path
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

            -- File Type
            ParamLabel("File Type", "Export format")
            local hapticTypes = ".haptic\0.haps\0"
            selectedIndex = tonumber(reaper.GetExtState("ReaHaptics", "HapticType")) or 0
            ImGui.SetNextItemWidth(ctx, 100)
            rv, selectedIndex = ImGui.Combo(ctx, "##FileType", selectedIndex, hapticTypes)
            if rv then reaper.SetExtState("ReaHaptics", "HapticType", tostring(selectedIndex), true) end

            -- Import Offset
            ParamLabel("Import Offset", "Track index offset for import")
            ImGui.SetNextItemWidth(ctx, 60)
            rv, InportOffset = ImGui.InputText(ctx, "##ImportOffset", tostring(InportOffset))
            if rv then reaper.SetExtState("ReaHaptics", "InportOffset", InportOffset, true) end

            ImGui.EndTable(ctx)
        end
        ImGui.EndChild(ctx)
    end
    EndCard()

    -- ═══════════════════════════════════════════════════════════════
    -- AUDIO TO HAPTIC SECTION
    -- ═══════════════════════════════════════════════════════════════
    if SectionHeader("Audio to Haptic", contentWidth) then
        ResetAudioToHaptic()
    end

    BeginCard()
    if ImGui.BeginChild(ctx, "AudioToHapticCard", -1, 195, ImGui.ChildFlags_Border) then
        if ImGui.BeginTable(ctx, "AudioParams", 4, ImGui.TableFlags_None) then
            ImGui.TableSetupColumn(ctx, "Label1", ImGui.TableColumnFlags_WidthFixed, 95)
            ImGui.TableSetupColumn(ctx, "Control1", ImGui.TableColumnFlags_WidthStretch)
            ImGui.TableSetupColumn(ctx, "Label2", ImGui.TableColumnFlags_WidthFixed, 95)
            ImGui.TableSetupColumn(ctx, "Control2", ImGui.TableColumnFlags_WidthStretch)

            -- Amplitude | Frequency headers
            ImGui.TableNextRow(ctx)
            ImGui.TableNextColumn(ctx)
            ImGui.TextColored(ctx, colors.accent, "Amplitude")
            ImGui.TableNextColumn(ctx)
            ImGui.TableNextColumn(ctx)
            ImGui.TextColored(ctx, colors.accent, "Frequency")
            ImGui.TableNextColumn(ctx)

            -- Min Threshold | Low End Max
            ImGui.TableNextRow(ctx)
            ImGui.TableNextColumn(ctx)
            ImGui.AlignTextToFramePadding(ctx)
            ImGui.Text(ctx, "Min Threshold")
            Tooltip("Minimum amplitude for output")
            ImGui.TableNextColumn(ctx)
            ImGui.SetNextItemWidth(ctx, -1)
            rv, ampMin = ImGui.SliderDouble(ctx, "##AmpMin", ampMin, 0.0, 1.0, "%.2f")
            if rv then reaper.SetExtState("ReaHaptics", "AmplitudeMin", tostring(ampMin), true) end

            ImGui.TableNextColumn(ctx)
            ImGui.AlignTextToFramePadding(ctx)
            ImGui.Text(ctx, "Low End Max")
            Tooltip("Bass frequency cutoff (Hz)")
            ImGui.TableNextColumn(ctx)
            ImGui.SetNextItemWidth(ctx, -1)
            rv, lowEndMax = ImGui.SliderDouble(ctx, "##LowEndMax", lowEndMax, 100, 500, "%.0f Hz")
            if rv then reaper.SetExtState("ReaHaptics", "LowEndMax", tostring(lowEndMax), true) end

            -- Multiplier | Freq Blend
            ImGui.TableNextRow(ctx)
            ImGui.TableNextColumn(ctx)
            ImGui.AlignTextToFramePadding(ctx)
            ImGui.Text(ctx, "Multiplier")
            Tooltip("Intensity scale factor")
            ImGui.TableNextColumn(ctx)
            ImGui.SetNextItemWidth(ctx, -1)
            rv, ampMultiplier = ImGui.SliderDouble(ctx, "##AmpMult", ampMultiplier, 0.0, 2.0, "%.2f")
            if rv then reaper.SetExtState("ReaHaptics", "AmplitudeMultiplier", tostring(ampMultiplier), true) end

            ImGui.TableNextColumn(ctx)
            ImGui.AlignTextToFramePadding(ctx)
            ImGui.Text(ctx, "Freq Blend")
            Tooltip("0=Bass, 1=Full spectrum")
            ImGui.TableNextColumn(ctx)
            ImGui.SetNextItemWidth(ctx, -1)
            rv, frequencyBlend = ImGui.SliderDouble(ctx, "##FreqBlend", frequencyBlend, 0.0, 1.0, "%.2f")
            if rv then reaper.SetExtState("ReaHaptics", "FrequencyBlend", tostring(frequencyBlend), true) end

            -- Transients | Envelope headers
            ImGui.TableNextRow(ctx)
            ImGui.TableNextColumn(ctx)
            ImGui.TextColored(ctx, colors.accent, "Transients")
            ImGui.TableNextColumn(ctx)
            ImGui.TableNextColumn(ctx)
            ImGui.TextColored(ctx, colors.accent, "Envelope")
            ImGui.TableNextColumn(ctx)

            -- Sensitivity | Simplification
            ImGui.TableNextRow(ctx)
            ImGui.TableNextColumn(ctx)
            ImGui.AlignTextToFramePadding(ctx)
            ImGui.Text(ctx, "Sensitivity")
            Tooltip("0=Strong only, 1=Subtle")
            ImGui.TableNextColumn(ctx)
            ImGui.SetNextItemWidth(ctx, -1)
            rv, transientSensitivity = ImGui.SliderDouble(ctx, "##TransSens", transientSensitivity, 0.0, 1.0, "%.2f")
            if rv then reaper.SetExtState("ReaHaptics", "TransientSensitivity", tostring(transientSensitivity), true) end

            ImGui.TableNextColumn(ctx)
            ImGui.AlignTextToFramePadding(ctx)
            ImGui.Text(ctx, "Simplification")
            Tooltip("0=Keep all, 1=Max reduce")
            ImGui.TableNextColumn(ctx)
            ImGui.SetNextItemWidth(ctx, -1)
            rv, envelopeSimplification = ImGui.SliderDouble(ctx, "##EnvSimp", envelopeSimplification, 0.0, 1.0, "%.2f")
            if rv then reaper.SetExtState("ReaHaptics", "EnvelopeSimplification", tostring(envelopeSimplification), true) end

            -- Min Spacing
            ImGui.TableNextRow(ctx)
            ImGui.TableNextColumn(ctx)
            ImGui.AlignTextToFramePadding(ctx)
            ImGui.Text(ctx, "Min Spacing")
            Tooltip("Min time between transients (s)")
            ImGui.TableNextColumn(ctx)
            ImGui.SetNextItemWidth(ctx, -1)
            rv, transientMinSpacing = ImGui.InputDouble(ctx, "##MinSpacing", transientMinSpacing, 0.01, 0.1, "%.2f s")
            if rv then reaper.SetExtState("ReaHaptics", "TransientMinSpacing", tostring(transientMinSpacing), true) end

            ImGui.TableNextColumn(ctx)
            ImGui.TableNextColumn(ctx)

            ImGui.EndTable(ctx)
        end
        ImGui.EndChild(ctx)
    end
    EndCard()

    -- SECTION: Logo (pinned to bottom)
    if logo_image then
        local logo_display_width = 80
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
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, colors.resetBtn)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, colors.resetBtnHover)
    if ImGui.Button(ctx, "Reset All", 70, 0) then
        ResetAllDefaults()
    end
    Tooltip("Reset all settings to defaults")
    ImGui.PopStyleColor(ctx, 2)
end

local function loop()
    PushStyle()
    ImGui.PushFont(ctx, font)
    ImGui.SetNextWindowSize(ctx, 540, 480, ImGui.Cond_FirstUseEver)

    local visible, open = ImGui.Begin(ctx, 'ReaHaptic Settings', true, ImGui.WindowFlags_NoCollapse)
    if visible then
        myWindow()
        ImGui.End(ctx)
    end

    ImGui.PopFont(ctx)
    PopStyle()

    if open then
        reaper.defer(loop)
    end
end

reaper.defer(loop)
