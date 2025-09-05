#!/usr/bin/env bash
# screentool_record_obs.sh
# OBS Studio-based recording system for screentool
# Uses OBS binary with launch flags for simple, reliable control

# Note: removed set -euo pipefail to avoid affecting main script

# OBS configuration - EVERYTHING goes in ST_DIR
OBS_COLLECTION_NAME="${OBS_COLLECTION_NAME:-Untitled}"
OBS_PROFILE_NAME="${OBS_PROFILE_NAME:-ScreenTool}"
OBS_SCENE_NAME="${OBS_SCENE_NAME:-M2-Bedroom 2}"
OBS_OUTPUT_DIR="${OBS_OUTPUT_DIR:-$ST_DIR}"  # Direct to ST_DIR
OBS_CONFIG_DIR="$HOME/Library/Application Support/obs-studio"

# OBS executable path
OBS_EXECUTABLE="/Applications/OBS.app/Contents/MacOS/obs"

# Check dependencies (much simpler now)
check_dependencies() {
    # Only need basic tools now
    local missing=()
    for bin in osascript; do
        if ! command -v "$bin" >/dev/null; then
            missing+=("$bin")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "❌ Missing dependencies: ${missing[*]}"
        return 1
    fi
    return 0
}

# Check if OBS is installed
check_obs_installation() {
    if [[ ! -f "$OBS_EXECUTABLE" ]]; then
        echo "❌ OBS Studio not found at $OBS_EXECUTABLE"
        echo "Please install OBS Studio from https://obsproject.com/"
        return 1
    fi
    
    echo "✅ OBS Studio found at $OBS_EXECUTABLE"
    return 0
}

# Check if OBS is running
is_obs_running() {
    pgrep -f "OBS.app" >/dev/null
}

# Ensure OBS output directory is under ST_DIR
setup_obs_output_dir() {
    # Make sure ST_DIR is set
    if [[ -z "$ST_DIR" ]]; then
        echo "❌ ST_DIR not set! Cannot proceed."
        echo "Run: source env.sh"
        return 1
    fi
    
    # OBS_OUTPUT_DIR is already set to ST_DIR
    # Individual recordings will create their own epoch directories
    mkdir -p "$ST_DIR"
    
    echo "✅ OBS output directory: $OBS_OUTPUT_DIR"
    echo "💡 All recordings stay within ST_DIR: $ST_DIR"
    
    return 0
}

