-- Common Functions for REAPER Lua Scripts
local socket = require('socket.core') -- Ensure Luasocket is installed and configured
local osc = require('osc')

function send_OSC_message(adress, hapticData, ip, port, udp)
    local msg = osc.encode(adress, hapticData)
    udp:sendto(msg, ip, port)
end

function getEthernetIP()
    local handle = io.popen("ipconfig")
    local result = handle:read("*a")
    handle:close()
    local ethernetIP = result:match("IPv4 Address[^\n]+: ([%d%.]+)")
    return ethernetIP
end
  
function promptIPAddress(defaultIP,defaultPort)
    local title = "Enter IP Address and Port"
    local captions = "IP Address,Port,Use Default (local 7401)"
    local defaults = defaultIP .. "," .. defaultPort .. ",0"
    
  
    local userInput, returnVal1 = reaper.GetUserInputs(title, 3, captions, defaults)
  
    if userInput then
      local inputs = {}
          for value in string.gmatch(returnVal1, "([^,]+)") do
              table.insert(inputs, value)
          end
  
      local useDefault = tonumber(inputs[3]) == 1
      if useDefault then
        return getEthernetIP(), 7401 -- Default IP and port
      else
        return inputs[1], tonumber(inputs[2])
      end
    else
        return nil
    end
end

function get_item_notes(item)
    local retval, notes = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
    return notes
end

-- Utility Functions
function round(num, decimal_places)
    local mult = 10^(decimal_places or 0)
    return math.floor(num * mult + 0.5) / mult
end

function get_project_dir()
    local retval, project_path = reaper.GetProjectPath("")
    return project_path
end

function get_selected_media_items()
	local selected_items = {}
	local num_items = reaper.CountMediaItems(0)
	
	for i = 0, num_items - 1 do
		local item = reaper.GetMediaItem(0, i)
		if reaper.IsMediaItemSelected(item) then
			table.insert(selected_items, item)
		end
	end
	return selected_items
end

function get_position()
    if (reaper.GetPlayState() & 1) == 1 then
        return reaper.GetPlayPosition()
    else
        return reaper.GetCursorPosition()
    end
end

-- Envelope and Points Processing
function get_envelope_points(track, env_name, start_time, end_time, addBeginPoint)
	local points = {}
	local env = reaper.GetTrackEnvelopeByName(track, env_name)
	local _, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
	if not env then return points end

	local time_name, value_name
	if selected_file_type == ".haps" then
		time_name = "m_time"
		value_name = "m_value"
	else
		time_name = "time"
		value_name = track_name
	end

    if addBeginPoint then
        local indx = reaper.GetEnvelopePointByTime(env, start_time)
        local _, time1, value1, _, _ = reaper.GetEnvelopePoint(env, indx)
        local _, time2, value2, _, _ = reaper.GetEnvelopePoint(env, indx + 1)
        local progress = (start_time - time1) / (time2 - time1)
        value1 = (value1 + 1)/2
        value2 = (value2 + 1)/2
        local interpolatedValue = value1 + progress * (value2 - value1)
        local amplitude = round(interpolatedValue, 3)

        table.insert(points, { [time_name] = 0.0, [value_name] = amplitude })
    end
    
	local num_points = reaper.CountEnvelopePoints(env)
    local prev_time = -1
    local pointnr = 0
	for i = 0, num_points - 1 do
		local _, time, value, _, _ = reaper.GetEnvelopePoint(env, i)
		if time >= start_time and time <= end_time then
            if time == prev_time then time = time + 0.001 end -- savety to make sure 2 points do not have the same time value, otherwise haptic does not work
            if (pointnr == 0 and round(time - start_time, 3) ~= 0.0) then --savety to always have a point at time 0.0
                table.insert(points, { [time_name] = 0, [value_name] = 0 })
            end
			local amplitude = round((value + 1) / 2, 3)
			table.insert(points, { [time_name] = round(time - start_time, 3), [value_name] = amplitude })
            prev_time = time
            pointnr = pointnr + 1
		end
	end
	return points
end

function get_automation_points_in_items(region_start, region_end, track, env_name)
	local envelope = reaper.GetTrackEnvelopeByName(track, env_name)
	if not envelope then return {} end

	local num_automation_items = reaper.CountAutomationItems(envelope)
	local points = {}

	for ai_idx = 0, num_automation_items - 1 do
		local start_pos = reaper.GetSetAutomationItemInfo(envelope, ai_idx, "D_POSITION", 0, false)
		if start_pos >= region_start and start_pos <= region_end then
			local num_points = reaper.CountEnvelopePointsEx(envelope, ai_idx)
            local _, time, value, _, tension = reaper.GetEnvelopePointEx(envelope, ai_idx, 0)
            table.insert(points, {
                time = time - region_start,
                value = value,
                tension = tension,
            })
		end
	end
	return points
end

