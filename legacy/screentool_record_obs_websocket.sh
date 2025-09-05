#!/usr/bin/env bash
# screentool_record_obs.sh
# OBS Studio-based recording system for screentool
# Uses OBS binary with launch flags for simple, reliable control

set -euo pipefail

# OBS configuration
OBS_COLLECTION_NAME="${OBS_COLLECTION_NAME:-ScreenTool}"
OBS_PROFILE_NAME="${OBS_PROFILE_NAME:-ScreenTool}"
OBS_SCENE_NAME="${OBS_SCENE_NAME:-ScreenTool}"
OBS_OUTPUT_DIR="${OBS_OUTPUT_DIR:-$HOME/Movies}"

# OBS executable path
OBS_EXECUTABLE="/Applications/OBS.app/Contents/MacOS/obs"

# WebSocket helper functions (based on obs_rec_scene.sh)
b64sha256() {
    # stdin -> base64(sha256)
    openssl dgst -binary -sha256 | openssl base64 -A
}

compute_auth() {
    local password="$1" salt="$2" challenge="$3"
    local secret auth
    secret="$(printf '%s' "${password}${salt}" | b64sha256)"
    auth="$(printf '%s%s' "$secret" "$challenge" | b64sha256)"
    printf '%s' "$auth"
}

send_ws() { 
    local data="$1"
    printf '%s\n' "$data" >&"${WS[1]}"
}

send_req() {
    local type="$1" data="${2:-{}}"
    local id; id="$(next_id)"
    send_ws "$(jq -cn --arg t "$type" --arg id "$id" --argjson d "$data" \
        '{op:6, d:{requestType:$t, requestId:$id, requestData:$d}}')"
}

# Check dependencies
check_dependencies() {
    local missing=()
    for bin in websocat jq openssl; do
        if ! command -v "$bin" >/dev/null; then
            missing+=("$bin")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "❌ Missing dependencies: ${missing[*]}"
        echo "Install with: brew install ${missing[*]}"
        return 1
    fi
    return 0
}

# Connect to OBS WebSocket
connect_obs_websocket() {
    local event_subs="${1:-0}"  # 0 = no events, 0x7fffffff for all events
    
    echo "🔌 Connecting to OBS WebSocket at ${OBS_WEBSOCKET_HOST}:${OBS_WEBSOCKET_PORT}..."
    
    # Start WebSocket connection as coprocess
    coproc WS ( websocat -q -t "ws://${OBS_WEBSOCKET_HOST}:${OBS_WEBSOCKET_PORT}" )
    
    # Read Hello message (op=0)
    local hello
    read -r hello <&"${WS[0]}"
    
    # Extract auth info if present
    local challenge salt rpcv
    challenge="$(jq -r 'select(.op==0) | .d.authentication.challenge // empty' <<<"$hello")"
    salt="$(jq -r 'select(.op==0) | .d.authentication.salt // empty' <<<"$hello")"
    rpcv="$(jq -r 'select(.op==0) | .d.rpcVersion' <<<"$hello")"
    rpcv="${rpcv:-1}"
    
    # Send Identify message (op=1)
    local ident
    if [[ -n "$challenge" && -n "$salt" ]]; then
        local auth
        auth="$(compute_auth "$OBS_WEBSOCKET_PASSWORD" "$salt" "$challenge")"
        ident="$(jq -cn --arg auth "$auth" --argjson rpc "$rpcv" --argjson subs "$event_subs" \
            '{op:1, d:{rpcVersion:$rpc, authentication:$auth, eventSubscriptions:$subs}}')"
    else
        ident="$(jq -cn --argjson rpc "$rpcv" --argjson subs "$event_subs" \
            '{op:1, d:{rpcVersion:$rpc, eventSubscriptions:$subs}}')"
    fi
    send_ws "$ident"
    
    # Wait for Identified message (op=2)
    local msg op
    while read -r msg <&"${WS[0]}"; do
        op="$(jq -r '.op' <<<"$msg")"
        if [[ "$op" == "2" ]]; then
            echo "✅ Connected to OBS WebSocket"
            return 0
        elif [[ "$op" == "7" ]]; then
            # RequestResponse - check for auth failure
            local status code
            status="$(jq -r '.d.requestStatus.result // empty' <<<"$msg")"
            code="$(jq -r '.d.requestStatus.code // empty' <<<"$msg")"
            if [[ "$status" == "false" && "$code" == "401" ]]; then
                echo "❌ Authentication failed - check OBS_WEBSOCKET_PASSWORD"
                return 1
            fi
        fi
    done
    
    echo "❌ Failed to establish WebSocket connection"
    return 1
}