# Create OBS profile and scene configuration files
create_obs_profile() {
    local profile_name="${1:-$OBS_PROFILE_NAME}"
    local output_dir="${2:-$OBS_OUTPUT_DIR}"
    
    echo "🔧 Creating OBS profile: $profile_name"
    
    # Create profile directory
    local profile_dir="$OBS_CONFIG_DIR/basic/profiles/$profile_name"
    mkdir -p "$profile_dir"
    
    # Create basic.ini with our settings
    cat > "$profile_dir/basic.ini" << EOF
[General]
Name=$profile_name

[Output]
Mode=Simple
FilenameFormatting=%CCYY-%MM-%DD %hh-%mm-%ss
DelayEnable=false
DelaySec=20
DelayPreserve=true
Reconnect=true
RetryDelay=2
MaxRetries=25
BindIP=default
IPFamily=IPv4+IPv6
NewSocketLoopEnable=false
LowLatencyEnable=false

[Stream1]
IgnoreRecommended=false
EnableMultitrackVideo=false
MultitrackVideoMaximumAggregateBitrateAuto=true
MultitrackVideoMaximumVideoTracksAuto=true

[SimpleOutput]
FilePath=$output_dir
RecFormat2=mkv
VBitrate=2500
ABitrate=160
UseAdvanced=false
Preset=veryfast
NVENCPreset2=p5
RecQuality=Stream
RecRB=false
RecRBTime=20
RecRBSize=512
RecRBPrefix=Replay
StreamAudioEncoder=CoreAudio_AAC
RecAudioEncoder=CoreAudio_AAC
RecTracks=1
StreamEncoder=x264
RecEncoder=x264

[AdvOut]
ApplyServiceSettings=true
UseRescale=false
TrackIndex=1
VodTrackIndex=2
Encoder=obs_x264
RecType=Standard
RecFilePath=$output_dir
RecFormat2=mkv
RecUseRescale=false
RecTracks=1
RecEncoder=none
FLVTrack=1
FFOutputToFile=true
FFFilePath=$output_dir
FFVBitrate=2500
FFVGOPSize=250
FFUseRescale=false
FFIgnoreCompat=false
FFABitrate=160
FFAudioMixes=1
Track1Bitrate=160
Track2Bitrate=160
Track3Bitrate=160
Track4Bitrate=160
Track5Bitrate=160
Track6Bitrate=160
RecSplitFileTime=15
RecSplitFileSize=2048
RecRB=false
RecRBTime=20
RecRBSize=512
AudioEncoder=CoreAudio_AAC
RecAudioEncoder=CoreAudio_AAC
RecSplitFileType=Time
FFFormat=
FFFormatMimeType=
FFVEncoderId=0
FFVEncoder=
FFAEncoderId=0
FFAEncoder=
StreamMultiTrackAudioMixes=1
RescaleRes=1920x1080
RecRescaleRes=1920x1080
FFRescaleRes=1920x1080
RecFileNameWithoutSpace=true
RescaleFilter=3
FFFileNameWithoutSpace=true
FFExtension=mp4

[Video]
BaseCX=1920
BaseCY=1080
OutputCX=1920
OutputCY=1080
FPSType=0
FPSCommon=30
FPSInt=30
FPSNum=30
FPSDen=1
ScaleType=bilinear
ColorFormat=NV12
ColorSpace=709
ColorRange=Partial
SdrWhiteLevel=300
HdrNominalPeakLevel=1000

[Audio]
SampleRate=48000
ChannelSetup=Stereo
MeterDecayRate=23.53
PeakMeterType=0

[Panels]
CookieId=15215222527A24D2
EOF

    # Create streamEncoder.json
    cat > "$profile_dir/streamEncoder.json" << 'EOF'
{
    "presets": []
}
EOF

    echo "✅ Profile created: $profile_dir"
}

# Create OBS scene collection - let OBS handle the scene creation
create_obs_scene() {
    local scene_name="${1:-$OBS_SCENE_NAME}"
    local collection_name="${2:-$OBS_COLLECTION_NAME}"
    
    echo "🔧 Creating OBS scene: $scene_name"
    echo "💡 Using OBS auto-configuration for better compatibility"
    
    # Create scene collection directory
    mkdir -p "$OBS_CONFIG_DIR/basic/scenes"
    
    # Don't create scene files manually - let OBS create them
    # This prevents version compatibility issues
    echo "✅ Scene directory prepared: $OBS_CONFIG_DIR/basic/scenes"
    echo "💡 OBS will auto-create scene configuration on first launch"
}

