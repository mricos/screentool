#!/usr/bin/env bash
# Unified environment configuration for ScreenTool

# Core paths
export ST_SRC="/Users/mricos/src/screentool"
export ST_DIR="/Users/mricos/recordings"

# OS and Backend Detection
case "$(uname)" in
  Darwin)
    export ST_OS_TYPE="macos"
    export ST_VIDEO_BACKEND="avfoundation"
    export ST_AUDIO_BACKEND="avfoundation"
    export ST_AVFOUNDATION_VIDEO_DEVICE="${ST_AVFOUNDATION_VIDEO_DEVICE:-2}"
    export ST_AVFOUNDATION_AUDIO_DEVICE="${ST_AVFOUNDATION_AUDIO_DEVICE:-1}"
    ;;
  Linux)
    export ST_OS_TYPE="linux"
    export DISPLAY="${DISPLAY:-:0}"
    export ST_VIDEO_BACKEND="x11grab"
    export ST_AUDIO_BACKEND="pulse"
    export ST_PULSE_IN_DEVICE="${ST_PULSE_IN_DEVICE:-@DEFAULT_SOURCE@}"
    export ST_PULSE_OUT_DEVICE="${ST_PULSE_OUT_DEVICE:-@DEFAULT_SINK@}"
    ;;
esac

# Geometry and Cropping
export ST_GEOMETRY=""
export SCREEN_GEOMETRY="3310x1112+0+0"
export ST_CROP_GEOMETRY="1920x1000+0+40"
export ST_CROP_UI_ELEMENTS="true"
export ST_MENU_BAR_HEIGHT="28"
export ST_DOCK_HEIGHT="70"

# Video Settings
export VIDEO_CODEC="libx264"
export PRESET="veryfast"
export CRF="23"
export COMPRESSION_TUNE="stillimage"
export COMPRESSION_GOP="300"
export FRAMERATE="5"
export PIXEL_FORMAT="uyvy422"

# Audio Settings
export AUDIO_CHANNELS="1"
export AUDIO_SAMPLERATE="48000"
export AUDIO_CODEC="aac"
export AUDIO_BITRATE="48000"
export ST_BUFFER_SIZE="1024"

# Edit Pipeline Settings
export EDIT_TARGET_WIDTH="1920"
export EDIT_TARGET_HEIGHT="1080"

# Save configuration function
save_config() {
  local config_file="$ST_SRC/env.sh"
  {
    # Regenerate the entire configuration file
    grep -v '^#' "$config_file" | grep -v '^\s*$' | sed 's/^export //'
  } > "$config_file.tmp"
  mv "$config_file.tmp" "$config_file"
  chmod +x "$config_file"
}

# Load configuration function (optional, for future-proofing)
load_config() {
  source "$ST_SRC/env.sh"
}
