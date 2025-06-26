--[[
 * ReaScript Name: ReaHaptic_AudioToHaptic
 * Description: create an haptic item based on the amplitude and frequency data of a selected media item
 * Version: 1
--]]

local opsys = reaper.GetOS()
local extension 
if opsys:match('Win') then
  extension = 'dll'
else
  extension = 'so'
end

local info = debug.getinfo(1, 'S');
local resourcePath = reaper.GetResourcePath()

package.cpath = package.cpath .. ";" .. resourcePath .. "/Scripts/ReaHapticScripts/LUA Sockets/socket module/?."..extension
package.path = package.path .. ";" .. resourcePath .. "/Scripts/ReaHapticScripts/LUA Sockets/socket module/?.lua"

dofile(resourcePath .. "/Scripts/ReaHapticScripts/scripts/ReaHaptic_FunctionsLibrary.lua")

-- Get socket and osc modules
local socket = require('socket.core')
local osc = require('osc')

function ApplyFadeMultiplier(time, itemStart, itemEnd, fadeInLen, fadeOutLen, fadeInShape, fadeOutShape)
    local fadeMultiplier = 1.0

    if time < itemStart + fadeInLen and fadeInLen > 0 then
        local t = (time - itemStart) / fadeInLen
        fadeMultiplier = EvalFadeShape(t, fadeInShape)
    end

    if time > itemEnd - fadeOutLen and fadeOutLen > 0 then
        local t = (itemEnd - time) / fadeOutLen
        fadeMultiplier = fadeMultiplier * EvalFadeShape(t, fadeOutShape)
    end

    return fadeMultiplier
end

function EvalFadeShape(t, shape)
    t = math.max(0, math.min(1, t))
    if shape == 0 then
        return t
    elseif shape == 1 then
        return t * t * (3 - 2 * t)
    elseif shape == 2 then
        return math.sqrt(t)
    elseif shape == 3 then
        return 1 - math.sqrt(1 - t)
    elseif shape == 4 then
        return t * t * t * (t * (t * 6 - 15) + 10)
    elseif shape == 5 then
        return t >= 1 and 1 or 0
    elseif shape == 6 then
        return math.log(1 + 9 * t) / math.log(10)
    else
        return t
    end
end

function CreateAudioAccessorAndInfo(take)
    local accessor = reaper.CreateTakeAudioAccessor(take)
    if not accessor then return nil end

    local item = reaper.GetMediaItemTake_Item(take)
    local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local itemLength = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local startOffset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
    local playrate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")

    return accessor, itemStart, itemLength, startOffset, playrate
end

function GetRMSAndCentroid(buffer, channels, sampleCount)
    local sum = 0
    local weightedSum = 0

    for i = 1, sampleCount do
        local sample = buffer[i]
        if sample then
            sum = sum + sample * sample
            weightedSum = weightedSum + math.abs(sample) * i
        end
    end

    local rms = math.sqrt(sum / sampleCount)
    local centroid = weightedSum / (sum + 1e-6)

    return rms, centroid
end

function EstimateFrequencyFromBuffer(buffer, channels, sampleRate)
    local mono = {}
    for i = 1, #buffer, channels do
        local l = buffer[i] or 0
        local r = buffer[i + 1] or 0
        table.insert(mono, (l + r) * 0.5)
    end

    local minLag = math.floor(sampleRate / 1000)
    local maxLag = math.floor(sampleRate / 80)
    local bestLag, bestCorr = 0, -1

    for lag = minLag, maxLag do
        local corr = 0
        for i = 1, #mono - lag do
            corr = corr + mono[i] * mono[i + lag]
        end
        if corr > bestCorr then
            bestCorr = corr
            bestLag = lag
        end
    end

    if bestLag > 0 then
        return sampleRate / bestLag
    else
        return 0
    end
end