# Calculate recording area based on screentool settings
calculate_recording_area() {
    local screen_geometry="${SCREEN_GEOMETRY:-}"
    local crop_geometry="${ST_CROP_GEOMETRY:-}"
    local crop_ui_elements="${ST_CROP_UI_ELEMENTS:-false}"
    local menu_bar_height="${ST_MENU_BAR_HEIGHT:-28}"
    local dock_height="${ST_DOCK_HEIGHT:-70}"
    
    # Default to current screen resolution if not set
    if [[ -z "$screen_geometry" ]]; then
        # Get current screen resolution using AppleScript
        local bounds
        bounds=$(osascript -e 'tell application "Finder" to get bounds of window of desktop' 2>/dev/null)
        if [[ -n "$bounds" ]]; then
            local width height
            width=$(echo "$bounds" | awk -F', ' '{print $3}')
            height=$(echo "$bounds" | awk -F', ' '{print $4}')
            screen_geometry="${width}x${height}+0+0"
        else
            # Fallback to common resolution
            screen_geometry="1920x1080+0+0"
        fi
    fi
    
    # Parse screen geometry
    local screen_width screen_height screen_x screen_y
    if [[ "$screen_geometry" =~ ^([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+)$ ]]; then
        screen_width="${BASH_REMATCH[1]}"
        screen_height="${BASH_REMATCH[2]}"
        screen_x="${BASH_REMATCH[3]}"
        screen_y="${BASH_REMATCH[4]}"
    else
        echo "❌ Invalid screen geometry: $screen_geometry"
        return 1
    fi
    
    # Calculate recording area
    local rec_x="$screen_x"
    local rec_y="$screen_y"
    local rec_width="$screen_width"
    local rec_height="$screen_height"
    
    # Apply UI cropping if enabled
    if [[ "$crop_ui_elements" == "true" ]]; then
        rec_y=$((rec_y + menu_bar_height))
        rec_height=$((rec_height - menu_bar_height - dock_height))
        echo "🎯 UI cropping enabled: excluding menu bar (${menu_bar_height}px) and dock (${dock_height}px)"
    fi
    
    # Apply custom crop geometry if set
    if [[ -n "$crop_geometry" ]] && [[ "$crop_geometry" =~ ^([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+)$ ]]; then
        rec_width="${BASH_REMATCH[1]}"
        rec_height="${BASH_REMATCH[2]}"
        rec_x="${BASH_REMATCH[3]}"
        rec_y="${BASH_REMATCH[4]}"
        echo "🎯 Custom crop geometry applied: ${rec_width}x${rec_height} at ${rec_x},${rec_y}"
    fi
    
    # Export calculated values
    export OBS_RECORD_X="$rec_x"
    export OBS_RECORD_Y="$rec_y"
    export OBS_RECORD_WIDTH="$rec_width"
    export OBS_RECORD_HEIGHT="$rec_height"
    
    echo "📐 Recording area: ${rec_width}x${rec_height} at position ${rec_x},${rec_y}"
}

# Start OBS with recording
start_obs_recording() {
    local collection="${1:-$OBS_COLLECTION_NAME}"
    local profile="${2:-$OBS_PROFILE_NAME}"
    local scene="${3:-$OBS_SCENE_NAME}"
    
    echo "🎬 Starting OBS recording with binary flags..."
    echo "Collection: $collection"
    echo "Profile: $profile"
    echo "Scene: $scene"
    
    # Build OBS command with launch flags
    local obs_cmd=(
        "$OBS_EXECUTABLE"
        --collection "$collection"
        --profile "$profile"
        --scene "$scene"
        --startrecording
        --minimize-to-tray
    )
    
    echo "Command: ${obs_cmd[*]}"
    
    # Execute OBS with recording
    "${obs_cmd[@]}" &
    local obs_pid=$!
    
    echo "✅ OBS started with PID: $obs_pid"
    echo "🎬 Recording should start automatically"
    
    # Handle OBS Safe Mode dialog if it appears
    sleep 2
    if pgrep -f "OBS.app" >/dev/null; then
        # Try to dismiss safe mode dialog by clicking "Run Normally"
        osascript -e 'tell application "System Events" to keystroke return' 2>/dev/null || true
        sleep 1
    fi
    
    return 0
}

# Stop OBS recording (using AppleScript/hotkeys)
stop_obs_recording() {
    echo "⏹️  Stopping OBS recording..."
    
    if is_obs_running; then
        # Try to use OBS hotkey to stop recording (Cmd+Shift+R is default)
        osascript -e 'tell application "OBS" to activate' 2>/dev/null
        sleep 1
        osascript -e 'tell application "System Events" to keystroke "r" using {command down, shift down}' 2>/dev/null
        
        echo "✅ Stop recording command sent via hotkey"
        echo "💡 Recording should stop in OBS"
        return 0
    else
        echo "❌ OBS is not running"
        return 1
    fi
}

# Quit OBS completely with force cleanup
quit_obs() {
    echo "🛑 Quitting OBS..."
    
    if is_obs_running; then
        # Try graceful quit first
        osascript -e 'tell application "OBS" to quit' 2>/dev/null
        
        # Wait for OBS to quit gracefully
        local timeout=5
        local count=0
        while is_obs_running && [[ $count -lt $timeout ]]; do
            sleep 1
            ((count++))
        done
        
        # Force kill if still running
        if is_obs_running; then
            echo "⚠️ Force killing OBS..."
            pkill -f "OBS.app" 2>/dev/null || true
            sleep 2
        fi
        
        if ! is_obs_running; then
            echo "✅ OBS quit successfully"
            return 0
        else
            echo "⚠️ OBS may still be running"
            return 1
        fi
    else
        echo "✅ OBS is not running"
        return 0
    fi
}

# Emergency cleanup function
emergency_cleanup() {
    echo "🚨 Emergency cleanup..."
    pkill -f "OBS.app" 2>/dev/null || true
    pkill -f "ffplay" 2>/dev/null || true
    pkill -f "obs" 2>/dev/null || true
    echo "✅ All processes killed"
}

# Main OBS recording function (replaces record_mac)
record_obs() {
    local prefix duration recording_id recording_dir recording_path
    prefix="${1:-screen}"
    duration="${2:-}"  # Optional duration parameter
    recording_id="$(date +%s)"
    recording_dir="$ST_DIR/$recording_id"
    
    # Create recording directory
    mkdir -p "$recording_dir"
    
    # OBS will save directly to the recording directory
    recording_path="$recording_dir/recording.mkv"
    
    echo "🎬 ScreenTool OBS Recording (Binary Mode)"
    echo "========================================"
    echo "Recording ID: $recording_id"
    echo "Session directory: $recording_dir"
    echo "Final path: $recording_path"
    echo
    
    # Check dependencies
    if ! check_dependencies; then
        return 1
    fi
    
    # Check OBS installation
    if ! check_obs_installation; then
        return 1
    fi
    
    # Ensure OBS profile exists and is configured for this recording directory
    echo "🔧 Updating OBS profile for recording directory: $recording_dir"
    create_obs_profile "$OBS_PROFILE_NAME" "$recording_dir"
    
    # Force quit OBS if running (needed for profile switching)
    if is_obs_running; then
        echo "⏹️  Force quitting OBS to apply new settings..."
        pkill -f "OBS.app" 2>/dev/null || true
        sleep 2
        echo "✅ OBS stopped"
    fi
    
    # Calculate recording area
    calculate_recording_area
    
    # Create recording metadata
    cat > "$recording_dir/recording.meta" << EOF
RECORDING_NAME="$prefix"
RECORDING_ID="$recording_id"
RECORDING_PATH="$recording_path"
RECORDING_LOG="recording.log"
START_TIME="$(date)"
RECORDING_METHOD="obs_binary"
OBS_COLLECTION="$OBS_COLLECTION_NAME"
OBS_PROFILE="$OBS_PROFILE_NAME"
OBS_SCENE="$OBS_SCENE_NAME"
OBS_RECORD_X="$OBS_RECORD_X"
OBS_RECORD_Y="$OBS_RECORD_Y"
OBS_RECORD_WIDTH="$OBS_RECORD_WIDTH"
OBS_RECORD_HEIGHT="$OBS_RECORD_HEIGHT"
SCREEN_GEOMETRY="$SCREEN_GEOMETRY"
CROP_GEOMETRY="$ST_CROP_GEOMETRY"
CROP_UI_ELEMENTS="$ST_CROP_UI_ELEMENTS"
RECORDING_FORMAT="mkv"
EDIT_FORMAT="mkv"
FINAL_FORMAT="mp4"
EOF
    
    # Update latest symlink
    local latest_link="$ST_DIR/latest"
    rm -f "$latest_link"
    ln -sf "$recording_id" "$latest_link"
    echo "Updated latest -> $recording_id"
    echo
    
    # Start recording with OBS profile
    if start_obs_recording "$OBS_COLLECTION_NAME" "$OBS_PROFILE_NAME" "$OBS_SCENE_NAME"; then
        echo
        echo "🎬 Recording in progress..."
        echo "💡 To stop recording:"
        echo "   • Press Cmd+Shift+R in OBS"
        echo "   • Or run: st stop-recording"
        echo "   • Or press Ctrl+C here"
        echo
        
        # If duration is specified, wait and then stop
        if [[ -n "$duration" ]] && [[ "$duration" =~ ^[0-9]+$ ]]; then
            echo "⏱️  Recording for $duration seconds..."
            sleep "$duration"
            stop_obs_recording
            sleep 2  # Give OBS time to finish writing file
        else
            echo "⏱️  Recording until stopped manually..."
            echo "Press Ctrl+C to stop recording"
            
            # Wait for user interrupt with better cleanup
            trap 'echo; echo "⏹️  Stopping recording..."; stop_obs_recording; sleep 2; quit_obs; echo "Recording stopped by user"; exit 0' INT
            
            # Keep the script running until user stops it
            echo "Press Ctrl+C to stop..."
            local count=0
            while true; do
                sleep 1
                ((count++))
                # Auto-quit if OBS crashes or stops responding
                if ! is_obs_running && [[ $count -gt 5 ]]; then
                    echo "⚠️  OBS stopped unexpectedly"
                    break
                fi
            done
        fi
        
        # Check for the recorded file (OBS saves directly to recording directory)
        echo
        echo "🔍 Checking for recorded file..."
        
        # Wait for file to be fully written (OBS needs time to finalize)
        echo "⏳ Waiting for OBS to finalize recording..."
        sleep 8
        
        # Additional wait if no file found yet
        local attempts=0
        while [[ $attempts -lt 3 ]]; do
            local check_file
            check_file=$(find "$recording_dir" -name "*.mkv" -o -name "*.mp4" -o -name "*.mov" | head -1)
            if [[ -n "$check_file" ]] && [[ -f "$check_file" ]]; then
                break
            fi
            echo "⏳ Still waiting for OBS file... (attempt $((attempts + 1)))"
            sleep 3
            ((attempts++))
        done
        
        # Look for any .mkv or .mov file in the recording directory
        local actual_file
        actual_file=$(find "$recording_dir" \( -name "*.mkv" -o -name "*.mov" \) | head -1)
        
        if [[ -n "$actual_file" ]] && [[ -f "$actual_file" ]]; then
            echo "✅ Found recorded file: $(basename "$actual_file")"
            
            # Rename to a standard name if it's not already named recording.mkv
            if [[ "$(basename "$actual_file")" != "recording.mkv" ]]; then
                echo "📝 Renaming to recording.mkv..."
                mv "$actual_file" "$recording_path"
                actual_file="$recording_path"
            fi
            
            # Update metadata
            cat >> "$recording_dir/recording.meta" << EOF
END_TIME="$(date)"
RECORDING_COMPLETE="true"
ACTUAL_OUTPUT_FILE="$(basename "$actual_file")"
EOF
            
            # Get file info
            local file_size
            file_size=$(stat -f "%z" "$actual_file" 2>/dev/null)
            if [[ -n "$file_size" ]]; then
                file_size=$(echo "$file_size" | awk '{printf "%.1fMB", $1/1024/1024}')
                echo "📊 Recording size: $file_size"
            fi
            
            echo
            echo "✅ OBS Recording completed successfully!"
            echo "📁 Session: $recording_id"
            echo "🎬 File: $actual_file"
            echo "▶️  Play: st play latest"
            echo "✏️  Edit: st edit $recording_id"
            
            # Profile is permanent, no cleanup needed
            
        else
            echo "⚠️  Could not find recorded file in: $recording_dir"
            echo "💡 Check OBS profile configuration and try again"
            
            # Update metadata to reflect issue
            cat >> "$recording_dir/recording.meta" << EOF
END_TIME="$(date)"
RECORDING_COMPLETE="false"
FAILURE_REASON="Could not locate OBS output file"
EOF
            return 1
        fi
        
    else
        echo "❌ Failed to start OBS recording"
        return 1
    fi
}

# Stop recording function for external use
stop_recording() {
    stop_obs_recording
}

# Check OBS status
obs_status() {
    echo "OBS Studio Status (Binary Mode)"
    echo "==============================="
    
    if check_obs_installation; then
        echo "✅ OBS Studio: Installed"
    else
        echo "❌ OBS Studio: Not found"
        return 1
    fi
    
    if is_obs_running; then
        echo "✅ OBS Process: Running"
        
        # Get OBS process info
        local obs_pid
        obs_pid=$(pgrep -f "OBS.app" | head -1)
        if [[ -n "$obs_pid" ]]; then
            echo "📊 Process ID: $obs_pid"
            
            # Get memory usage
            local memory_usage
            memory_usage=$(ps -o rss= -p "$obs_pid" 2>/dev/null | awk '{printf "%.1fMB", $1/1024}')
            if [[ -n "$memory_usage" ]]; then
                echo "💾 Memory usage: $memory_usage"
            fi
        fi
    else
        echo "⏸️  OBS Process: Not running"
    fi
    
    echo
    echo "Configuration:"
    echo "  Collection: $OBS_COLLECTION_NAME"
    echo "  Profile: $OBS_PROFILE_NAME"
    echo "  Scene: $OBS_SCENE_NAME"
    echo "  OBS Output Directory: $OBS_OUTPUT_DIR"
    echo "  ScreenTool Directory: ${ST_DIR:-not set}"
    echo "  Recording Area: ${OBS_RECORD_WIDTH:-auto}x${OBS_RECORD_HEIGHT:-auto}"
    echo "  UI Cropping: ${ST_CROP_UI_ELEMENTS:-false}"
    echo
    if [[ "$OBS_OUTPUT_DIR" == *"Movies"* ]]; then
        echo "⚠️  WARNING: OBS output directory contains 'Movies'"
        echo "   This should be under ST_DIR only!"
        echo "   Run 'st obs-config' to fix this."
    else
        echo "✅ OBS output directory is correctly under ST_DIR"
    fi
    echo "💡 All files stay within ScreenTool directory structure."
}

# Configuration helper
configure_obs() {
    echo "🎬 OBS Auto-Configuration (CLI Mode)"
    echo "===================================="
    echo
    echo "Creating OBS profile and scene automatically..."
    echo "No manual GUI setup required! 🚀"
    echo
    
    # Setup output directory first
    if ! setup_obs_output_dir; then
        return 1
    fi
    
    # Create profile with correct output path
    create_obs_profile "$OBS_PROFILE_NAME" "$OBS_OUTPUT_DIR"
    
    # Create scene collection
    create_obs_scene "$OBS_SCENE_NAME" "$OBS_COLLECTION_NAME"
    
    echo
    echo "✅ OBS Configuration Complete!"
    echo "=============================="
    echo "Profile: $OBS_PROFILE_NAME"
    echo "Scene Collection: $OBS_COLLECTION_NAME"
    echo "Scene: $OBS_SCENE_NAME"
    echo "Output Directory: $OBS_OUTPUT_DIR"
    echo
    echo "🎯 ScreenTool will use these launch flags:"
    echo "  --collection '$OBS_COLLECTION_NAME'"
    echo "  --profile '$OBS_PROFILE_NAME'"
    echo "  --scene '$OBS_SCENE_NAME'"
    echo "  --startrecording"
    echo
    echo "💡 Test the setup with:"
    echo "    st record test 5"
    echo
    echo "🔧 If you need to customize settings later:"
    echo "   - Open OBS and switch to the '$OBS_PROFILE_NAME' profile"
    echo "   - Modify display capture, audio sources, etc."
    echo "   - The output path is already set correctly!"
}