function merge_amplitude_and_emphasis(amplitude, emphasis, decimal_places, region_start)
    local merged = {}
    local i, j = 1, 1
    local round_places = decimal_places or 6

    while j <= #emphasis do
        while i <= #amplitude and round(amplitude[i].time, round_places) < round(emphasis[j].time, round_places) do
            table.insert(merged, amplitude[i])
            i = i + 1
        end
        if i <= #amplitude and round(amplitude[i].time, round_places) == round(emphasis[j].time, round_places) then
            local ampl = (amplitude[i].amplitude > emphasis[j].value) and amplitude[i].amplitude or emphasis[j].value
            table.insert(merged, {
                time = amplitude[i].time,
                amplitude = amplitude[i].amplitude,
                emphasis = {
                    amplitude = ampl,
                    frequency = emphasis[j].tension
                }
            })
            i = i + 1
        else
            local calculated_amplitude = get_amplitude_at_time(amplitude, emphasis[j].time, region_start)  -- Correct function call here
            local ampl = (calculated_amplitude > emphasis[j].value) and calculated_amplitude or emphasis[j].value
            table.insert(merged, {
                time = emphasis[j].time,
                amplitude = calculated_amplitude,
                emphasis = {
                    amplitude = ampl,
                    frequency = emphasis[j].tension
                }
            })
        end
        j = j + 1
    end

    while i <= #amplitude do
        table.insert(merged, amplitude[i])
        i = i + 1
    end

    return merged
end

function get_amplitude_at_time(amplitude_points, time, start_time)
	for i = 2, #amplitude_points do
		if amplitude_points[i].time + start_time > time + start_time then
			local prev_point = amplitude_points[i - 1]
			local next_point = amplitude_points[i]
			local interp_amplitude = prev_point.amplitude + 
				((next_point.amplitude - prev_point.amplitude) * 
				((time - prev_point.time) / (next_point.time - prev_point.time)))
			return interp_amplitude
		end
	end
	return amplitude_points[#amplitude_points].amplitude
end

function generate_points_string(amplitude_keyframes, frequency_keyframes)
    local result = "{\n"
    -- Process amplitude points
    if #amplitude_keyframes > 0 then
        result = result .. '  "amplitude": [\n'
        for i, point in ipairs(amplitude_keyframes) do
            result = result .. '    {\n'
            result = result .. string.format('      "time": %.6f, "amplitude": %.6f', point.time, point.amplitude)

            if point.emphasis then
                result = result .. string.format(',\n      "emphasis": {"amplitude": %.6f, "frequency": %.6f}', point.emphasis.amplitude, point.emphasis.frequency)
            end

            result = result .. "\n    }"

            if i < #amplitude_keyframes then
                result = result .. ",\n"
            else
                result = result .. "\n"
            end
        end
        result = result .. "  ],\n"
    end
    -- Process frequency points
    if #frequency_keyframes > 0 then
        result = result .. '  "frequency": [\n'
        for i, point in ipairs(frequency_keyframes) do
            result = result .. '    {\n'
            result = result .. string.format('      "time": %.6f, "frequency": %.6f', point.time, point.frequency)

            result = result .. "\n    }"

            if i < #frequency_keyframes then
                result = result .. ",\n"
            else
                result = result .. "\n"
            end
        end
        result = result .. "  ]\n"
    end
    result = result .. "}"
    return result
end

function process_HapticItem(region_start, region_end, region_name, addBeginPoint)
	local track_count = reaper.CountTracks(0)
	local amplitude, frequency, emphasis = {}, {}, {}

	for i = 0, track_count - 1 do
		local track = reaper.GetTrack(0, i)
		local _, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)

		if track_name:lower() == "amplitude" then
			amplitude = get_envelope_points(track, "Pan", region_start, region_end, addBeginPoint)
		elseif track_name:lower() == "frequency" then
			frequency = get_envelope_points(track, "Pan", region_start, region_end, addBeginPoint)
		elseif track_name:lower() == "emphasis" then
			emphasis = get_automation_points_in_items(region_start, region_end, track, "Pan")
		end
	end
	amplitude = merge_amplitude_and_emphasis(amplitude,emphasis,3 ,region_start)

	if #amplitude == 0 and #frequency == 0 then
		reaper.ShowMessageBox(region_name .. ": No amplitude or frequency data found.", "Error", 0)
		return
	end
	local pointsString = generate_points_string(amplitude, frequency)
	--reaper.ShowMessageBox(pointsString, "Debug", 0)
	return pointsString
end

return {
    round = round,
    get_project_dir = get_project_dir,
    get_selected_media_items = get_selected_media_items,
    get_envelope_points = get_envelope_points,
    get_automation_points = get_automation_points,
    merge_amplitude_and_emphasis = merge_amplitude_and_emphasis,
    get_amplitude_at_time = get_amplitude_at_time,
    send_OSC_message = send_OSC_message,
    serialize_keyframes = serialize_keyframes,
}