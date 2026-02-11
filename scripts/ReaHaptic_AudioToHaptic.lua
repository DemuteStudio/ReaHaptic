--[[
 * ReaScript Name: ReaHaptic_AudioToHaptic
 * Description: Create a haptic item from audio using frequency-filtered analysis:
 *   - Amplitude: weighted blend of low-end and full spectrum energy
 *   - Frequency: inverse of low-end ratio (bass = deep, no bass = bright)
 *   - Emphasis: low-end transient detection for bass hits
 * Version: 2
--]]

local opsys = reaper.GetOS()
local extension 
if opsys:match('Win') then
  extension = 'dll'
else
  extension = 'so'
end

local resourcePath = reaper.GetResourcePath()

package.cpath = package.cpath .. ";" .. resourcePath .. "/Scripts/ReaHapticScripts/LUA Sockets/socket module/?."..extension
package.path = package.path .. ";" .. resourcePath .. "/Scripts/ReaHapticScripts/LUA Sockets/socket module/?.lua"

dofile(resourcePath .. "/Scripts/ReaHapticScripts/scripts/ReaHaptic_FunctionsLibrary.lua")

--global vars
local default_ampMin = 0.0
local transientMinSpacing = tonumber(reaper.GetExtState("ReaHaptics", "TransientMinSpacing")) or 0.1
local ampMin = tonumber(reaper.GetExtState("ReaHaptics", "AmplitudeMin")) or default_ampMin
local ampMax = 1.0
local ampMultiplier = tonumber(reaper.GetExtState("ReaHaptics", "AmplitudeMultiplier")) or 0.7
local lowEndMax = tonumber(reaper.GetExtState("ReaHaptics", "LowEndMax")) or 250
local frequencyBlend = tonumber(reaper.GetExtState("ReaHaptics", "FrequencyBlend")) or 0.3
local transientSensitivity = tonumber(reaper.GetExtState("ReaHaptics", "TransientSensitivity")) or 0.5
local envelopeSimplification = tonumber(reaper.GetExtState("ReaHaptics", "EnvelopeSimplification")) or 0.1

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

-- Biquad low-pass filter for isolating low frequencies
function CreateLowPassFilter(cutoffFreq, sampleRate)
    local Q = 0.707 -- Butterworth
    local omega = 2 * math.pi * cutoffFreq / sampleRate
    local alpha = math.sin(omega) / (2 * Q)
    local cosw = math.cos(omega)

    local b0 = (1 - cosw) / 2
    local b1 = 1 - cosw
    local b2 = (1 - cosw) / 2
    local a0 = 1 + alpha
    local a1 = -2 * cosw
    local a2 = 1 - alpha

    -- Normalize coefficients
    return {
        b0 = b0 / a0,
        b1 = b1 / a0,
        b2 = b2 / a0,
        a1 = a1 / a0,
        a2 = a2 / a0,
        -- Filter state
        x1 = 0, x2 = 0,
        y1 = 0, y2 = 0
    }
end

function ApplyFilter(filter, sample)
    local output = filter.b0 * sample + filter.b1 * filter.x1 + filter.b2 * filter.x2
                   - filter.a1 * filter.y1 - filter.a2 * filter.y2

    -- Update state
    filter.x2 = filter.x1
    filter.x1 = sample
    filter.y2 = filter.y1
    filter.y1 = output

    return output
end

function ResetFilter(filter)
    filter.x1 = 0
    filter.x2 = 0
    filter.y1 = 0
    filter.y2 = 0
end

-- Get RMS of low-end frequencies only
function GetLowEndRMS(buffer, sampleCount, sampleRate, cutoffFreq)
    local filter = CreateLowPassFilter(cutoffFreq, sampleRate)
    local sum = 0

    for i = 1, sampleCount do
        local sample = buffer[i] or 0
        local filtered = ApplyFilter(filter, sample)
        sum = sum + filtered * filtered
    end

    return math.sqrt(sum / sampleCount)
end

