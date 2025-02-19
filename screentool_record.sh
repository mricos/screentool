#!/bin/bash
# screentool_record.sh - Screen recording functions for screentool

# Load environment configuration
ENV_CONFIG="./screentool.env"
if [ -f "$ENV_CONFIG" ]; then
  source "$ENV_CONFIG"
fi

# Ensure ST_DIR exists and is absolute
ST_DIR=${ST_DIR:-"$HOME/recordings"}
mkdir -p "$ST_DIR"

# Ensure DISPLAY is correctly formatted
if [[ ! "$DISPLAY" =~ ^:[0-9]+(\.[0-9]+)?$ ]]; then
  echo "Warning: Invalid DISPLAY format. Resetting to :0"
  DISPLAY=":0"
fi

record() {
  timestamp=$(date +'%Y%m%d_%H%M%S')
  prefix=${1:-"screen"}
  recording_path="$ST_DIR/${prefix}_$timestamp.mp4"

  echo "Starting recording: $recording_path"
  echo "Capture region: ${SCREEN_GEOMETRY}"
  echo "Display: $DISPLAY"

  env_display

  # Parse geometry values
  IFS='x+' read -r WIDTH HEIGHT OFFSET_X OFFSET_Y <<< "$SCREEN_GEOMETRY"

  # Debug output
  echo "Dimensions: ${WIDTH}x${HEIGHT} at +${OFFSET_X}+${OFFSET_Y}"

  # Validate geometry before passing to FFmpeg
  if [[ ! "$SCREEN_GEOMETRY" =~ ^[0-9]+x[0-9]+\+[0-9]+\+[0-9]+$ ]]; then
    echo "Error: Invalid geometry format: $SCREEN_GEOMETRY"
    exit 1
  fi

  # Start recording with geometry
  ffmpeg \
      -f x11grab \
      -framerate "$FRAMERATE" \
      -video_size "${WIDTH}x${HEIGHT}" \
      -i "$DISPLAY+${OFFSET_X},${OFFSET_Y}" \
      -f pulse \
      -i "${AUDIO_DEVICE_IN:-@DEFAULT_SOURCE@}" \
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
  ln -sf "$recording_path" "$ST_DIR/latest.mp4"
}

# Play the latest or specified recording
play_recording() {
  local file="${1:-latest.mp4}"
  
  # If file is not absolute path, assume it's relative to ST_DIR
  if [[ ! "$file" = /* ]]; then
    file="$ST_DIR/$file"
  fi
  
  if [ ! -f "$file" ]; then
    echo "Error: File not found: $file"
    exit 1
  fi
  
  echo "Playing: $file"
  summary "$file"

  # Normal video playback with audio
  ffplay -autoexit -i "$file"
}

# Save DISPLAY variable into the environment file
save_display_env() {
  echo "Saving DISPLAY variable to $ENV_CONFIG..."
  grep -v '^export DISPLAY=' "$ENV_CONFIG" > "$ENV_CONFIG.tmp" && mv "$ENV_CONFIG.tmp" "$ENV_CONFIG"
  echo "export DISPLAY=\"$DISPLAY\"" >> "$ENV_CONFIG"
}
