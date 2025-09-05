#!/usr/bin/env bash
# screentool_obs_helper.sh
# OBS Setup Assistant - Works WITH OBS, not against it

# Check if OBS is installed
check_obs_installation() {
    local obs_path="/Applications/OBS.app/Contents/MacOS/obs"
    if [[ -f "$obs_path" ]]; then
        echo "✅ OBS Studio found at: $obs_path"
        return 0
    else
        echo "❌ OBS Studio not found"
        echo "📥 Download from: https://obsproject.com/"
        return 1
    fi
}

# Show current OBS configuration
show_obs_config() {
    local obs_config_dir="$HOME/Library/Application Support/obs-studio"
    
    echo "🎬 OBS Studio Configuration"
    echo "=========================="
    echo
    
    if [[ ! -d "$obs_config_dir" ]]; then
        echo "❌ OBS configuration directory not found"
        echo "💡 Launch OBS Studio at least once to create configuration"
        return 1
    fi
    
    echo "📁 Config Directory: $obs_config_dir"
    echo
    
    # Show available profiles
    local profiles_dir="$obs_config_dir/basic/profiles"
    if [[ -d "$profiles_dir" ]]; then
        echo "📋 Available Profiles:"
        for profile in "$profiles_dir"/*; do
            if [[ -d "$profile" ]]; then
                local profile_name=$(basename "$profile")
                echo "  • $profile_name"
                
                # Show output directory if configured
                local basic_ini="$profile/basic.ini"
                if [[ -f "$basic_ini" ]]; then
                    local output_path=$(grep "^FilePath=" "$basic_ini" 2>/dev/null | cut -d'=' -f2)
                    if [[ -n "$output_path" ]]; then
                        echo "    Output: $output_path"
                    fi
                fi
            fi
        done
    else
        echo "❌ No profiles found"
    fi
    echo
    
    # Show available scene collections
    local scenes_dir="$obs_config_dir/basic/scenes"
    if [[ -d "$scenes_dir" ]]; then
        echo "🎭 Available Scene Collections:"
        for scene_file in "$scenes_dir"/*.json; do
            if [[ -f "$scene_file" ]]; then
                local scene_name=$(basename "$scene_file" .json)
                echo "  • $scene_name"
            fi
        done
    else
        echo "❌ No scene collections found"
    fi
    echo
}

# Create a new recording session directory
create_recording_session() {
    local recording_id="$(date +%s)"
    local recording_dir="$ST_DIR/$recording_id"
    
    mkdir -p "$recording_dir"
    
    # Update latest symlink
    local latest_link="$ST_DIR/latest"
    rm -f "$latest_link"
    ln -sf "$recording_id" "$latest_link"
    
    echo "$recording_dir"
}

# Suggest OBS setup for screentool workflow
suggest_obs_setup() {
    echo "🎯 Recommended OBS Setup for ScreenTool"
    echo "======================================="
    echo
    echo "IMPORTANT: ScreenTool uses epoch-based directory naming!"
    echo "Each recording gets its own directory: $ST_DIR/[timestamp]/"
    echo
    echo "1. 📋 Create a Profile called 'ScreenTool'"
    echo "   • File → Settings → Profiles → New"
    echo "   • Name: ScreenTool"
    echo
    echo "2. 📁 Configure Output Settings"
    echo "   • Settings → Output → Recording"
    echo "   • Recording Path: LEAVE BLANK (we'll set it per session)"
    echo "   • Recording Format: mkv (recommended)"
    echo "   • Filename Formatting: recording"
    echo "   ⚠️  DO NOT use timestamp in filename - we handle that with directories"
    echo
    echo "3. 🎭 Create Scene Collections"
    echo "   • Scene Collection → New"
    echo "   • Add Display Capture source"
    echo "   • Add Audio Input Capture if needed"
    echo
    echo "4. ⚙️  Configure Video Settings"
    echo "   • Settings → Video"
    echo "   • Base Resolution: ${SCREEN_GEOMETRY%+*} (your screen)"
    echo "   • Output Resolution: 1920x1080 (recommended)"
    echo "   • FPS: ${FRAMERATE:-30} (from your config)"
    echo
    echo "5. 🎵 Configure Audio Settings"
    echo "   • Settings → Audio"
    echo "   • Desktop Audio: Your system audio device"
    echo "   • Mic/Auxiliary Audio: Device ${ST_AVFOUNDATION_AUDIO_DEVICE:-1}"
    echo
    echo "6. 🎬 Recording Workflow with ScreenTool Integration"
    echo "   • Run: st obs new-session"
    echo "   • This creates: $ST_DIR/[timestamp]/ directory"
    echo "   • Manually set OBS recording path to that directory"
    echo "   • Start recording in OBS (Cmd+Shift+R)"
    echo "   • Stop recording when done"
    echo "   • File will be: $ST_DIR/[timestamp]/recording.mkv"
    echo
    echo "💡 For easier workflow, see: st obs workflow"
    echo
}

# Show current screentool configuration relevant to OBS
show_screentool_config() {
    echo "🔧 Current ScreenTool Configuration"
    echo "=================================="
    echo
    echo "📁 Recording Directory: $ST_DIR"
    echo "📐 Screen Geometry: ${SCREEN_GEOMETRY:-auto-detect}"
    echo "✂️  Crop Geometry: ${ST_CROP_GEOMETRY:-none}"
    echo "🎵 Audio Device: ${ST_AVFOUNDATION_AUDIO_DEVICE:-system default}"
    echo "📺 Video Device: ${ST_AVFOUNDATION_VIDEO_DEVICE:-screen capture}"
    echo
    echo "💡 These settings can guide your OBS configuration"
    echo
}

# Show recording workflow
show_workflow() {
    echo "🎬 ScreenTool + OBS Recording Workflow"
    echo "====================================="
    echo
    echo "STEP 1: Create New Recording Session"
    echo "   st obs new-session"
    echo "   → Creates timestamped directory"
    echo "   → Updates 'latest' symlink"
    echo
    echo "STEP 2: Set OBS Recording Path"
    echo "   • Open OBS Studio"
    echo "   • Go to Settings → Output → Recording"
    echo "   • Set Recording Path to the directory from Step 1"
    echo "   • Set Filename Formatting to: recording"
    echo
    echo "STEP 3: Record"
    echo "   • Start Recording in OBS (Cmd+Shift+R)"
    echo "   • Record your content"
    echo "   • Stop Recording (Cmd+Shift+R again)"
    echo
    echo "STEP 4: Use ScreenTool Pipeline"
    echo "   st list              # See your recordings"
    echo "   st play latest       # Play the recording"
    echo "   st edit latest       # Edit to 1080p"
    echo "   st final latest      # Export final MP4"
    echo
    echo "💡 The directory structure will be:"
    echo "   $ST_DIR/[timestamp]/"
    echo "   ├── recording.mkv    # OBS output"
    echo "   ├── edit.mkv         # After st edit"
    echo "   ├── final.mp4        # After st final"
    echo "   └── recording.meta   # Metadata"
    echo
}

# Create OBS profile for this recording session
create_obs_profile_for_session() {
    local recording_dir="$1"
    local profile_name="ScreenTool"
    local obs_config_dir="$HOME/Library/Application Support/obs-studio"
    local profiles_dir="$obs_config_dir/basic/profiles"
    local profile_dir="$profiles_dir/$profile_name"
    
    # Create profiles directory if it doesn't exist
    mkdir -p "$profiles_dir"
    
    # Remove old session-specific profiles
    find "$profiles_dir" -type d -name "ScreenTool_*" -exec rm -rf {} +
    
    # Ensure the ScreenTool profile directory exists
    mkdir -p "$profile_dir"
    
    # Create basic.ini with session-specific settings
    cat > "$profile_dir/basic.ini" << EOF
[General]
Name=$profile_name

[Output]
Mode=Advanced
FilenameFormatting=recording
DelayEnable=false

[SimpleOutput]
FilePath=$recording_dir
RecFormat2=mkv
VBitrate=2500
ABitrate=160
UseAdvanced=false
Preset=veryfast
RecQuality=Stream
RecTracks=3
StreamEncoder=obs_x264
RecEncoder=obs_x264

[AdvOut]
RecType=Standard
RecFilePath=$recording_dir
RecFormat2=mkv
RecTracks=3
RecEncoder=obs_x264
Track1Bitrate=160
Track2Bitrate=160
Track3Bitrate=160

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

[Audio]
SampleRate=48000
ChannelSetup=Stereo
EOF
    
    # Update global configuration to use this profile
    local global_config="$obs_config_dir/global.ini"
    mkdir -p "$(dirname "$global_config")"
    cat > "$global_config" << EOF
[General]
CurrentProfile=$profile_name
CurrentSceneCollection=$profile_name
EOF
    
    echo "✅ Created/Updated OBS profile: $profile_name"
    echo "📁 OBS Profile: $profile_dir"
    echo "📁 Output directory: $recording_dir"
    echo "📄 Filename: recording.mkv"
    
    # Return the profile name
    echo "$profile_name"
}

# Create new recording session
new_recording_session() {
    local recording_dir
    recording_dir=$(create_recording_session)
    local recording_id=$(basename "$recording_dir")
    
    echo "📁 New Recording Session Created"
    echo "==============================="
    echo
    echo "Session ID: $recording_id"
    echo "Directory: $recording_dir"
    echo
    
    # Create OBS profile for this session and capture the profile name
    echo
    local profile_name
    profile_name=$(create_obs_profile_for_session "$recording_dir" | tail -1)
    
    echo
    echo "🎯 Next Steps:"
    echo "1. Launch OBS with profile: st obs launch $recording_id"
    echo "2. Start recording (Cmd+Shift+R)"
    echo "   → Will save as: $recording_dir/recording.mkv"
    echo
    echo "💡 When done recording, use:"
    echo "   st play latest"
    echo "   st edit latest"
    echo "   st final latest"
    echo
    echo "🚀 Want to launch OBS now? Run: st obs launch $recording_id"
    echo
    
    # Create metadata file
    cat > "$recording_dir/recording.meta" << EOF
RECORDING_ID="$recording_id"
RECORDING_PATH="$recording_dir/recording.mkv"
START_TIME="$(date)"
RECORDING_METHOD="obs_profile"
SCREEN_GEOMETRY="$SCREEN_GEOMETRY"
CROP_GEOMETRY="$ST_CROP_GEOMETRY"
CROP_UI_ELEMENTS="$ST_CROP_UI_ELEMENTS"
RECORDING_FORMAT="mkv"
EDIT_FORMAT="mkv"
FINAL_FORMAT="mp4"
OBS_PROFILE="$profile_name"
EOF
    
    echo "✅ Session metadata created"
}

# Launch OBS with specific profile
launch_obs() {
    local session_id_or_profile="${1:-}"
    local obs_executable="/Applications/OBS.app/Contents/MacOS/obs"
    local profile_name="ScreenTool"
    local recording_dir=""
    
    # Determine recording directory if a session ID is provided
    if [[ -n "$session_id_or_profile" ]]; then
        # Check if it's a numeric session ID
        if [[ "$session_id_or_profile" =~ ^[0-9]+$ ]]; then
            recording_dir="$ST_DIR/$session_id_or_profile"
            
            # Verify the recording directory exists
            if [[ ! -d "$recording_dir" ]]; then
                echo "❌ Recording session $session_id_or_profile not found"
                echo "💡 Available sessions:"
                ls "$ST_DIR" | grep -E '^[0-9]+$' || echo "  No sessions found"
                return 1
            fi
            
            # Update the profile's recording path
            local profile_dir="$HOME/Library/Application Support/obs-studio/basic/profiles/$profile_name"
            sed -i '' "s|FilePath=.*|FilePath=$recording_dir|g" "$profile_dir/basic.ini"
            sed -i '' "s|RecFilePath=.*|RecFilePath=$recording_dir|g" "$profile_dir/basic.ini"
        else
            # Treat as a specific profile name
            profile_name="$session_id_or_profile"
        fi
    else
        # No argument - use latest session
        local latest_dir="$ST_DIR/latest"
        if [[ -L "$latest_dir" ]]; then
            recording_dir=$(readlink "$latest_dir")
            recording_dir="$ST_DIR/$recording_dir"
        fi
    fi
    
    echo "🚀 Launching OBS Studio with profile: $profile_name"
    
    if [[ ! -f "$obs_executable" ]]; then
        echo "❌ OBS Studio not found at $obs_executable"
        return 1
    fi
    
    # Check if profile exists
    local profile_dir="$HOME/Library/Application Support/obs-studio/basic/profiles/$profile_name"
    if [[ ! -d "$profile_dir" ]]; then
        echo "❌ Profile '$profile_name' not found"
        echo "💡 Available profiles:"
        ls "$HOME/Library/Application Support/obs-studio/basic/profiles/" | grep ScreenTool || echo "  None found"
        return 1
    fi
    
    # Show session info if applicable
    if [[ -n "$recording_dir" ]]; then
        echo "📁 Session: $(basename "$recording_dir")"
        echo "📂 Directory: $recording_dir"
    fi
    
    # Launch OBS with the specific profile
    "$obs_executable" --profile "$profile_name" &
    local obs_pid=$!
    
    echo "✅ OBS Studio launched with profile: $profile_name"
    echo "📊 Process ID: $obs_pid"
    echo "🎬 Ready to record - press Cmd+Shift+R to start/stop"
    echo
}

# Get track information for the latest recording
get_recording_track_info() {
    local track_number="${1:-all}"
    local latest_recording_dir="$ST_DIR/latest"
    
    # Verify latest recording exists
    if [[ ! -L "$latest_recording_dir" ]]; then
        echo "❌ No latest recording found"
        echo "💡 Run 'st obs new-session' to create a recording session"
        return 1
    fi
    
    # Find the latest recording.mkv file
    local recording_file
    recording_file=$(find "$ST_DIR" -type f -name "recording*.mkv" | sort -n | tail -1)
    
    if [[ -z "$recording_file" ]]; then
        echo "❌ No recording files found"
        return 1
    fi
    
    echo "🎬 Recording File: $recording_file"
    echo "========================="
    
    # Use ffprobe to get track information
    if [[ "$track_number" == "all" ]]; then
        # Show all track details
        ffprobe -v quiet -print_format json -show_streams "$recording_file"
    else
        # Show specific track details
        ffprobe -v quiet -select_streams a:"$((track_number-1))" -show_streams "$recording_file"
    fi
}

# Initialize OBS with ScreenTool preset configuration
initialize_obs_config() {
    local obs_config_dir="$HOME/Library/Application Support/obs-studio"
    local profiles_dir="$obs_config_dir/basic/profiles"
    local scenes_dir="$obs_config_dir/basic/scenes"
    
    # Create necessary directories
    mkdir -p "$profiles_dir"
    mkdir -p "$scenes_dir"
    
    # Create ScreenTool profile
    local profile_dir="$profiles_dir/ScreenTool"
    mkdir -p "$profile_dir"
    
    # Create basic configuration file
    cat > "$profile_dir/basic.ini" << EOF
[General]
Name=ScreenTool

[Output]
Mode=Advanced
FilenameFormatting=recording

[SimpleOutput]
RecFormat2=mkv
VBitrate=2500
ABitrate=160
Preset=veryfast
RecQuality=Stream
RecTracks=3

[AdvOut]
RecType=Standard
RecFormat2=mkv
RecTracks=3
RecEncoder=obs_x264

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

[Audio]
SampleRate=48000
ChannelSetup=Stereo
EOF

    # Create a basic scene collection
    cat > "$scenes_dir/ScreenTool.json" << EOF
{
    "AuxAudioDeviceList": [],
    "current_scene": "Screen Capture",
    "scene_order": [
        {
            "name": "Screen Capture"
        }
    ],
    "sources": [
        {
            "name": "Screen Capture",
            "type": "screen_capture",
            "settings": {
                "display": 0
            }
        }
    ]
}
EOF

    # Create global configuration
    mkdir -p "$obs_config_dir"
    cat > "$obs_config_dir/global.ini" << EOF
[General]
CurrentProfile=ScreenTool
CurrentSceneCollection=ScreenTool
EOF

    # Set up global settings
    cat > "$obs_config_dir/basic.ini" << EOF
[General]
ConfigVersion=2.0

[Output]
Mode=Advanced
EOF

    echo "✅ OBS Configuration Initialized"
    echo "   - Profile: ScreenTool"
    echo "   - Scene Collection: ScreenTool"
    echo "   - Configuration Path: $obs_config_dir"
    echo
    echo "💡 Next Steps:"
    echo "   1. Verify audio/video sources"
    echo "   2. Adjust settings as needed"
    echo "   3. Use 'st obs launch' to start OBS"
}

# Scene management functions
list_obs_scenes() {
    local obs_config_dir="$HOME/Library/Application Support/obs-studio"
    local scenes_dir="$obs_config_dir/basic/scenes"
    
    echo "🎭 OBS Scene Collections"
    echo "======================="
    
    if [[ ! -d "$scenes_dir" ]]; then
        echo "❌ No scene collections found"
        return 1
    fi
    
    # List scene collections
    for scene_file in "$scenes_dir"/*.json; do
        if [[ -f "$scene_file" ]]; then
            local scene_name=$(basename "$scene_file" .json)
            echo "• $scene_name"
            
            # Optional: Show basic scene details
            jq -r '.scene_order[].name' "$scene_file" 2>/dev/null | sed 's/^/  - Scene: /'
        fi
    done
}

# Get detailed information about a specific scene collection
get_scene_info() {
    local scene_name="${1:-ScreenTool}"
    local obs_config_dir="$HOME/Library/Application Support/obs-studio"
    local scene_file="$obs_config_dir/basic/scenes/$scene_name.json"
    
    if [[ ! -f "$scene_file" ]]; then
        echo "❌ Scene collection '$scene_name' not found"
        return 1
    fi
    
    echo "🎬 Scene Collection: $scene_name"
    echo "========================="
    
    # Show detailed scene information
    echo "Scenes:"
    jq -r '.scene_order[].name' "$scene_file"
    
    echo -e "\nSources:"
    jq -r '.sources[] | "• \(.name) - Type: \(.type)"' "$scene_file"
}

# Restore default OBS configuration
restore_obs_config() {
    local obs_config_dir="$HOME/Library/Application Support/obs-studio"
    local profiles_dir="$obs_config_dir/basic/profiles"
    local scenes_dir="$obs_config_dir/basic/scenes"
    
    # Backup existing configuration
    local backup_dir="$obs_config_dir/backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    cp -r "$obs_config_dir/basic" "$backup_dir/"
    
    echo "🔄 Restoring OBS Configuration"
    echo "============================"
    echo "Backup created: $backup_dir"
    
    # Remove existing configurations
    rm -rf "$profiles_dir"
    rm -rf "$scenes_dir"
    
    # Recreate directories
    mkdir -p "$profiles_dir/ScreenTool"
    mkdir -p "$scenes_dir"
    
    # Create default ScreenTool profile
    cat > "$profiles_dir/ScreenTool/basic.ini" << EOF
[General]
Name=ScreenTool

[Output]
Mode=Advanced
FilenameFormatting=recording

[SimpleOutput]
RecFormat2=mkv
VBitrate=2500
ABitrate=160
Preset=veryfast
RecQuality=Stream
RecTracks=3

[AdvOut]
RecType=Standard
RecFormat2=mkv
RecTracks=3
RecEncoder=obs_x264

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

[Audio]
SampleRate=48000
ChannelSetup=Stereo
EOF

    # Create a default scene collection
    cat > "$scenes_dir/ScreenTool.json" << EOF
{
    "AuxAudioDeviceList": [],
    "current_scene": "Screen Capture",
    "scene_order": [
        {
            "name": "Screen Capture"
        }
    ],
    "sources": [
        {
            "name": "Screen Capture",
            "type": "screen_capture",
            "settings": {
                "display": 0
            }
        }
    ]
}
EOF

    # Update global configuration
    cat > "$obs_config_dir/global.ini" << EOF
[General]
CurrentProfile=ScreenTool
CurrentSceneCollection=ScreenTool
EOF

    echo "✅ OBS Configuration Restored"
    echo "   - Profile: ScreenTool"
    echo "   - Scene Collection: ScreenTool"
    echo "   - Backup: $backup_dir"
}

# Main OBS helper function
obs_help() {
    local command="${1:-status}"
    
    case "$command" in
        "status"|"config")
            check_obs_installation && show_obs_config && show_screentool_config
            ;;
        "setup"|"guide")
            echo "🎬 OBS Studio Configuration Guide for ScreenTool"
            echo "============================================="
            echo
            echo "1. 🔍 ENCODER CONFIGURATION"
            echo "   - Recommended Video Encoder: Apple VT H.264 Hardware Encoder"
            echo "   - Fallback: Software (x264)"
            echo "   - Verify in: Settings > Output > Recording/Streaming"
            echo
            echo "2. 🎧 MULTI-TRACK AUDIO SETUP"
            echo "   - Enable Advanced Output Mode"
            echo "   - Configure Audio Tracks:"
            echo "     * Track 1: Main Mix (Streaming)"
            echo "     * Track 2: Desktop Audio"
            echo "     * Track 3: Microphone Audio"
            echo
            echo "3. 📹 VIDEO SETTINGS"
            echo "   - Base Resolution: Match your screen (e.g., 1920x1080)"
            echo "   - Output Resolution: 1920x1080 (recommended)"
            echo "   - FPS: 30 (standard) or match your screen refresh rate"
            echo
            echo "4. 🔊 AUDIO CONFIGURATION"
            echo "   - Sample Rate: 48000 Hz"
            echo "   - Channels: Stereo"
            echo "   - Select correct input/output devices"
            echo
            echo "5. 🧪 TESTING CONFIGURATION"
            echo "   Commands:"
            echo "   - st obs tracks       # Verify multi-track recording"
            echo "   - st obs status       # Check current OBS settings"
            echo "   - st obs launch       # Open OBS with ScreenTool profile"
            echo
            echo "💡 TROUBLESHOOTING TIPS:"
            echo "   - Encoder not set? Check Output > Recording/Streaming settings"
            echo "   - Audio issues? Verify device selection in Audio settings"
            echo "   - Performance problems? Try different encoder presets"
            ;;
        "workflow")
            show_workflow
            ;;
        "new-session"|"session")
            new_recording_session
            ;;
        "launch"|"open")
            launch_obs
            ;;
        "tracks")
            get_recording_track_info "$2"
            ;;
        "init"|"initialize")
            initialize_obs_config
            ;;
        "scenes")
            list_obs_scenes
            ;;
        "scene")
            get_scene_info "$2"
            ;;
        "restore")
            restore_obs_config
            ;;
        *)
            echo "🎬 OBS Helper Commands:"
            echo "======================"
            echo
            echo "st obs status       - Show current OBS and ScreenTool configuration"
            echo "st obs setup        - Detailed OBS configuration guide"
            echo "st obs workflow     - Show complete recording workflow"
            echo "st obs new-session  - Create new recording session directory"
            echo "st obs launch       - Launch OBS Studio"
            echo "st obs tracks [n]   - Show audio track information"
            echo "st obs init         - Initialize OBS with ScreenTool preset"
            echo "st obs scenes        - List available scene collections"
            echo "st obs scene [name]  - Show details of a scene collection"
            echo "st obs restore       - Restore default OBS configuration"
            echo
            ;;
    esac
}
