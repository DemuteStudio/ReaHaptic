#[[
# * ReaScript Name: ReaHaptic_Exporter
# * Description: exports selected haptics file
# * Author: Florian Heynen
# * Version: 1.0
#]]
import os
import reaper_python as RPR
import json
import tkinter as tk
from tkinter import filedialog

sys.path.append(RPR_GetResourcePath() + '/Scripts')
from sws_python import *

selected_file_type = ".haptic"
export_path = ""

ExportFeedback = ""

def get_selected_regions():
    """Retrieve all selected regions in the Reaper project."""
    selected_regions = []
    _, _, _, num_regionsOut = RPR.RPR_CountProjectMarkers(0, 0, 0)
    for i in range(num_regionsOut):
        _, _, isrgn, pos, rgnend, _, markrgnindexnumber = RPR.RPR_EnumProjectMarkers(i, 0, 0, 0, "name", 0)
        fs = SNM_CreateFastString("")
        SNM_GetProjectMarkerName(0, markrgnindexnumber, isrgn, fs)
        faststringname = SNM_GetFastString(fs)
        SNM_DeleteFastString(fs)

        if isrgn and markrgnindexnumber >= 0:  # Only consider regions
            #RPR.RPR_ShowMessageBox(faststringname, "Debug message", 0)
            selected_regions.append((pos, rgnend, faststringname))
    return selected_regions

def get_envelope_points(track, env_name, start_time, end_time):
    """Retrieve envelope points from a specific envelope within a time range."""
    points = []
    env = RPR.RPR_GetTrackEnvelopeByName(track, env_name)
    _, _, _, track_name, _ = RPR.RPR_GetSetMediaTrackInfo_String(track, "P_NAME", "", False)
    if not env:
        return points
    
    time_name, value_name = ("m_time", "m_value") if selected_file_type == ".haps" else ("time", track_name)
        
    for i in range(RPR.RPR_CountEnvelopePoints(env)):
        _, _, _, time, value, _, _, _ = RPR.RPR_GetEnvelopePoint(env, i, 0, 0, 0, 0, 0)
        if start_time <= time <= end_time:
            amplitude = round((value + 1) / 2, 3)
            points.append({time_name: round(time - start_time, 3), value_name: amplitude})
    return points

def get_automation_points_in_items(region_start, region_end, track, env_name):
    envelope = RPR.RPR_GetTrackEnvelopeByName(track, env_name)

    num_automation_items = RPR.RPR_CountAutomationItems(envelope)
    points = []
    for ai_idx in range(num_automation_items):
        start_pos = RPR.RPR_GetSetAutomationItemInfo(envelope, ai_idx, "D_POSITION", 0, False)
        if region_start <= start_pos <= region_end:
            num_points = RPR.RPR_CountEnvelopePointsEx(envelope, ai_idx)
            if num_points > 0:
                _, _, _, _, time, value, _, tension, _ = RPR.RPR_GetEnvelopePointEx(envelope, ai_idx, 0, 0, 0, 0, 0, 0)
                points.append({
                    "time": time - region_start,
                    "value": value,
                    "tension": tension,
                })
    #RPR.RPR_ShowMessageBox(points, "Debug message", 0)
    return points

def get_amplitude_at_time(amplitude_points, time, start_time):
    # Find the closest amplitude value at the given time based on the curve

    for i in range(1, len(amplitude_points)):
        if amplitude_points[i]['time'] + start_time > time + start_time:
            prev_point = amplitude_points[i - 1]
            next_point = amplitude_points[i]
            # Simple linear interpolation (can be modified to Bezier interpolation)
            interp_amplitude = prev_point['amplitude'] + (next_point['amplitude'] - prev_point['amplitude']) * ((time - prev_point['time']) / (next_point['time'] - prev_point['time']))
            return interp_amplitude
    return amplitude_points[-1]['amplitude']  # Return the last point if time is after all points

def add_emphasis_to_haptic(amplitude_points, emphasis_points, start_time):
    """Merge emphasis points into amplitude points."""
    updated_points = amplitude_points[:]
    for emphasis in emphasis_points:
        emphasis_time = round(emphasis['time'], 3)
        emphasis_amplitude = round((emphasis['value'] + 1) / 2, 3)
        emphasis_frequency = round((emphasis['tension'] + 1) / 2, 3)
        matching_point = next((pt for pt in updated_points if round(pt['time'], 3) == emphasis_time), None)

        amplitude_at_time = get_amplitude_at_time(amplitude_points, emphasis_time, start_time)
        amplitude_at_time = round(amplitude_at_time, 3)

        if (amplitude_at_time > emphasis_amplitude):
            emphasis_amplitude = amplitude_at_time
        
        if matching_point and selected_file_type == ".haptic":
            matching_point['emphasis'] = emphasis.get('emphasis', {
                'amplitude': emphasis_amplitude,
                'frequency': emphasis_frequency
            })
        else:
            updated_points.append({
                "time": emphasis_time,
                "amplitude": amplitude_at_time,
                'emphasis': {
                    'amplitude': emphasis_amplitude,
                    'frequency': emphasis_frequency
                }
            })
    
    return sorted(updated_points, key=lambda x: x['time'])