# Disconnect from OBS WebSocket
disconnect_obs_websocket() {
    if [[ -n "${WS[0]:-}" && -n "${WS[1]:-}" ]]; then
        exec {WS[0]}>&- {WS[1]}>&-
    fi
}

# Wait for request response
wait_for_response() {
    local request_type="$1"
    local timeout="${2:-10}"
    local count=0
    
    while [[ $count -lt $timeout ]]; do
        if read -r -t 1 msg <&"${WS[0]}"; then
            local op rtype status
            op="$(jq -r '.op' <<<"$msg")"
            if [[ "$op" == "7" ]]; then
                rtype="$(jq -r '.d.requestType' <<<"$msg")"
                status="$(jq -r '.d.requestStatus.result' <<<"$msg")"
                
                if [[ "$rtype" == "$request_type" ]]; then
                    if [[ "$status" == "true" ]]; then
                        return 0
                    else
                        local code comment
                        code="$(jq -r '.d.requestStatus.code' <<<"$msg")"
                        comment="$(jq -r '.d.requestStatus.comment // empty' <<<"$msg")"
                        echo "❌ Request $rtype failed: code=$code ${comment:+comment=\"$comment\"}"
                        return 1
                    fi
                fi
            fi
        fi
        ((count++))
    done
    
    echo "⚠️ Timeout waiting for $request_type response"
    return 1
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

# Start OBS if not running
start_obs() {
    if is_obs_running; then
        echo "✅ OBS Studio is already running"
        return 0
    fi
    
    echo "🚀 Starting OBS Studio..."
    # Start OBS in background with minimal UI
    "$OBS_EXECUTABLE" --minimize-to-tray --disable-shutdown-check &
    
    # Wait for OBS to start
    local timeout=10
    local count=0
    while ! is_obs_running && [[ $count -lt $timeout ]]; do
        sleep 1
        ((count++))
    done
    
    if is_obs_running; then
        echo "✅ OBS Studio started successfully"
        # Give OBS a moment to fully initialize
        sleep 2
        return 0
    else
        echo "❌ Failed to start OBS Studio"
        return 1
    fi
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

# Create or configure OBS scene via WebSocket
setup_obs_scene() {
    local scene_name="${1:-$OBS_SCENE_NAME}"
    local source_name="${2:-$OBS_SOURCE_NAME}"
    
    echo "🎬 Setting up OBS scene: $scene_name"
    
    # Create scene if it doesn't exist
    send_req "CreateScene" "$(jq -cn --arg name "$scene_name" '{sceneName:$name}')"
    wait_for_response "CreateScene" 5 || echo "Scene may already exist"
    
    # Create display capture source
    local source_settings
    source_settings=$(jq -cn \
        --arg x "$OBS_RECORD_X" \
        --arg y "$OBS_RECORD_Y" \
        --arg w "$OBS_RECORD_WIDTH" \
        --arg h "$OBS_RECORD_HEIGHT" \
        '{
            crop_left: ($x | tonumber),
            crop_top: ($y | tonumber), 
            crop_right: 0,
            crop_bottom: 0,
            width: ($w | tonumber),
            height: ($h | tonumber)
        }')
    
    send_req "CreateInput" "$(jq -cn \
        --arg scene "$scene_name" \
        --arg source "$source_name" \
        --argjson settings "$source_settings" \
        '{
            sceneName: $scene,
            inputName: $source,
            inputKind: "screen_capture",
            inputSettings: $settings
        }')"
    wait_for_response "CreateInput" 5 || echo "Source may already exist"
    
    # Set as current program scene
    send_req "SetCurrentProgramScene" "$(jq -cn --arg scene "$scene_name" '{sceneName:$scene}')"
    wait_for_response "SetCurrentProgramScene" 5
    
    echo "✅ Scene configured: $scene_name with source: $source_name"
    echo "📐 Recording area: ${OBS_RECORD_WIDTH}x${OBS_RECORD_HEIGHT} at ${OBS_RECORD_X},${OBS_RECORD_Y}"
}

# Start OBS recording via WebSocket
start_obs_recording() {
    local scene_name="${1:-$OBS_SCENE_NAME}"
    
    echo "🎬 Starting OBS recording..."
    
    # Set up the recording area and scene
    calculate_recording_area
    setup_obs_scene "$scene_name"
    
    # Start recording
    send_req "StartRecord" "{}"
    if wait_for_response "StartRecord" 10; then
        echo "✅ Recording started successfully"
        return 0
    else
        echo "❌ Failed to start recording"
        return 1
    fi
}

# Stop OBS recording via WebSocket
stop_obs_recording() {
    echo "⏹️  Stopping OBS recording..."
    
    send_req "StopRecord" "{}"
    if wait_for_response "StopRecord" 10; then
        echo "✅ Recording stopped successfully"
        return 0
    else
        echo "❌ Failed to stop recording"
        return 1
    fi
}

# Get OBS recording status
get_recording_status() {
    send_req "GetRecordStatus" "{}"
    # Note: This would need response parsing to get actual status
    # For now, we'll use a simple check
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
    
    # OBS will save to its configured output directory
    # We'll need to move the file to our recording directory afterward
    local obs_output_dir="$HOME/Movies"  # Default OBS output directory
    recording_path="$recording_dir/recording.mkv"  # OBS typically outputs MKV
    
    echo "🎬 ScreenTool OBS Recording"
    echo "=========================="
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
    
    # Start OBS if needed
    if ! start_obs; then
        return 1
    fi
    
    # Connect to OBS WebSocket
    if ! connect_obs_websocket; then
        echo "❌ Failed to connect to OBS WebSocket"
        echo "💡 Make sure OBS WebSocket is enabled in Tools > WebSocket Server Settings"
        echo "💡 Default port: 4455, password: screentool"
        return 1
    fi
    
    # Set up cleanup trap
    trap 'disconnect_obs_websocket' EXIT
    
    # Create recording metadata
    cat > "$recording_dir/recording.meta" << EOF
RECORDING_NAME="$prefix"
RECORDING_ID="$recording_id"
RECORDING_PATH="$recording_path"
RECORDING_LOG="recording.log"
START_TIME="$(date)"
RECORDING_METHOD="obs"
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
    
    # Start recording
    if start_obs_recording "$OBS_SCENE_NAME"; then
        echo
        echo "🎬 Recording in progress..."
        echo "💡 To stop recording:"
        echo "   • Run: st stop-recording"
        echo "   • Or press Ctrl+C here"
        echo
        
        # If duration is specified, wait and then stop
        if [[ -n "$duration" ]] && [[ "$duration" =~ ^[0-9]+$ ]]; then
            echo "⏱️  Recording for $duration seconds..."
            sleep "$duration"
            stop_obs_recording
        else
            echo "⏱️  Recording until stopped manually..."
            echo "Press Ctrl+C to stop recording"
            
            # Wait for user interrupt
            trap 'stop_obs_recording; disconnect_obs_websocket; echo; echo "Recording stopped by user"; exit 0' INT
            
            # Keep the script running
            while is_obs_running; do
                sleep 1
            done
        fi
        
        # Look for the recorded file in OBS output directory
        echo
        echo "🔍 Looking for recorded file..."
        
        # OBS typically saves files with timestamps, so we need to find the most recent one
        local obs_file
        obs_file=$(find "$obs_output_dir" -name "*.mkv" -o -name "*.mp4" -o -name "*.mov" | \
                   xargs ls -t 2>/dev/null | head -1)
        
        if [[ -n "$obs_file" ]] && [[ -f "$obs_file" ]]; then
            echo "✅ Found recorded file: $(basename "$obs_file")"
            
            # Move to our recording directory
            mv "$obs_file" "$recording_path"
            echo "📁 Moved to: $recording_path"
            
            # Update metadata
            cat >> "$recording_dir/recording.meta" << EOF
END_TIME="$(date)"
RECORDING_COMPLETE="true"
ACTUAL_OUTPUT_FILE="$(basename "$obs_file")"
EOF
            
            # Get file info
            if [[ -f "$recording_path" ]]; then
                local file_size
                file_size=$(stat -f "%z" "$recording_path" 2>/dev/null)
                if [[ -n "$file_size" ]]; then
                    file_size=$(echo "$file_size" | awk '{printf "%.1fMB", $1/1024/1024}')
                    echo "📊 Recording size: $file_size"
                fi
            fi
            
            echo
            echo "✅ OBS Recording completed successfully!"
            echo "📁 Session: $recording_id"
            echo "🎬 File: $recording_path"
            echo "▶️  Play: st play latest"
            echo "✏️  Edit: st edit $recording_id"
            
        else
            echo "⚠️  Could not find recorded file in $obs_output_dir"
            echo "💡 Check OBS output settings and try again"
            
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
    echo "OBS Studio Status"
    echo "================="
    
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
    echo "  WebSocket Host: $OBS_WEBSOCKET_HOST"
    echo "  WebSocket Port: $OBS_WEBSOCKET_PORT"
    echo "  Recording Area: ${OBS_RECORD_WIDTH:-auto}x${OBS_RECORD_HEIGHT:-auto}"
    echo "  UI Cropping: ${ST_CROP_UI_ELEMENTS:-false}"
}

# OBS Device Management Functions

# List available input kinds (device types) via OBS WebSocket
list_obs_input_kinds() {
    echo "Available OBS Input Types:"
    echo "========================="
    
    if ! connect_obs_websocket; then
        echo "❌ Could not connect to OBS WebSocket"
        return 1
    fi
    
    send_req "GetInputKindList" "{}"
    
    local msg op
    while read -r -t 5 msg <&"${WS[0]}"; do
        op="$(jq -r '.op' <<<"$msg")"
        if [[ "$op" == "7" ]]; then
            local rtype status
            rtype="$(jq -r '.d.requestType' <<<"$msg")"
            status="$(jq -r '.d.requestStatus.result' <<<"$msg")"
            
            if [[ "$rtype" == "GetInputKindList" && "$status" == "true" ]]; then
                local input_kinds
                input_kinds="$(jq -r '.d.responseData.inputKinds[]' <<<"$msg")"
                
                echo "Screen/Display Capture:"
                echo "$input_kinds" | grep -E "(screen|display|capture)" | sed 's/^/  • /'
                echo
                echo "Audio Devices:"
                echo "$input_kinds" | grep -E "(audio|mic|input)" | sed 's/^/  • /'
                echo
                echo "Video Devices:"
                echo "$input_kinds" | grep -E "(video|camera|webcam)" | sed 's/^/  • /'
                echo
                echo "Other Sources:"
                echo "$input_kinds" | grep -vE "(screen|display|capture|audio|mic|input|video|camera|webcam)" | sed 's/^/  • /'
                
                disconnect_obs_websocket
                return 0
            fi
        fi
    done
    
    disconnect_obs_websocket
    echo "⚠️ Could not retrieve input kinds from OBS"
    return 1
}

# List current inputs/sources in OBS
list_obs_inputs() {
    echo "Current OBS Inputs/Sources:"
    echo "=========================="
    
    if ! connect_obs_websocket; then
        echo "❌ Could not connect to OBS WebSocket"
        return 1
    fi
    
    send_req "GetInputList" "{}"
    
    local msg op
    while read -r -t 5 msg <&"${WS[0]}"; do
        op="$(jq -r '.op' <<<"$msg")"
        if [[ "$op" == "7" ]]; then
            local rtype status
            rtype="$(jq -r '.d.requestType' <<<"$msg")"
            status="$(jq -r '.d.requestStatus.result' <<<"$msg")"
            
            if [[ "$rtype" == "GetInputList" && "$status" == "true" ]]; then
                local inputs
                inputs="$(jq -r '.d.responseData.inputs[]' <<<"$msg")"
                
                if [[ -n "$inputs" ]]; then
                    echo "$inputs" | jq -r '"  • " + .inputName + " (" + .inputKind + ")"'
                else
                    echo "  No inputs configured in OBS"
                fi
                
                disconnect_obs_websocket
                return 0
            fi
        fi
    done
    
    disconnect_obs_websocket
    echo "⚠️ Could not retrieve inputs from OBS"
    return 1
}

# List available scenes in OBS
list_obs_scenes() {
    echo "Available OBS Scenes:"
    echo "===================="
    
    if ! connect_obs_websocket; then
        echo "❌ Could not connect to OBS WebSocket"
        return 1
    fi
    
    send_req "GetSceneList" "{}"
    
    local msg op
    while read -r -t 5 msg <&"${WS[0]}"; do
        op="$(jq -r '.op' <<<"$msg")"
        if [[ "$op" == "7" ]]; then
            local rtype status
            rtype="$(jq -r '.d.requestType' <<<"$msg")"
            status="$(jq -r '.d.requestStatus.result' <<<"$msg")"
            
            if [[ "$rtype" == "GetSceneList" && "$status" == "true" ]]; then
                local current_scene scenes
                current_scene="$(jq -r '.d.responseData.currentProgramSceneName' <<<"$msg")"
                scenes="$(jq -r '.d.responseData.scenes[].sceneName' <<<"$msg")"
                
                echo "$scenes" | while read -r scene; do
                    if [[ "$scene" == "$current_scene" ]]; then
                        echo "  • $scene ← current"
                    else
                        echo "  • $scene"
                    fi
                done
                
                disconnect_obs_websocket
                return 0
            fi
        fi
    done
    
    disconnect_obs_websocket
    echo "⚠️ Could not retrieve scenes from OBS"
    return 1
}

# Create a display capture source for screen recording
create_screen_capture_source() {
    local scene_name="${1:-$OBS_SCENE_NAME}"
    local source_name="${2:-$OBS_SOURCE_NAME}"
    local display_index="${3:-0}"  # 0 = main display
    
    echo "Creating screen capture source in OBS..."
    echo "Scene: $scene_name"
    echo "Source: $source_name"
    echo "Display: $display_index"
    
    if ! connect_obs_websocket; then
        echo "❌ Could not connect to OBS WebSocket"
        return 1
    fi
    
    # Create the scene first
    send_req "CreateScene" "$(jq -cn --arg name "$scene_name" '{sceneName:$name}')"
    wait_for_response "CreateScene" 3 || echo "Scene may already exist"
    
    # Create display capture source with proper settings
    local source_settings
    source_settings=$(jq -cn \
        --arg display "$display_index" \
        '{
            display: ($display | tonumber),
            show_cursor: true,
            crop_mode: 0
        }')
    
    send_req "CreateInput" "$(jq -cn \
        --arg scene "$scene_name" \
        --arg source "$source_name" \
        --argjson settings "$source_settings" \
        '{
            sceneName: $scene,
            inputName: $source,
            inputKind: "screen_capture",
            inputSettings: $settings
        }')"
    
    if wait_for_response "CreateInput" 5; then
        echo "✅ Screen capture source created successfully"
        
        # Set the scene as current
        send_req "SetCurrentProgramScene" "$(jq -cn --arg scene "$scene_name" '{sceneName:$scene}')"
        wait_for_response "SetCurrentProgramScene" 3
        
        disconnect_obs_websocket
        return 0
    else
        echo "❌ Failed to create screen capture source"
        disconnect_obs_websocket
        return 1
    fi
}