function GetAudioSamples(take, sampleRate, stepSize)
    local accessor, itemStart, itemLength, startOffset, playrate = CreateAudioAccessorAndInfo(take)
    if not accessor then return {}, {} end

    local item = reaper.GetMediaItemTake_Item(take)
    local fadeInLen = reaper.GetMediaItemInfo_Value(item, "D_FADEINLEN")
    local fadeOutLen = reaper.GetMediaItemInfo_Value(item, "D_FADEOUTLEN")
    local fadeInShape = reaper.GetMediaItemInfo_Value(item, "C_FADEINSHAPE")
    local fadeOutShape = reaper.GetMediaItemInfo_Value(item, "C_FADEOUTSHAPE")

    local channels = 1
    local windowSamples = math.floor(sampleRate * stepSize)
    local buffer = reaper.new_array(windowSamples * channels)
    local numSteps = math.floor(itemLength / stepSize)

    local amplitude, freq = {}, {}
    table.insert(amplitude, { time = itemStart, value = -1 })
    table.insert(freq, { time = itemStart, value = -1 })

    for i = 0, numSteps - 1 do
        local time = itemStart + i * stepSize
        local sourceTime = (time - itemStart) * playrate + startOffset

        buffer.clear()
        reaper.GetAudioAccessorSamples(accessor, sampleRate, channels, sourceTime, windowSamples, buffer)

        local rms, centroid = GetRMSAndCentroid(buffer, channels, windowSamples)
        local fadeMult = ApplyFadeMultiplier(time, itemStart, itemStart + itemLength, fadeInLen, fadeOutLen, fadeInShape, fadeOutShape)

        table.insert(amplitude, { time = time, value = (rms * fadeMult * 2) - 1 })
        table.insert(freq, { time = time, value = NormalizeLog(centroid, 1000, 1000000) })
    end

    table.insert(amplitude, { time = itemStart + itemLength, value = -1 })
    table.insert(freq, { time = itemStart + itemLength, value = -1 })

    reaper.DestroyAudioAccessor(accessor)
    return amplitude, freq
end

function GetFrequencyFromEnvelopeAtTime(time)
    local trackCount = reaper.CountTracks(0)
    for i = 0, trackCount - 1 do
        local track = reaper.GetTrack(0, i)
        local _, name = reaper.GetTrackName(track)
        if name:lower() == "frequency" then
            local env = reaper.GetTrackEnvelopeByName(track, "Pan")
            if env then
                local retval, value, _, _ = reaper.Envelope_Evaluate(env, time, 0, 0)
                return value
            end
        end
    end
    return 0
end

function GetAudioAmplitudeAndFrequencyAtTime(take, timePosition)
    local accessor, itemStart, itemLength, startOffset, playrate = CreateAudioAccessorAndInfo(take)
    if not accessor then return nil, nil end

    local sampleRate = 44100
    local windowDuration = 0.05
    local channels = 2
    local samples = math.floor(sampleRate * windowDuration) * channels
    local buffer = reaper.new_array(samples)

    local item = reaper.GetMediaItemTake_Item(take)
    local fadeInLen = reaper.GetMediaItemInfo_Value(item, "D_FADEINLEN")
    local fadeOutLen = reaper.GetMediaItemInfo_Value(item, "D_FADEOUTLEN")
    local fadeInShape = reaper.GetMediaItemInfo_Value(item, "C_FADEINSHAPE")
    local fadeOutShape = reaper.GetMediaItemInfo_Value(item, "C_FADEOUTSHAPE")

    local sourceTime = (timePosition - itemStart) * playrate + startOffset

    buffer.clear()
    reaper.GetAudioAccessorSamples(accessor, sampleRate, channels, sourceTime, samples / channels, buffer)

    -- Amplitude
    local sum, count = 0, 0
    for i = 1, samples do
        local sample = buffer[i]
        if sample then
            sum = sum + sample * sample
            count = count + 1
        end
    end

    local amplitude = (count > 0) and math.sqrt(sum / count) or 0
    local fadeMult = ApplyFadeMultiplier(timePosition, itemStart, itemStart + itemLength, fadeInLen, fadeOutLen, fadeInShape, fadeOutShape)
    amplitude = amplitude * fadeMult

    -- Frequency
    local freq = GetFrequencyFromEnvelopeAtTime(timePosition)

    reaper.DestroyAudioAccessor(accessor)
    return amplitude, freq
end