def process_region(region_start, region_end, region_name, output_dir):
    global ExportFeedback
    #RPR.RPR_ShowMessageBox(region_name, "Debug Message", 0)
    """Process a region to export .haptic or .haps files."""
    track_count = RPR.RPR_CountTracks(0)
    amplitude, frequency, emphasis = [], [], []

    for i in range(track_count):
        track = RPR.RPR_GetTrack(0, i)
        _, _, _, track_name, _ = RPR.RPR_GetSetMediaTrackInfo_String(track, "P_NAME", "", False)
        points = get_envelope_points(track, "Pan", region_start, region_end)

        if track_name.lower() == "amplitude":
            amplitude = points
        elif track_name.lower() == "frequency":
            frequency = points
        elif track_name.lower() == "emphasis":
            emphasis = get_automation_points_in_items(region_start,region_end, track, "Pan")

    if not amplitude and not frequency:
        RPR.RPR_ShowMessageBox(f"{region_name}: No amplitude or frequency data found.", "Error", 0)
        return
    if selected_file_type == ".haptic":
        data = {
            "version": {"major": 1, "minor": 0, "patch": 0},
            "metadata": {"editor": "Reaper", "project": "hap_reaperTestExample"},
            "signals": {
                "continuous": {
                    "envelopes": {
                        "amplitude": add_emphasis_to_haptic(amplitude, emphasis, region_start),
                        "frequency": frequency
                    }
                }
            }
        }
        output_path = os.path.join(output_dir, region_name + ".haptic")
    else:
        defaultParams = {
                "m_loop": 0,
                "m_maximum": 1.0,
                "m_gain": 1.0,
                "m_signalEvaluationMethod": 3,
                "m_melodies": []
            },
        data = {
            "m_version": "5",
            "m_description": "",
            "m_HDFlag": 0,
            "m_time_unit": 0,
            "m_length_unit": 7,
            "m_stiffness": defaultParams,
            "m_texture": defaultParams,
            "m_vibration": {
                "m_loop": 0,
                "m_maximum": 1.0,
                "m_gain": 1.0,
                "m_signalEvaluationMethod": 3,
                "m_melodies": [{
                        "m_mute": 0,
                        "m_gain": 1.0,
                        "m_notes": emphasis
                    },
                    {
                        "m_mute": 0,
                        "m_gain": 1.0,
                        "m_notes": [{
                            "m_hapticEffect": {
                                "m_amplitudeModulation": {"m_keyframes": amplitude},
                                "m_frequencyModulation": {"m_keyframes": frequency}
                            }
                        }]
                    }
                ]
            },
            "m_gain": 1.0
        }
        output_path = os.path.join(output_dir, region_name + ".haps")
    os.makedirs(output_dir, exist_ok=True)
    with open(output_path, "w") as file:
        json.dump(data, file, indent=4)

    ExportFeedback = ExportFeedback + "File saved to: " + output_path + " \n"

def get_selected_media_items():
    selected_items = []
    # Get the total number of selected items
    num_items = RPR.RPR_CountMediaItems(0)
    
    for i in range(num_items):
        # Get each selected media item
        item = RPR_GetMediaItem(0, i)
        isSelected = RPR.RPR_IsMediaItemSelected(item)
        if isSelected:
            selected_items.append(item)
    
    return selected_items
    
    return None  # No region found at the given time
    
def main():
    global export_path
    global ExportFeedback
    export_path = RPR.RPR_GetExtState("ReaHaptics", "ExportPath")
    selected_file_typeId= RPR.RPR_GetExtState("ReaHaptics", "HapticType")
    file_types = [".haptic", ".haps"]
    selected_file_type = file_types[int(selected_file_typeId)]
    output_dir = export_path

    selected_items = get_selected_media_items()
    valid_tracks = {"haptics", "amplitude", "frequency", "emphasis"}
    processed_items = set()
    for item in selected_items:
        start_pos = RPR.RPR_GetMediaItemInfo_Value(item, "D_POSITION")
        end_pos = start_pos + RPR.RPR_GetMediaItemInfo_Value(item, "D_LENGTH")
        track_name = RPR.RPR_GetTrackName(RPR.RPR_GetMediaItem_Track(item), "", 512)[2]
        if track_name in valid_tracks:
            item_name = RPR.RPR_GetSetMediaItemInfo_String(item, "P_NOTES", "", False)[3]
            if item_name != " " and item_name not in processed_items:
                #RPR.RPR_ShowMessageBox(item_name, "Success", 0)
                processed_items.add(item_name)
                process_region(start_pos, end_pos, item_name, output_dir)

    RPR.RPR_ShowConsoleMsg(ExportFeedback)
            
main()