# Configuration helper
configure_obs() {
    echo "OBS Configuration Helper"
    echo "======================="
    echo
    echo "This will help you set up OBS Studio for ScreenTool integration."
    echo
    
    # Check if OBS is running
    if ! is_obs_running; then
        echo "Starting OBS Studio..."
        if ! start_obs; then
            echo "❌ Could not start OBS Studio"
            return 1
        fi
    fi
    
    echo "✅ OBS Studio is running"
    echo
    
    # Test WebSocket connection
    echo "Testing WebSocket connection..."
    if connect_obs_websocket; then
        echo "✅ WebSocket connection successful"
        
        echo
        echo "Current OBS Configuration:"
        echo "========================="
        
        # Show available input types
        echo "📱 Available Device Types:"
        list_obs_input_kinds
        
        echo
        echo "🎬 Current Scenes:"
        list_obs_scenes
        
        echo
        echo "🎯 Current Sources:"
        list_obs_inputs
        
        disconnect_obs_websocket
        
        echo
        echo "Setup Options:"
        echo "1) Create ScreenTool scene automatically"
        echo "2) Manual setup instructions"
        echo "3) Exit"
        echo
        read -rp "Choose option (1-3): " choice
        
        case "$choice" in
            1)
                echo "Creating ScreenTool scene..."
                create_screen_capture_source "$OBS_SCENE_NAME" "$OBS_SOURCE_NAME" 0
                echo "✅ ScreenTool scene created! Test with: st record test 5"
                ;;
            2)
                echo
                echo "Manual Setup Instructions:"
                echo "========================="
                echo "1. In OBS, create a scene called '$OBS_SCENE_NAME'"
                echo "2. Add a 'Display Capture' source named '$OBS_SOURCE_NAME'"
                echo "3. Configure the display capture for your main screen"
                echo "4. Set recording format to MKV in Settings > Output"
                echo "5. Test with: st record test 5"
                ;;
            3)
                echo "Configuration cancelled"
                ;;
        esac
    else
        echo "❌ Could not connect to OBS WebSocket"
        echo
        echo "WebSocket Setup Required:"
        echo "========================"
        echo "1. In OBS, go to Tools > WebSocket Server Settings"
        echo "2. Check 'Enable WebSocket server'"
        echo "3. Set Server Port: $OBS_WEBSOCKET_PORT"
        echo "4. Set Server Password: $OBS_WEBSOCKET_PASSWORD"
        echo "5. Click OK and restart OBS"
        echo "6. Run this command again"
    fi
}
