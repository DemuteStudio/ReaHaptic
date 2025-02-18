

import reaper_python as RPR

def create_track_at_index(index, track_name, color, folder_depth=0):
    """Create a new track at the specified index with the given name and folder depth."""
    RPR.RPR_InsertTrackAtIndex(index, True)  # Insert a new track at the specified index
    track = RPR.RPR_GetTrack(0, index)  # Get the newly created track
    RPR.RPR_GetSetMediaTrackInfo_String(track, "P_NAME", track_name, True)  # Set track name
    RPR.RPR_SetTrackColor(track, color)
    RPR.RPR_SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", folder_depth)  # Set folder depth
    return track

def ensure_envelope_exists(track, envelope_name):
    """Ensure an envelope exists by adding a point if necessary."""
    RPR.RPR_SetMediaTrackInfo_Value(track, "I_AUTOMODE", 1)  # Set automation mode to 'Read'
    envelope = RPR.RPR_GetTrackEnvelopeByChunkName(track, "<PANENV2")
    RPR.RPR_GetSetEnvelopeInfo_String(envelope, "ACTIVE", "1", True)
    RPR.RPR_GetSetEnvelopeInfo_String(envelope, "ARM", "1", True)
    RPR.RPR_GetSetEnvelopeInfo_String(envelope, "VISIBLE", "1", True)
    RPR.RPR_GetSetEnvelopeInfo_String(envelope, "SHOWLANE", "0", True)
    RPR.RPR_InsertEnvelopePoint(envelope,0,-1,0,0,False,True)
    #RPR.RPR_ShowMessageBox(envelope, "Error", 0)
    if envelope == 0:
        raise Exception(f"Failed to create {envelope_name} envelope.")
    return envelope

    

def main():
    # Get the total number of tracks (to insert at the top)
    num_tracks = RPR.RPR_CountTracks(0)
    RPR.RPR_SetExtState("ReaHaptics", "LastHapticId", 0, True)
    RPR.RPR_SetExtState("ReaHaptics", "IPAddress", "127.0.0.1", True)
    RPR.RPR_SetExtState("ReaHaptics", "Port", "7401", True)
    # Create the parent track ("Haptics") at the top
    create_track_at_index(0, "haptics",RPR.RPR_ColorToNative(145, 148, 174), folder_depth=1)

    # Create child tracks under the parent
    amplitude_track = create_track_at_index(1, "amplitude",RPR.RPR_ColorToNative(92, 78, 105), folder_depth=0, )
    frequency_track = create_track_at_index(2, "frequency",RPR.RPR_ColorToNative(18, 120, 87), folder_depth=0)
    emphasis_track = create_track_at_index(3, "emphasis",RPR.RPR_ColorToNative(65, 77, 131), folder_depth=-1)  # Close the folder

    for track, envelope_name in [(amplitude_track, "Pan"), (frequency_track, "Pan"), (emphasis_track, "Pan")]:
        ensure_envelope_exists(track, envelope_name)
        RPR.RPR_TrackList_AdjustWindows(False)

    RPR.RPR_UpdateArrange()  # Refresh the arrangement to reflect changes

main()