function InsertEnvelope(track, name, data)
    local env = reaper.GetTrackEnvelopeByName(track, "Pan")
    if not env then
        reaper.Main_OnCommand(40406, 0) -- Show all envelopes
        env = reaper.GetTrackEnvelopeByName(track, "Pan")
    end
    
    if not env then return end

    for _, point in ipairs(data) do
        reaper.InsertEnvelopePoint(env, point.time, point.value, 0, 0, false, true)
    end
    reaper.Envelope_SortPoints(env)
end

function CreateTransientEnvelope(track, take)
    local envName = "Pan"
    local env = reaper.GetTrackEnvelopeByName(track, envName)
    if not env then
        reaper.InsertTrackEnvelope(track)
        env = reaper.GetTrackEnvelopeByName(track, envName)
    end
    if not env then 
        reaper.ShowMessageBox("Could not get or create envelope '"..envName.."'", "Error", 0)
        return 
    end

    local item = reaper.GetMediaItemTake_Item(take)
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local endPos = pos + len

    local itemParentTrack = reaper.GetMediaItemTrack(item)
    local dupItem = reaper.AddMediaItemToTrack(itemParentTrack)
    if not dupItem then
        reaper.ShowMessageBox("Failed to duplicate item", "Error", 0)
        return
    end

    reaper.SetMediaItemInfo_Value(dupItem, "D_POSITION", pos)
    reaper.SetMediaItemInfo_Value(dupItem, "D_LENGTH", len)

    local newTake = reaper.AddTakeToMediaItem(dupItem)
    if not newTake then
        reaper.ShowMessageBox("Failed to add take to duplicate item", "Error", 0)
        return
    end
    local takeSource = reaper.GetMediaItemTake_Source(take)
    reaper.SetMediaItemTake_Source(newTake, takeSource)

    reaper.SelectAllMediaItems(0, false)
    reaper.SetMediaItemSelected(dupItem, true)
    reaper.UpdateArrange()

    reaper.Undo_BeginBlock()
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_XENAKIOS_SPLIT_ITEMSATRANSIENTS"), 0)
    reaper.Undo_EndBlock("Prepare transient data", -1)

    local transientTimes = {}
    local count = reaper.CountTrackMediaItems(itemParentTrack)
    local first = false
    local itemsToDelete = {}
    for i = 0, count - 1 do
        local itm = reaper.GetTrackMediaItem(itemParentTrack, i)
        local tpos = reaper.GetMediaItemInfo_Value(itm, "D_POSITION")
        if tpos >= pos and tpos <= pos + len then
            if first then
                local amp, freq = GetAudioAmplitudeAndFrequencyAtTime(take, tpos)
                if amp > 0.2 then
                    InsertEmphasisAtTime(tpos, amp*2*1.5 - 1, freq)
                    table.insert(transientTimes, tpos)
                end
            end
            table.insert(itemsToDelete, itm)
            first = true
        end
    end

    for i = #itemsToDelete, 1, -1 do
        if itemsToDelete[i] ~= item then
            reaper.DeleteTrackMediaItem(itemParentTrack, itemsToDelete[i])
        end
    end
end


reaper.Undo_BeginBlock()
local item = reaper.GetSelectedMediaItem(0, 0)
if not item then
    reaper.ShowMessageBox("Please select an audio item.", "No Item Selected", 0)
    return
end

local take = reaper.GetActiveTake(item)
if not take or not reaper.TakeIsMIDI(take) then
    local sampleRate = 44100
    local stepSize = 0.05

    local amplitude, frequency = GetAudioSamples(take, sampleRate, stepSize)
    local track = reaper.GetMediaItem_Track(item)
    
    local ampTrack = FindTrackByName("amplitude")
    local freqTrack = FindTrackByName("frequency")
    local emphTrack = FindTrackByName("emphasis")

    InsertEnvelope(ampTrack, "amplitude", amplitude)
    InsertEnvelope(freqTrack, "frequency", frequency)
    CreateTransientEnvelope(emphTrack, take)

    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local name = GetSourceFilename(item)
    InsertHapticItem(name, pos, pos + len + 0.2)
end

reaper.UpdateArrange()
reaper.Undo_EndBlock("Generate haptic envelopes", -1)