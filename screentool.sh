#!/usr/bin/env bash
# screentool.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export ST_SRC=${ST_SRC:-"$HOME/src/screentool"}
export ST_DIR=${ST_DIR:-"$HOME/recordings"}

source "$SCRIPT_DIR/screentool_env.sh"
source "$SCRIPT_DIR/screentool_macos_devices.sh"
source "$SCRIPT_DIR/screentool_audio.sh"
source "$SCRIPT_DIR/screentool_video.sh"
source "$SCRIPT_DIR/screentool_record.sh"
source "$SCRIPT_DIR/screentool_play.sh"
source "$SCRIPT_DIR/screentool_info.sh"

load_env

usage() {
  cat << 'EOF'
screentool - Screen Recording Tool

USAGE:
  record [file]         Record screen
  play [file]           Play recording
  list                  List recordings
  geometry              Show screen layout
  select-area           Set recording area
  audio                 Configure audio input/quality
  help                  Show detailed help

Quick start: ./screentool.sh record demo.mp4
For full help: ./screentool.sh help
EOF
  exit 1
}

usage_full() {
  cat << 'EOF'
screentool - Advanced Screen Recording Tool
===========================================

COMMANDS:
  record [filename]     Record screen with current settings
  play [filename]       Play a recording file  
  list                  List all recordings with metadata
  
INFORMATION:
  info <file>           Show detailed file information
  summary <file>        Show brief file summary
  json <file>           Output raw metadata as JSON
  geometry              Display ASCII visualization of screen setup
  
CONFIGURATION:
  select                Select recording display/device
  select-area           Interactively select recording area
  clear-area            Clear area selection (record full screen)
  audio                 Configure audio input/output
  
DEVICE MANAGEMENT:
  input                 List available audio input devices
  output                List available audio output devices  
  video                 List available video input devices
  
ENVIRONMENT:
  save                  Save current configuration
  load                  Load saved configuration
  env                   Display current environment settings

EXAMPLES:
  $0 record demo.mp4    # Record to demo.mp4
  $0 select-area        # Set up area recording
  $0 geometry           # Show screen layout
  $0 list               # View all recordings

For more help: https://github.com/mricos/screentool
EOF
  exit 0
}

check_dependencies() {
  case "$ST_OS_TYPE" in
    macos)
      for dep in ffmpeg cliclick; do
        command -v "$dep" >/dev/null || { echo "Missing $dep. Try: brew install $dep"; exit 1; }
      done
      ;;
    linux)
      for dep in ffmpeg jq pactl xrandr; do
        command -v "$dep" >/dev/null || { echo "Missing $dep"; exit 1; }
      done
      ;;
  esac
}

select_display() {
  case "$ST_OS_TYPE" in
    macos)
      echo "Device Selection"
      echo "================"
      echo
      
      print_macos_devices
      
      echo
      echo "Current settings:"
      echo "  Video device: ${ST_AVFOUNDATION_VIDEO_DEVICE:-0}"
      echo "  Audio device: ${ST_AVFOUNDATION_AUDIO_DEVICE:-0}"
      echo
      
      # Video device selection
      read -rp "Enter AVFoundation video device index for screen (default ${ST_AVFOUNDATION_VIDEO_DEVICE:-0}): " vid
      if [[ -n "$vid" ]]; then
        if [[ "$vid" =~ ^[0-9]+$ ]]; then
          export ST_AVFOUNDATION_VIDEO_DEVICE="$vid"
          echo "✓ Video device set to index: $vid"
        else
          echo "⚠️  Invalid input, keeping current video device"
        fi
      else
        export ST_AVFOUNDATION_VIDEO_DEVICE="${ST_AVFOUNDATION_VIDEO_DEVICE:-0}"
        echo "✓ Using video device index: ${ST_AVFOUNDATION_VIDEO_DEVICE}"
      fi
      
      echo
      # Audio device selection
      read -rp "Enter AVFoundation audio device index (default ${ST_AVFOUNDATION_AUDIO_DEVICE:-0}): " aid
      if [[ -n "$aid" ]]; then
        if [[ "$aid" =~ ^[0-9]+$ ]]; then
          export ST_AVFOUNDATION_AUDIO_DEVICE="$aid"
          echo "✓ Audio device set to index: $aid"
        else
          echo "⚠️  Invalid input, keeping current audio device"
        fi
      else
        export ST_AVFOUNDATION_AUDIO_DEVICE="${ST_AVFOUNDATION_AUDIO_DEVICE:-0}"
        echo "✓ Using audio device index: ${ST_AVFOUNDATION_AUDIO_DEVICE}"
      fi
      
      echo
      # Try to auto-detect geometry for the selected video device
      echo "Detecting screen geometry..."
      res=$(system_profiler SPDisplaysDataType | grep Resolution | head -n1 | awk -F: '{print $2}' | xargs)
      if [[ -n "$res" ]]; then
        width=$(echo "$res" | awk '{print $1}')
        height=$(echo "$res" | awk '{print $3}')
        SCREEN_GEOMETRY="${width}x${height}+0+0"
        export SCREEN_GEOMETRY
        echo "✓ Screen geometry detected: $SCREEN_GEOMETRY"
      else
        echo "⚠️  Could not auto-detect screen geometry"
      fi
      
      save_env
      
      echo
      echo "Device selection saved!"
      echo "💡 Tips:"
      echo "  - Run './screentool.sh geometry' to visualize your setup"
      echo "  - Run './screentool.sh audio' for advanced audio settings"
      echo "  - Test with './screentool.sh record test.mp4'"
      ;;
    linux)
      # Existing xrandr/selection logic (not shown, no change)
      ;;
  esac
}

