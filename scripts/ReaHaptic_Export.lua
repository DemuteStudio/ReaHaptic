--[[
 * ReaScript Name: ReaHaptic_Export
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

-- Load saved settings (if any)
local default_type = reaper.GetExtState("ReaHaptics", "HapticType")
if default_type == "" then default_type = ".haptic" end

local file_types = {".haptic", ".haps"}
local selected_file_type_idx = 1
for i, ft in ipairs(file_types) do
    if ft == default_type then
        selected_file_type_idx = i
        break
    end
end

local export_path = reaper.GetExtState("ReaHaptics", "ExportPath")
if export_path == "" then export_path = "" end

local function browse_path()
    local retval, selected_path = reaper.BrowseForFolder("Select Export Path")
    if retval then export_path = selected_path end
end

local function Custom_EnumerateActions()
    local actions = {}

    -- Get the Reaper resource path
    local ini_path = reaper.GetResourcePath() .. "/reaper-kb.ini"

    -- Open the action list file
    local file = io.open(ini_path, "r")
    if not file then return actions end  -- Return empty table if file can't be opened

    for line in file:lines() do
        -- Match the structure of 'SCR' lines containing custom actions
        local action_id, action_name = line:match('SCR%s+%d+%s+%d+%s+(RS[%x]+)%s+"(.-)"')
        
        if action_id and action_name then
            actions[action_name] = "_" .. action_id  -- Store in dictionary
        end
    end

    file:close()
    return actions
end



local function GetIdFromActionName(section, search)
    local actions = Custom_EnumerateActions(section)
    return actions[search]  -- Return the command ID if found, else nil
end

local function on_confirm()
    -- Save settings
    reaper.SetExtState("ReaHaptics", "HapticType", selected_file_type_idx, true)
    reaper.SetExtState("ReaHaptics", "ExportPath", export_path, true)

    local action_id = GetIdFromActionName(0, "Custom: ReaHaptic_Exporter.py")
    if action_id then
        reaper.Main_OnCommand(reaper.NamedCommandLookup(action_id), 0)
    else
        reaper.ShowMessageBox("Action not found!", "Error", 0)
    end
end

local function get_selected_items()
    local unique_items = {}
    local seen_groups = {}

    local num_selected = reaper.CountSelectedMediaItems(0)

    for i = 0, num_selected - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local group_id = reaper.GetMediaItemInfo_Value(item, "I_GROUPID")
        
        -- If this group hasn't been added yet and item has notes
        if group_id == 0 or not seen_groups[group_id] then
            local _, notes = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
            if notes ~= "" then
                table.insert(unique_items, notes)
                if group_id > 0 then
                    seen_groups[group_id] = true
                end
            end
        end
    end

    return unique_items
end

local function render_ui()
    -- File Type Dropdown
    ImGui.Text(ctx, "Haptic Type Override:")
    if ImGui.BeginCombo(ctx, "##file_type", file_types[selected_file_type_idx]) then
        for i, ft in ipairs(file_types) do
            if ImGui.Selectable(ctx, ft, selected_file_type_idx == i) then
                selected_file_type_idx = i
            end
        end
        ImGui.EndCombo(ctx)
    end

    -- Export Path Input & Browse Button
    ImGui.Text(ctx, "Export Path Override:")
    local changed, new_path = ImGui.InputText(ctx, "##export_path", export_path, ImGui.InputTextFlags_AutoSelectAll)
    if changed then export_path = new_path end

    if ImGui.Button(ctx, "Browse") then
        browse_path()
    end

    -- Display Selected Items
    ImGui.Separator(ctx)
    ImGui.Text(ctx, "Selected Haptic Items:")
    local selected_items = get_selected_items()
    for _, item_name in ipairs(selected_items) do
        ImGui.BulletText(ctx, item_name) -- Displays each item as a bulleted list
    end
    ImGui.Separator(ctx)

    -- OK Button
    if ImGui.Button(ctx, "Export") then
        on_confirm()
        return true
    end
    return false
end

local function loop()
    ImGui.PushFont(ctx, font)
    ImGui.SetNextWindowSize(ctx, 400, 400, ImGui.Cond_FirstUseEver)
    local visible, open = ImGui.Begin(ctx, 'ReaHaptic Exporter', true)
    if visible then
        done = render_ui()
        ImGui.End(ctx)
    end
    ImGui.PopFont(ctx)

    if open and not done then
        reaper.defer(loop)
    end
end

reaper.defer(loop)