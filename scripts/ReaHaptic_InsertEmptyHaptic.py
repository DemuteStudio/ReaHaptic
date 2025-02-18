# @version 1.0
# @author Florian Heynen

import os
import json
import reaper_python as RPR

# Globals
cursor_position = RPR.RPR_GetCursorPosition()
hapticName = "hap_defaultName"

def OpenRenderDialogueBox():
    """Display file type selection dialog."""
    default_choice =  "hap_defaultName"
    global hapticName

    retval, _, _, _, user_input, _ = RPR.RPR_GetUserInputs(
        "Insert empty haptic", 1, "name:", default_choice, 256
    )
    if retval:
        hapticName = user_input
        return True
    RPR.RPR_ShowMessageBox("Invalid file selected or operation canceled.", "Error", 0)
    return False

def create_region(region_name, start_time, end_time):
    """Create a new region in the project."""
    region_idx = RPR.RPR_AddProjectMarker2(0, True, start_time, end_time, region_name, -1, 0)
    if region_idx >= 0:
        return True
    else:
        RPR.RPR_ShowMessageBox("Failed to create region.", "Error", 0)
        return False
    
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
        RPR.RPR_SetMediaItemPosition(item, RPR.RPR_GetCursorPosition(), False)
        RPR.RPR_SetMediaItemLength(item, end_time - start_time + 0.1, True)
        RPR.RPR_SetMediaItemInfo_Value(item, "I_GROUPID", Id)

def create_envelope(track, env_name, start_time, end_time):
    """Create envelope points on a given envelope."""
    env = RPR.RPR_GetTrackEnvelopeByName(track, env_name)
    RPR.RPR_DeleteEnvelopePointRange(env, start_time, end_time)
    if not env:
        RPR.RPR_ShowMessageBox(f"Envelope '{env_name}' not found on track.", "Error", 0)
        return False
    RPR.RPR_InsertEnvelopePoint(env, start_time, -1, 0, 0, False, True)# Add a point at the beginning of the region
    
    RPR.RPR_InsertEnvelopePoint(env, end_time, -1, 0, 0, False, True)# Add a point at the end of the region
    RPR.RPR_Envelope_SortPoints(env)
    return True

def main():
    if not OpenRenderDialogueBox():
        return
    
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

    end_time = cursor_position + 1

    create_envelope(amplitude_track, "Pan", cursor_position, end_time)
    create_envelope(frequency_track, "Pan", cursor_position, end_time)
    create_envelope(emphasis_track, "Pan", cursor_position, end_time)
    
    HapticId = int(RPR.RPR_GetExtState("Haptics", "LastHapticId")) + 1
    RPR.RPR_SetExtState("Haptics", "LastHapticId", HapticId, True)# Create region

    create_item(hapticName, cursor_position, end_time, "amplitude", HapticId)
    create_item(hapticName, cursor_position, end_time, "frequency", HapticId)
    create_item(hapticName, cursor_position, end_time, "emphasis", HapticId)
    create_item(hapticName, cursor_position, end_time, "haptics", HapticId)
    RPR.RPR_ShowMessageBox(f"Created: {hapticName}", "Success", 0)

main()