calculate_file_size() {
  local width=$1
  local height=$2
  local fps=${FRAMERATE:-5}
  local crf=${CRF:-23}
  
  # Base bitrate calculation (rough estimates for screen recording)
  # These are conservative estimates for screen content with current settings
  local pixels=$((width * height))
  local base_bitrate_kbps
  
  # Adjust base bitrate based on CRF (lower CRF = higher quality = higher bitrate)
  case $crf in
    18|19|20) base_bitrate_kbps=$((pixels / 1000)) ;;  # High quality
    21|22|23) base_bitrate_kbps=$((pixels / 1500)) ;;  # Medium quality (default)
    24|25|26) base_bitrate_kbps=$((pixels / 2000)) ;;  # Lower quality
    *) base_bitrate_kbps=$((pixels / 1500)) ;;         # Default
  esac
  
  # Adjust for framerate (screen recordings are typically low motion)
  local fps_multiplier
  case $fps in
    1|2|3) fps_multiplier="0.3" ;;
    4|5|6) fps_multiplier="0.5" ;;
    10|15) fps_multiplier="0.8" ;;
    24|25|30) fps_multiplier="1.0" ;;
    *) fps_multiplier="0.5" ;;
  esac
  
  # Calculate final bitrate
  local video_bitrate_kbps
  video_bitrate_kbps=$(echo "$base_bitrate_kbps $fps_multiplier" | awk '{printf "%.0f", $1 * $2}')
  
  # Add audio bitrate (convert from Hz to kbps)
  local audio_bitrate_kbps=$((${AUDIO_BITRATE:-48000} / 1000))
  
  local total_bitrate_kbps=$((video_bitrate_kbps + audio_bitrate_kbps))
  
  # Calculate file size per hour (in MB)
  local mb_per_hour
  mb_per_hour=$(echo "$total_bitrate_kbps" | awk '{printf "%.0f", $1 * 3600 / 8 / 1024}')
  
  echo "$mb_per_hour MB/hour (~${total_bitrate_kbps} kbps)"
}

