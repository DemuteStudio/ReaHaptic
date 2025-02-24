#[[
# * ReaScript Name: ReaHaptic_Importer
# * Description: importes haptic file
# * Author: Florian Heynen
# * Version: 1.0
#]]
import os
import json
import reaper_python as RPR
import tkinter as tk
from tkinter import filedialog

# Globals
cursor_position = RPR.RPR_GetCursorPosition()
selected_file_type = ".haptic"

def show_file_dialog():
    # Initialize Tkinter (hidden root window)
    root = tk.Tk()
    root.withdraw()  # Hide the root window

    # Open a file dialog for multiple file selection
    file_paths = filedialog.askopenfilenames(
        title="Select files",  # Dialog title
        filetypes=[("All Files", "*.*")]  # File filters
    )

    if file_paths:
        return file_paths
    
    RPR.RPR_ShowMessageBox("Invalid files selected or operation canceled.", "Error", 0)
    return []

def parse_haptic_file(file_path):
    """Parse the .haptic or .haps file and extract envelope data."""
    global selected_file_type
    try:
        with open(file_path, 'r') as file:
            data = json.load(file)
        
        if file_path.endswith('.haptic'):
            selected_file_type = '.haptic'
            amplitude_points = data['signals']['continuous']['envelopes'].get('amplitude', [])
            frequency_points = data['signals']['continuous']['envelopes'].get('frequency', [])
            enphasis_points = data['signals']['continuous']['envelopes'].get('amplitude', [])
        elif file_path.endswith('.haps'):
            selected_file_type = '.haps'
            melodies = data['m_vibration']['m_melodies']
            amplitude_points = melodies[1]['m_notes'][0]['m_hapticEffect']['m_amplitudeModulation']['m_keyframes']
            frequency_points = melodies[1]['m_notes'][0]['m_hapticEffect']['m_frequencyModulation']['m_keyframes']
            enphasis_points = melodies[0]['m_notes']
        else:
            RPR.RPR_ShowMessageBox("Unsupported file format.", "Error", 0)
            return None, None
        
        return amplitude_points, frequency_points, enphasis_points
    except Exception as e:
        RPR.RPR_ShowMessageBox(f"Failed to parse file: {e}", "Error", 0)
        return None, None

def create_envelope(track, env_name, points, envelopename, start_time, end_time):
    """Create envelope points on a given envelope."""
    env = RPR.RPR_GetTrackEnvelopeByName(track, env_name)
    RPR.RPR_DeleteEnvelopePointRange(env, start_time, end_time)
    if not env:
        RPR.RPR_ShowMessageBox(f"Envelope '{env_name}' not found on track.", "Error", 0)
        return False
    RPR.RPR_InsertEnvelopePoint(env, start_time, -1, 0, 0, False, True)# Add a point at the beginning of the region
    for pt in points:
        if (envelopename == "emphasis"):
            if (selected_file_type == '.haptic'):
                if (pt.get('emphasis') is not None):
                    time = start_time + pt['time']
                    value = pt['emphasis']['amplitude']
                    tension = pt['emphasis']['frequency']
                    indx = RPR.RPR_InsertAutomationItem(env, -1, time, 0.07)  #collect created envelope points
                    #RPR.RPR_ShowMessageBox(indx, "Error", 0)
                    
                    RPR.RPR_InsertEnvelopePointEx(env,indx, 0, value, 5, tension, False, True)
                    RPR.RPR_SetEnvelopePointEx(env, indx, 0, time, value, 5, tension, False, True)
                    RPR.RPR_DeleteEnvelopePointEx(env, indx, 1)
        else:
            if (selected_file_type == '.haptic'):
                time = start_time + pt['time']
                value = pt[envelopename]*2 - 1
                shape = 0  # Linear
                tension = 0
                selected = False
                no_sort = True  # We'll sort after inserting all points
            RPR.RPR_InsertEnvelopePoint(env, time, value, shape, tension, selected, no_sort)
    RPR.RPR_InsertEnvelopePoint(env, end_time, -1, 0, 0, False, True)# Add a point at the end of the region
    RPR.RPR_Envelope_SortPoints(env)
    return True
 
