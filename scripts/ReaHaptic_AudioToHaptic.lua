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

--global vars
local default_ampMin = 0.0
local default_ampMax = 1.0
local default_freqMin = 20
local default_freqMax = 20000
local TransientTreshold = tonumber(reaper.GetExtState("ReaHaptics", "TransientThreshold")) or 0.2
local transientMinSpacing = tonumber(reaper.GetExtState("ReaHaptics", "TransientMinSpacing")) or 0.1
local ampMin = tonumber(reaper.GetExtState("ReaHaptics", "AmplitudeMin")) or default_ampMin
local ampMax = tonumber(reaper.GetExtState("ReaHaptics", "AmplitudeMax")) or default_ampMax
local freqMin = tonumber(reaper.GetExtState("ReaHaptics", "FrequencyMin")) or default_freqMin
local freqMax = tonumber(reaper.GetExtState("ReaHaptics", "FrequencyMax")) or default_freqMax

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

local function fft(x)
    local N = #x
    if N <= 1 then return x end

    local function bitrev(n, bits)
        local rev = 0
        for i = 1, bits do
            rev = (rev << 1) | (n & 1)
            n = n >> 1
        end
        return rev
    end

    -- Bit reversal permutation
    local bits = math.floor(math.log(N) / math.log(2))
    local X = {}
    for i=0,N-1 do
        X[bitrev(i,bits)+1] = {x[i+1], 0}
    end

    -- Danielson-Lanczos section
    local halfsize = 1
    local tablestep = N >> 1

    while halfsize < N do
        local phaseShiftStepR = math.cos(math.pi / halfsize)
        local phaseShiftStepI = -math.sin(math.pi / halfsize)
        local currentPhaseR = 1
        local currentPhaseI = 0

        for fftStep = 0, halfsize-1 do
            for i=fftStep, N-1, 2*halfsize do
                local off = i + halfsize
                local tr = currentPhaseR * X[off+1][1] - currentPhaseI * X[off+1][2]
                local ti = currentPhaseR * X[off+1][2] + currentPhaseI * X[off+1][1]

                local ur = X[i+1][1]
                local ui = X[i+1][2]

                X[off+1][1] = ur - tr
                X[off+1][2] = ui - ti
                X[i+1][1] = ur + tr
                X[i+1][2] = ui + ti
            end
            local tmpR = currentPhaseR
            currentPhaseR = tmpR * phaseShiftStepR - currentPhaseI * phaseShiftStepI
            currentPhaseI = tmpR * phaseShiftStepI + currentPhaseI * phaseShiftStepR
        end
        halfsize = halfsize * 2
    end

    return X
end

function EstimateFrequencyFromBufferfft(buffer, channels, sampleRate)
    -- Convert stereo buffer to mono
    local N = #buffer / channels
    local mono = {}
    for i = 1, N do
        local sum = 0
        for ch = 0, channels-1 do
            sum = sum + (buffer[(i-1)*channels + ch + 1] or 0)
        end
        mono[i] = sum / channels
    end

    -- Find next power of two equal or less than N (to avoid padding too much)
    local function previousPowerOfTwo(x)
        local power = 1
        while power * 2 <= x do
            power = power * 2
        end
        return power
    end

    local fftSize = previousPowerOfTwo(#mono)
    -- Trim buffer to fftSize to avoid zero padding
    local trimmed = {}
    for i = 1, fftSize do
        trimmed[i] = mono[i]
    end

    local X = fft(trimmed)

    -- Find max magnitude (skip DC)
    local maxMag = 0
    local maxIndex = 1
    for i = 2, fftSize/2 do
        local re = X[i][1]
        local im = X[i][2]
        local mag = math.sqrt(re*re + im*im)
        if mag > maxMag then
            maxMag = mag
            maxIndex = i
        end
    end

    local freqBin = maxIndex - 1
    local freq = freqBin * sampleRate / fftSize

    return freq
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

        buffer.clear()
        reaper.GetAudioAccessorSamples(accessor, sampleRate, channels, time-itemStart, windowSamples, buffer)

        local rms, centroid = GetRMSAndCentroid(buffer, channels, windowSamples)
        local fadeMult = ApplyFadeMultiplier(time, itemStart, itemStart + itemLength, fadeInLen, fadeOutLen, fadeInShape, fadeOutShape)

        local scaledAmp = (rms * fadeMult - ampMin) / (ampMax - ampMin)
        scaledAmp = math.max(-1, math.min(1, scaledAmp * 2 - 1)) -- Clamp and remap to -1 to 1
        table.insert(amplitude, { time = time, value = scaledAmp })

        local estimatedFreq = EstimateFrequencyFromBufferfft(buffer, channels, sampleRate)
        local clampedFreq = math.max(freqMin, math.min(freqMax, centroid or 0))
        local normFreq = NormalizeLog(centroid, freqMin, freqMax)
        table.insert(freq, { time = time, value = NormalizeLog(estimatedFreq, freqMin, freqMax) })
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
    local windowDuration = 0.01
    local channels = 2
    local samples = math.floor(sampleRate * windowDuration) * channels
    local buffer = reaper.new_array(samples)

    local item = reaper.GetMediaItemTake_Item(take)
    local fadeInLen = reaper.GetMediaItemInfo_Value(item, "D_FADEINLEN")
    local fadeOutLen = reaper.GetMediaItemInfo_Value(item, "D_FADEOUTLEN")
    local fadeInShape = reaper.GetMediaItemInfo_Value(item, "C_FADEINSHAPE")
    local fadeOutShape = reaper.GetMediaItemInfo_Value(item, "C_FADEOUTSHAPE")

    buffer.clear()
    reaper.GetAudioAccessorSamples(accessor, sampleRate, channels, timePosition - itemStart, samples / channels, buffer)

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
    reaper.SetMediaItemTakeInfo_Value(newTake, "D_STARTOFFS", reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS"))
    reaper.SetMediaItemTakeInfo_Value(newTake, "D_PLAYRATE", reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE"))
    reaper.SetMediaItemTakeInfo_Value(newTake, "D_PAN", reaper.GetMediaItemTakeInfo_Value(take, "D_PAN"))
    reaper.SetMediaItemTakeInfo_Value(newTake, "D_VOL", reaper.GetMediaItemTakeInfo_Value(take, "D_VOL"))
    reaper.SetMediaItemTakeInfo_Value(newTake, "D_PITCH", reaper.GetMediaItemTakeInfo_Value(take, "D_PITCH"))
    reaper.SetMediaItemTakeInfo_Value(newTake, "I_CHANMODE", reaper.GetMediaItemTakeInfo_Value(take, "I_CHANMODE"))
    reaper.SetMediaItemTakeInfo_Value(newTake, "I_CUSTOMCOLOR", reaper.GetMediaItemTakeInfo_Value(take, "I_CUSTOMCOLOR"))
    reaper.SetMediaItemInfo_Value(dupItem, "I_CURTAKE", 0)

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
    local lastTransientTime = -math.huge
    for i = 0, count - 1 do
        local itm = reaper.GetTrackMediaItem(itemParentTrack, i)
        local tpos = reaper.GetMediaItemInfo_Value(itm, "D_POSITION")
        if tpos >= pos and tpos <= pos + len then
            if first and (tpos - lastTransientTime >= transientMinSpacing) then
                local amp, freq = GetAudioAmplitudeAndFrequencyAtTime(take, tpos)
                if amp > (transientThreshold or 0.2) then
                    InsertEmphasisAtTime(tpos, amp * 2 * 1.5 - 1, freq)
                    table.insert(transientTimes, tpos)
                    lastTransientTime = tpos
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