select_area() {
  if [[ "$ST_OS_TYPE" != "macos" ]]; then
    echo "This feature is only available on macOS."
    exit 1
  fi

  echo "Click-and-Size Area Selection"
  echo "============================="
  echo
  echo "Step 1: Click the TOP-LEFT corner of your desired recording area"
  echo "Move your mouse to the top-left corner and press Enter..."
  read -r

  local pos1
  pos1=$(cliclick p)
  local x1
  x1=$(echo "$pos1" | cut -d, -f1)
  local y1
  y1=$(echo "$pos1" | cut -d, -f2)
  echo "✓ Top-left corner set to: ($x1, $y1)"
  echo

  echo "Step 2: Choose recording setup"
  echo "Current settings: ${FRAMERATE:-5}fps, CRF${CRF:-23}, ${VIDEO_CODEC:-libx264}"
  echo
  echo "📋 CODING PRESETS (optimized for development):"
  echo "c1) Ultrawide Coding (2560x1200) - $(calculate_file_size 2560 1200) - Editor + Terminal"
  echo "c2) Standard Coding (1920x1200) - $(calculate_file_size 1920 1200) - Single Editor"
  echo "c3) Compact Coding (1680x1050) - $(calculate_file_size 1680 1050) - Focused View"
  echo
  echo "📺 STANDARD RESOLUTIONS:"
  echo "1) 1440p (2560x1440) - $(calculate_file_size 2560 1440) - Full QHD"
  echo "2) 1080p (1920x1080) - $(calculate_file_size 1920 1080) - Full HD"
  echo "3) 720p  (1280x720)  - $(calculate_file_size 1280 720) - HD"
  echo "4) 480p  (854x480)   - $(calculate_file_size 854 480) - SD"
  echo "5) 360p  (640x360)   - $(calculate_file_size 640 360) - Low"
  echo "6) Custom size (enter width x height)"
  echo
  read -rp "Select preset/resolution (c1/c2/c3/1-6): " choice

  local width height coding_preset=false
  case $choice in
    # Coding presets with optimized positioning
    c1|C1) 
      width=2560; height=1200; coding_preset=true
      echo "📋 Selected: Ultrawide Coding preset"
      echo "    Perfect for: Editor + Terminal/Browser side-by-side"
      ;;
    c2|C2) 
      width=1920; height=1200; coding_preset=true
      echo "📋 Selected: Standard Coding preset"
      echo "    Perfect for: Single editor with sidebar"
      ;;
    c3|C3) 
      width=1680; height=1050; coding_preset=true
      echo "📋 Selected: Compact Coding preset"
      echo "    Perfect for: Focused coding sessions"
      ;;
    # Standard resolutions
    1) width=2560; height=1440 ;;
    2) width=1920; height=1080 ;;
    3) width=1280; height=720 ;;
    4) width=854; height=480 ;;
    5) width=640; height=360 ;;
    6) 
      read -rp "Enter width: " width
      read -rp "Enter height: " height
      # Validate input
      if ! [[ "$width" =~ ^[0-9]+$ ]] || ! [[ "$height" =~ ^[0-9]+$ ]]; then
        echo "Error: Invalid dimensions. Please enter numbers only."
        exit 1
      fi
      ;;
    *)
      echo "Invalid selection. Exiting."
      exit 1
      ;;
  esac

  # Ensure even dimensions for ffmpeg
  width=$(( (width / 2) * 2 ))
  height=$(( (height / 2) * 2 ))

  # For coding presets, auto-position below macOS menu bar
  if [[ "$coding_preset" == "true" ]]; then
    x1=10  # Small margin from left edge
    y1=35  # Below macOS menu bar (28-30px) with buffer
    echo "🍎 Auto-positioned below macOS menu bar at (${x1}, ${y1})"
  fi

  export ST_CROP_GEOMETRY="${width}:${height}:${x1}:${y1}"
  
  echo
  echo "✓ Recording area configured:"
  echo "  Position: ($x1, $y1)"
  echo "  Size: ${width}x${height}"
  if [[ "$coding_preset" == "true" ]]; then
    echo "  Type: Coding preset (optimized for development)"
    echo "  Positioning: Below macOS menu bar"
  fi
  echo "  Estimated file size: $(calculate_file_size $width $height)"
  echo "  Crop geometry: $ST_CROP_GEOMETRY"
  
  save_env
  
  echo
  if [[ "$coding_preset" == "true" ]]; then
    echo "💡 Coding Tips:"
    echo "  - Position your IDE/editor in the top-left area"
    echo "  - Keep important code visible in the capture zone"
    echo "  - Run './screentool.sh geometry' to visualize the area"
    echo "  - Test with './screentool.sh record coding-demo.mp4'"
  else
    echo "💡 Tip: Run './screentool.sh geometry' to visualize your recording area"
  fi
}

clear_area() {
  unset ST_CROP_GEOMETRY
  save_env
  echo "Area selection cleared. Recording will use full screen."
}

case "$1" in
  record)      record "$2" "$SCREEN_GEOMETRY" ;;
  play)        play_recording "$2" ;;
  list)        list_recordings ;;
  info)        summary "$2" ;;
  summary)     summary "$2" ;;
  json)        json_metadata "$2" ;;
  geometry)    ascii_geometry ;;
  help)        usage_full ;;
  input)       list_audio_inputs ;;
  output)      list_audio_outputs ;;
  video)       list_video_inputs ;;
  select)      select_display ;;
  select-area) select_area ;;
  clear-area)  clear_area ;;
  audio)       configure_audio ;;
  save)        save_env ;;
  load)        load_env ;;
  env)         env_display ;;
  *)           usage ;;
esac

