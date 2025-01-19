#!/bin/bash
# screentool_record.sh - Screen recording functions for screentool

# Load environment configuration
ENV_CONFIG="$HOME/.screentool_env"
if [ -f "$ENV_CONFIG" ]; then
  source "$ENV_CONFIG"
fi

# Ensure DISPLAY is correctly formatted
if [[ ! "$DISPLAY" =~ ^:[0-9]+(\.[0-9]+)?$ ]]; then
  echo "Warning: Invalid DISPLAY format. Resetting to :0"
  DISPLAY=":0"
fi

start_recording() {
  timestamp=$(date +'%Y%m%d_%H%M%S')
  prefix=${1:-"screen"}
  recording_path="$HOME/screen_recordings/${prefix}_$timestamp.mp4"

  echo "Starting recording: $recording_path"
  echo "Capture region: ${SCREEN_GEOMETRY}"
  echo "Display: $DISPLAY"

  env_display

  # Validate SCREEN_GEOMETRY before passing to FFmpeg
  if [[ ! "$SCREEN_GEOMETRY" =~ ^[0-9]+x[0-9]+\+[0-9]+\+[0-9]+$ ]]; then
    echo "Error: Invalid SCREEN_GEOMETRY format: $SCREEN_GEOMETRY"
    exit 1
  fi

  # Start recording
  ffmpeg \
      -f x11grab \
      -framerate "$FRAMERATE" \
      -video_size "$(echo "$SCREEN_GEOMETRY" | cut -d'+' -f1)" \
      -i "$DISPLAY+$(echo "$SCREEN_GEOMETRY" | cut -d'+' -f2,3)" \
      -f pulse \
      -i "$AUDIO_DEVICE_IN" \
      -c:v "$VIDEO_CODEC" \
      -preset "$PRESET" \
      -crf "$CRF" \
      -tune "$COMPRESSION_TUNE" \
      -g "$COMPRESSION_GOP" \
      -pix_fmt yuv420p \
      -c:a "$AUDIO_CODEC" \
      -b:a "$AUDIO_BITRATE" \
      -ac "$AUDIO_CHANNELS" \
      -movflags +faststart \
      "$recording_path"

  # Create symbolic link to the latest recorded file
  ln -sf "$recording_path" "$HOME/screen_recordings/latest.mp4"
}

# Play the latest or specified recording
play_recording() {
  local file="${1:-$HOME/screen_recordings/latest.mp4}"
  if [ ! -f "$file" ]; then
    echo "Error: File not found: $file"
    exit 1
  fi
  echo "Playing: $file"
  summary "$file"
  ffplay "$file"
}

# Save DISPLAY variable into the environment file
save_display_env() {
  echo "Saving DISPLAY variable to $ENV_CONFIG..."
  grep -v '^export DISPLAY=' "$ENV_CONFIG" > "$ENV_CONFIG.tmp" && mv "$ENV_CONFIG.tmp" "$ENV_CONFIG"
  echo "export DISPLAY=\"$DISPLAY\"" >> "$ENV_CONFIG"
}
