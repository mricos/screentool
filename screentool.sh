#!/bin/bash
# screentool.sh - Main dispatcher script for screen recording

# Define script directory
SCRIPT_DIR="$(dirname "$0")"

# Load module scripts
source "$SCRIPT_DIR/screentool_env.sh"
source "$SCRIPT_DIR/screentool_record.sh"
source "$SCRIPT_DIR/screentool_audio.sh"
source "$SCRIPT_DIR/screentool_info.sh"

# ====================================================================
#                         MAIN DISPATCH
# ====================================================================

check_dependencies() {
  for dep in ffmpeg jq pactl xrandr; do
    if ! command -v "$dep" &>/dev/null; then
      echo "Error: Required dependency '$dep' is not installed."
      exit 1
    fi
  done
}

check_dependencies

# Load environment variables from the config file if available
if [ -f "$ENV_CONFIG" ]; then
  source "$ENV_CONFIG"
fi

# List available X displays
list_displays_OLD() {
  echo "Available X Displays:"
  ls /tmp/.X11-unix/ | sed 's/X/:/' | nl
}


list_displays() {
  echo "Available X Displays:"
  xrandr --query | grep " connected" | awk '{print NR, $1, $3}'
}


select_display() {
  echo "Selecting display..."
  list_displays
  read -rp "Select display number: " display_choice

  # Extract display name based on user selection
  SELECTED_DISPLAY=$(xrandr --query | grep " connected" | awk '{print NR, $1}' | awk -v choice="$display_choice" '$1 == choice {print $2}')

  # Extract correct screen geometry (resolution + position), ignoring 'primary'
  SCREEN_GEOMETRY=$(xrandr --query | grep "^$SELECTED_DISPLAY " | awk '{for (i=3; i<=NF; i++) if ($i ~ /^[0-9]+x[0-9]+\+[0-9]+\+[0-9]+$/) print $i}')

  if [ -z "$SELECTED_DISPLAY" ] || [ -z "$SCREEN_GEOMETRY" ]; then
    echo "Error: Invalid selection. Please try again."
    exit 1
  fi

  export SCREEN_GEOMETRY
  echo "Selected SCREEN_GEOMETRY: $SCREEN_GEOMETRY"
  save_env
}


case "$1" in
  start)
    start_recording "$2"
    ;;
  play)
    play_recording "$2"
    ;;
  info)
    [ -z "$2" ] && { echo "Error: Please specify a file for info."; usage; }
    summary "$2"
    ;;
  summary)
    summary "$2"
    ;;
  json)
    json_metadata "$2"
    ;;
  input)
    list_audio_inputs
    ;;
  output)
    list_audio_outputs
    ;;
  select)
    select_audio
    select_display
    save_env
    ;;
  save)
    save_env
    ;;
  load)
    load_env
    ;;
  env)
    echo "Current Environment Variables:"
    echo "-------------------------------"
    if [ -f "$ENV_CONFIG" ]; then
      cat "$ENV_CONFIG"
    else
      echo "No environment configuration file found."
    fi
    echo "-------------------------------"
    ;;
  *)
    usage
    ;;
esac
