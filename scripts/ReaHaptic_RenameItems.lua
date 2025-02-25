--[[
 * ReaScript Name: ReaHaptic_DeleteSelectedHaptic
 * Description: deletes  the selected haptic files.
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

local items = {}
local item_entries = {}

local function collect_items()
    local count = reaper.CountSelectedMediaItems(0)
    local unique_items = {} 
    for i = 0, count - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        if item ~= nil then
            group = reaper.GetMediaItemInfo_Value(item, "I_GROUPID")
            local _, name = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
            if name then
                local key = name .. "|" .. group
                if not unique_items[key] then
                    unique_items[key] = {name = name, group = group, items = {item}, oldName = name}
                    table.insert(item_entries, unique_items[key])
                else
                    table.insert(unique_items[key].items, item)
                end
            end
        end
    end
end

local function rename_items()
    reaper.Undo_BeginBlock()

    local rename_map = {}
    for _, entry in ipairs(item_entries) do
        rename_map[entry.oldName .. "|" .. entry.group] = entry.name
    end

    local item_count = reaper.CountMediaItems(0)
    for i = 0, item_count - 1 do
        local item = reaper.GetMediaItem(0, i)
        local group = reaper.GetMediaItemInfo_Value(item, "I_GROUPID")
        local _, name = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)

        if name then
            local key = name .. "|" .. group
            if rename_map[key] then
                reaper.GetSetMediaItemInfo_String(item, "P_NOTES", rename_map[key], true)
            end
        end
    end

    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Rename Items (including grouped items)", -1)
end

local function loop()
    local visible, open = ImGui.Begin(ctx, "Rename Selected Items", true)
    if visible then
        if reaper.ImGui_Button(ctx, 'Refresh') then
            item_entries = {}
            collect_items()
        end
        for i, entry in ipairs(item_entries) do
            local label = entry.oldName
            local changed, new_name = ImGui.InputText(ctx, "##" .. i, entry.name)
            if changed then
                entry.name = new_name
            end
            ImGui.SameLine(ctx)
            ImGui.Text(ctx, label)
        end
        if ImGui.Button(ctx, "Apply") then
            rename_items()
            item_entries = {}
            collect_items()
        end
        ImGui.End(ctx)
    end

    if open then
        reaper.defer(loop)
    end
end

collect_items()
reaper.defer(loop)