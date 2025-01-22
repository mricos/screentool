#!/bin/bash
# screentool.sh - Main dispatcher script for screen recording

# Define script directory and default paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export ST_SRC=${ST_SRC:-"$HOME/src/screentool"}
export ST_DIR=${ST_DIR:-"$HOME/recordings"}

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

# Load environment variables
load_env

# Ensure ST_DIR exists
mkdir -p "$ST_DIR"

# List available X displays
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
  record)
    record "$2"
    ;;
  play)
    play_recording "$2"
    ;;
  list)
    list_recordings
    ;;
  clip)
    case "$2" in
      add)
        [ -z "$3" -o -z "$4" -o -z "$5" -o -z "$6" ] && { 
          echo "Usage: $0 clip add <filename> <start> <duration> <label>"
          echo "Examples:"
          echo "  $0 clip add recording.mp4 1h2m 30s intro"
          echo "  $0 clip add recording.mp4 01:02:00 00:00:30 intro"
          echo "  $0 clip add recording.mp4 3600 30 intro"
          exit 1
        }
        add_marker "$3" "$4" "$5" "$6"
        ;;
      remove)
        [ -z "$3" -o -z "$4" ] && { 
          echo "Usage: $0 clip remove <filename> <label>"
          echo "Example: $0 clip remove recording.mp4 intro"
          exit 1
        }
        remove_marker "$3" "$4"
        ;;
      extract)
        [ -z "$3" -o -z "$4" ] && {
          echo "Usage: $0 clip extract <filename> <label>"
          echo "Example: $0 clip extract recording.mp4 intro"
          exit 1
        }
        # Get clip points from clips.txt
        if [ -f "$ST_DIR/clips.txt" ]; then
          clip_info=$(awk -F: -v file="$3" -v label="$4" '$1 == file && $4 == label {print $2 ":" $3}' "$ST_DIR/clips.txt")
          if [ -n "$clip_info" ]; then
            IFS=: read -r start duration <<< "$clip_info"
            output_file="${3%.*}_${4}.mp4"
            # Calculate end time by adding duration to start
            end=$(bc <<< "$start + $duration")
            ffmpeg -i "$ST_DIR/$3" -ss "$start" -t "$duration" -c copy "$ST_DIR/$output_file"
            echo "Extracted clip '$4' to $output_file"
          else
            echo "Error: Clip point '$4' not found in $3"
            exit 1
          fi
        else
          echo "Error: No clips file found"
          exit 1
        fi
        ;;
      *)
        echo "Usage: $0 clip {add|remove|extract} ..."
        exit 1
        ;;
    esac
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
    env_display
    ;;
  *)
    usage
    ;;
esac