-- Get full spectrum RMS
function GetFullRMS(buffer, sampleCount)
    local sum = 0
    for i = 1, sampleCount do
        local sample = buffer[i] or 0
        sum = sum + sample * sample
    end
    return math.sqrt(sum / sampleCount)
end

-- Douglas-Peucker envelope simplification algorithm
function SimplifyEnvelope(points, tolerance)
    if #points <= 2 then return points end

    -- Find the point with the maximum distance from the line between first and last
    local maxDist = 0
    local maxIndex = 1
    local first = points[1]
    local last = points[#points]

    for i = 2, #points - 1 do
        local dist = PerpendicularDistance(points[i], first, last)
        if dist > maxDist then
            maxDist = dist
            maxIndex = i
        end
    end

    -- If max distance is greater than tolerance, recursively simplify
    if maxDist > tolerance then
        local left = {}
        local right = {}

        for i = 1, maxIndex do
            table.insert(left, points[i])
        end
        for i = maxIndex, #points do
            table.insert(right, points[i])
        end

        local leftSimplified = SimplifyEnvelope(left, tolerance)
        local rightSimplified = SimplifyEnvelope(right, tolerance)

        -- Combine results (remove duplicate middle point)
        local result = {}
        for i = 1, #leftSimplified - 1 do
            table.insert(result, leftSimplified[i])
        end
        for i = 1, #rightSimplified do
            table.insert(result, rightSimplified[i])
        end

        return result
    else
        return {first, last}
    end
end

function PerpendicularDistance(point, lineStart, lineEnd)
    local dx = lineEnd.time - lineStart.time
    local dy = lineEnd.value - lineStart.value

    -- Normalize
    local mag = math.sqrt(dx * dx + dy * dy)
    if mag < 1e-10 then return 0 end

    dx = dx / mag
    dy = dy / mag

    -- Vector from lineStart to point
    local pvx = point.time - lineStart.time
    local pvy = point.value - lineStart.value

    -- Perpendicular distance (cross product magnitude)
    local dist = math.abs(pvx * dy - pvy * dx)

    return dist
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

        -- Calculate low-end and full spectrum RMS
        local lowEndRMS = GetLowEndRMS(buffer, windowSamples, sampleRate, lowEndMax)
        local fullRMS = GetFullRMS(buffer, windowSamples)

        -- Apply fade multiplier
        local fadeMult = ApplyFadeMultiplier(time, itemStart, itemStart + itemLength, fadeInLen, fadeOutLen, fadeInShape, fadeOutShape)

        -- Amplitude: weighted blend between low-end and full spectrum
        -- frequencyBlend: 0 = bass only, 1 = full spectrum
        local blendedRMS = lowEndRMS * (1 - frequencyBlend) + fullRMS * frequencyBlend
        local scaledAmp = (blendedRMS * fadeMult - ampMin) / (ampMax - ampMin)
        scaledAmp = math.max(-1, math.min(1, scaledAmp * ampMultiplier * 2 - 1)) -- Clamp and remap to -1 to 1
        table.insert(amplitude, { time = time, value = scaledAmp })

        -- Frequency envelope: inverse of low-end ratio
        -- High bass content = low frequency value (deep haptic)
        -- Low bass content = high frequency value (bright haptic)
        local epsilon = 1e-6
        local lowEndRatio = lowEndRMS / (fullRMS + epsilon)
        -- Clamp ratio to 0-1 range, then invert
        lowEndRatio = math.max(0, math.min(1, lowEndRatio))
        local freqValue = (1 - lowEndRatio) * 2 - 1 -- Remap to -1 to 1
        table.insert(freq, { time = time, value = freqValue })
    end

    table.insert(amplitude, { time = itemStart + itemLength, value = -1 })
    table.insert(freq, { time = itemStart + itemLength, value = -1 })

    reaper.DestroyAudioAccessor(accessor)

    -- Apply envelope simplification if enabled
    if envelopeSimplification > 0 then
        amplitude = SimplifyEnvelope(amplitude, envelopeSimplification)
        freq = SimplifyEnvelope(freq, envelopeSimplification*3)
    end

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

    local accessor, itemStart, itemLength = CreateAudioAccessorAndInfo(take)
    if not accessor then return end

    local sampleRate = 44100
    local stepSize = 0.01   -- 10 ms
    local windowSamples = math.floor(sampleRate * stepSize)
    local buffer = reaper.new_array(windowSamples)
    local numSteps = math.floor(itemLength / stepSize)

    -------------------------------------------------
    -- FAST FILTERS
    -------------------------------------------------

    function MakeHPF(fc)
        local a = math.exp(-2 * math.pi * fc / sampleRate)
        return {a=a, y=0, xPrev=0}
    end

    function RunHPF(f, x)
        local y = f.a * (f.y + x - f.xPrev)
        f.xPrev = x
        f.y = y
        return y
    end

    function MakeLPF(fc)
        local a = math.exp(-2 * math.pi * fc / sampleRate)
        return {a=a, y=0}
    end

    function RunLPF(f, x)
        f.y = (1 - f.a) * x + f.a * f.y
        return f.y
    end

    function MakeBand(lo, hi)
        return { hp = MakeHPF(lo), lp = MakeLPF(hi) }
    end

    function RunBand(band, x)
        return RunLPF(band.lp, RunHPF(band.hp, x))
    end

    -- Punch-optimized bands
    local bands = {
        MakeBand(40, 90),     -- sub
        MakeBand(90, 400),   -- body
        MakeBand(400, 1000)   -- snap
    }

    -------------------------------------------------
    -- PASS 1: Shock envelopes (2nd derivative)
    -------------------------------------------------

    local shockEnv = {}

    local prevSample = {0,0,0}
    local prevVel = {0,0,0}

    for i = 0, numSteps-1 do
        buffer.clear()
        reaper.GetAudioAccessorSamples(accessor, sampleRate, 1,
            i * stepSize, windowSamples, buffer)

        local sumShock = 0

        for s = 1, windowSamples do
            local x = buffer[s] or 0

            for b = 1,3 do
                local y = RunBand(bands[b], x)

                -- first derivative (velocity)
                local v = y - prevSample[b]
                prevSample[b] = y

                -- second derivative (acceleration / shock)
                local a = v - prevVel[b]
                prevVel[b] = v

                sumShock = sumShock + math.abs(a)
            end
        end

        shockEnv[i+1] = sumShock / windowSamples
    end

    -------------------------------------------------
    -- PASS 2: Adaptive peak picking
    -------------------------------------------------

    local lookbackCount = 20
    local thresholdMultiplier = 3 - (transientSensitivity*2)
    local minShock = 0.0003

    local lastTransientTime = -math.huge

    for i = lookbackCount + 1, numSteps - 1 do
        local s = shockEnv[i]

        local isLocalMax =
            s > shockEnv[i-1] and
            s > shockEnv[i+1] and
            s > minShock

        if isLocalMax then
            local sum = 0
            for j = i - lookbackCount, i - 1 do
                sum = sum + shockEnv[j]
            end
            local mean = sum / lookbackCount
            local threshold = math.max(minShock, mean * thresholdMultiplier)

            if s > threshold then
                local time = itemStart + (i-1)*stepSize

                if (time - lastTransientTime) >= transientMinSpacing then

                    -- Strength from shock intensity
                    local strength = math.min(1, s * 30)
                    local emphasisAmp = strength * 2 - 1

                    -- Low vs high shock ratio for frequency mapping
                    local low = bands[1].lp.y
                    local mid = bands[2].lp.y
                    local high = bands[3].lp.y
                    local total = math.abs(low) + math.abs(mid) + math.abs(high) + 1e-6
                    local lowRatio = math.abs(low) / total
                    local emphasisFreq = (1 - lowRatio) * 2 - 1

                    InsertEmphasisAtTime(time, emphasisAmp, emphasisFreq)
                    lastTransientTime = time
                end
            end
        end
    end

    reaper.DestroyAudioAccessor(accessor)
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