def create_item(item_name, start_time, end_time, trackName, Id):
    track_count = RPR.RPR_CountTracks(0)  # Get the total number of tracks
    haptics_track = None

    for i in range(track_count):
        track = RPR.RPR_GetTrack(0, i)
        _, _, _, track_name, _ = RPR.RPR_GetSetMediaTrackInfo_String(track, "P_NAME", "", False)
        if track_name.lower() == trackName:
            haptics_track = track
    #RPR.RPR_ShowMessageBox(haptics_track, "Success", 0)
    if haptics_track:
        color = RPR.RPR_GetTrackColor(track)
        item = RPR.RPR_AddMediaItemToTrack(haptics_track)
        RPR.RPR_GetSetMediaItemInfo_String(item, "P_NOTES", item_name, True)
        RPR.RPR_SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", color)
        RPR.RPR_SetMediaItemPosition(item, start_time - 0.001, False)
        RPR.RPR_SetMediaItemLength(item, end_time - start_time + 0.1, True)
        RPR.RPR_SetMediaItemInfo_Value(item, "I_GROUPID", Id)
        #RPR.RPR_UpdateItemInProject(item)
    
def main():

    file_paths = show_file_dialog()
    if not file_paths:
        return

    offset = 0
    for file_path in file_paths:
        # RPR.RPR_ShowConsoleMsg(file_path)
        # Parse haptic file
        amplitude_points, frequency_points, enphasis_points = parse_haptic_file(file_path)
        if amplitude_points is None or frequency_points is None:
            RPR.RPR_ShowMessageBox("No Points found", "Error", 0)

        # Get tracks
        track_count = RPR.RPR_CountTracks(0)
        amplitude_track, frequency_track, emphasis_track = None, None, None

        for i in range(track_count):
            track = RPR.RPR_GetTrack(0, i)
            _, _, _, track_name, _ = RPR.RPR_GetSetMediaTrackInfo_String(track, "P_NAME", "", False)
            if track_name.lower() == "amplitude":
                amplitude_track = track
            elif track_name.lower() == "frequency":
                frequency_track = track
            elif track_name.lower() == "emphasis":
                emphasis_track = track

        if not amplitude_track or not frequency_track or not emphasis_track:
            RPR.RPR_ShowMessageBox("Ensure tracks named 'amplitude' and 'frequency' and 'emphasis' exist.", "Error", 0)
            return

        start_time = cursor_position + offset
        end_time = start_time + max(pt['time'] for pt in amplitude_points + frequency_points)
        # Create envelope points
        success_amp = create_envelope(amplitude_track, "Pan", amplitude_points, "amplitude", start_time,end_time)
        success_freq = create_envelope(frequency_track, "Pan", frequency_points, "frequency", start_time,end_time)
        success_emph = create_envelope(emphasis_track, "Pan", enphasis_points, "emphasis", start_time,end_time)

        if not success_amp and not success_freq and not success_emph:
            return

        # Create region
        region_name = os.path.splitext(os.path.basename(file_path))[0]
        #RPR.RPR_ShowMessageBox(f"Imported and created: {region_name}", "Success", 0)
        HapticId = int(RPR.RPR_GetExtState("ReaHaptics", "LastHapticId")) + 1
        RPR.RPR_SetExtState("ReaHaptics", "LastHapticId", HapticId, True)
        create_item(region_name, start_time, end_time, "amplitude", HapticId)
        create_item(region_name, start_time, end_time, "frequency", HapticId)
        create_item(region_name, start_time, end_time, "emphasis", HapticId)
        create_item(region_name, start_time, end_time, "haptics", HapticId)

        offset = offset + end_time - start_time + 2
        RPR.RPR_ShowConsoleMsg("offset" + str(offset) + "\n")

main()