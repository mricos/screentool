#!/bin/bash
# screentool_env.sh - Environment variable management for screentool

# Define environment configuration file
ENV_CONFIG="$HOME/.screentool_env"

save_env() {
  echo "Saving environment variables to $ENV_CONFIG..."
  {
    echo "export DISPLAY=\"$DISPLAY\""
    echo "export SCREEN_GEOMETRY=\"$SCREEN_GEOMETRY\""
    echo "export AUDIO_DEVICE_IN=\"$AUDIO_DEVICE_IN\""
    echo "export AUDIO_DEVICE_OUT=\"$AUDIO_DEVICE_OUT\""
    echo "export VIDEO_CODEC=\"$VIDEO_CODEC\""
    echo "export PRESET=\"$PRESET\""
    echo "export CRF=\"$CRF\""
    echo "export COMPRESSION_TUNE=\"$COMPRESSION_TUNE\""
    echo "export COMPRESSION_GOP=\"$COMPRESSION_GOP\""
    echo "export FRAMERATE=\"$FRAMERATE\""
    echo "export SCREEN_SIZE=\"$SCREEN_SIZE\""
    echo "export RATE=\"$RATE\""
    echo "export BUFFER_SIZE=\"$BUFFER_SIZE\""
    echo "export PERIOD_SIZE=\"$PERIOD_SIZE\""
    echo "export AUDIO_CHANNELS=\"$AUDIO_CHANNELS\""
    echo "export AUDIO_CODEC=\"$AUDIO_CODEC\""
    echo "export AUDIO_BITRATE=\"$AUDIO_BITRATE\""
  } > "$ENV_CONFIG"
}


# Load environment variables from file
load_env() {
  if [ -f "$ENV_CONFIG" ]; then
    echo "Loading environment variables from $ENV_CONFIG..."
    source "$ENV_CONFIG"
  else
    echo "No environment configuration file found."
  fi
}

# Display environment variables
env_display() {
  echo "Current Environment Variables:"
  echo "-------------------------------"
  cat "$ENV_CONFIG"
  echo "-------------------------------"
}
