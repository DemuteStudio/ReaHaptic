#[[
# * ReaScript Name: ReaHaptic_InsertEmphasis
# * Description: iserts an emphasis automation item on the enmphasis track
# * Author: Florian Heynen
# * Version: 1.0
#]]
import os
import reaper_python as RPR

def InsertEmphasisAtCursor():
    track_count = RPR.RPR_CountTracks(0)
    emphasis_track = None

    for i in range(track_count):
        track = RPR.RPR_GetTrack(0, i)
        _, _, _, track_name, _ = RPR.RPR_GetSetMediaTrackInfo_String(track, "P_NAME", "", False)
        if track_name.lower() == "emphasis":
            emphasis_track = track
    
    env = RPR.RPR_GetTrackEnvelopeByName(emphasis_track, "Pan")
    time = RPR.RPR_GetCursorPosition()
    value = 0.5
    tension = 0.5
    indx = RPR.RPR_InsertAutomationItem(env, -1, time, 0.07)  #collect created envelope points
    #RPR.RPR_ShowMessageBox(indx, "Error", 0)
    
    RPR.RPR_InsertEnvelopePointEx(env,indx, 0, value, 5, tension, False, True)
    RPR.RPR_SetEnvelopePointEx(env, indx, 0, time, value, 5, tension, False, True)
    RPR.RPR_DeleteEnvelopePointEx(env, indx, 1)

InsertEmphasisAtCursor()