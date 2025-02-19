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
  # First check if DISPLAY is set and valid
  if [ -z "$DISPLAY" ] || ! xrandr --display "$DISPLAY" &>/dev/null; then
    # Try to find a valid display
    for d in $(ls /tmp/.X11-unix/X* | sed 's#/tmp/.X11-unix/X##'); do
      if xrandr --display ":$d" &>/dev/null; then
        export DISPLAY=":$d"
        break
      fi
    done
  fi

  if [ -z "$DISPLAY" ]; then
    echo "Error: No valid X display found"
    exit 1
  fi

  echo "Selecting display (using DISPLAY=$DISPLAY)..."
  list_displays
  read -rp "Select display number [current: $SELECTED_DISPLAY]: " display_choice
  
  # If user just hits enter, keep current selection
  if [ -z "$display_choice" ]; then
    echo "Keeping current display: $SELECTED_DISPLAY"
  else
    # Get all connected displays with their full information
    DISPLAYS=$(xrandr --query | grep " connected")
    
    # Extract display name based on user selection
    SELECTED_DISPLAY=$(echo "$DISPLAYS" | awk -v choice="$display_choice" 'NR == choice {print $1}')
  fi

  # Extract full screen geometry
  FULL_GEOMETRY=$(echo "$DISPLAYS" | grep "^$SELECTED_DISPLAY " | awk '{
    for (i=2; i<=NF; i++) {
      if ($i ~ /^[0-9]+x[0-9]+\+[0-9]+\+[0-9]+$/) {
        print $i
        break
      }
      if ($i == "primary" && $(i+1) ~ /^[0-9]+x[0-9]+\+[0-9]+\+[0-9]+$/) {
        print $(i+1)
        break
      }
    }
  }')

  if [ -z "$SELECTED_DISPLAY" ] || [ -z "$FULL_GEOMETRY" ]; then
    echo "Error: Invalid selection. Please try again."
    exit 1
  fi

  # Parse full geometry into components
  IFS=x+ read -r width height offset_x offset_y <<< "$FULL_GEOMETRY"

  # Display recording options
  echo "Recording options for $SELECTED_DISPLAY:"
  echo "1. Full screen (${width}x${height})"
  echo "2. HD (1920x1080)"
  echo "3. Custom (default: 1280x720)"
  read -rp "Select option [1]: " area_choice

  case "$area_choice" in
    1)
      SCREEN_GEOMETRY="$FULL_GEOMETRY"
      ;;
    2)
      SCREEN_GEOMETRY="1920x1080+${offset_x}+${offset_y}"
      ;;
    3)
      echo "Current screen size: ${width}x${height}"
      read -rp "Enter custom width [1280]: " custom_width
      read -rp "Enter custom height [720]: " custom_height
      read -rp "Enter X offset [0]: " custom_x
      read -rp "Enter Y offset [0]: " custom_y
      
      # Use defaults if empty
      custom_width=${custom_width:-1280}
      custom_height=${custom_height:-720}
      custom_x=${custom_x:-0}
      custom_y=${custom_y:-0}
      
      # Calculate final position
      final_x=$((offset_x + custom_x))
      final_y=$((offset_y + custom_y))
      
      SCREEN_GEOMETRY="${custom_width}x${custom_height}+${final_x}+${final_y}"
      ;;
    *)
      echo "Invalid option selected. Please try again."
      exit 1
      ;;
  esac

  export SELECTED_DISPLAY
  export SCREEN_GEOMETRY
  echo "Selected DISPLAY: $SELECTED_DISPLAY"
  echo "Selected SCREEN_GEOMETRY: $SCREEN_GEOMETRY"
  save_env
}

configure_all() {
  echo "=== Audio Input Setup ==="
  configure_recording

  echo -e "\n=== Audio Output Setup ==="
  configure_playback

  echo -e "\n=== Display Setup ==="
  select_display
  
  save_env
  
  # Show final configuration
  echo -e "\n=== Current Configuration ==="
  echo "Audio Input:  ${ST_AUDIO_IN_DEVICE:-@DEFAULT_SOURCE@} (${ST_AUDIO_BACKEND:-pulse})"
  echo "Audio Output: ${ST_AUDIO_OUT_DEVICE:-@DEFAULT_SINK@} (${ST_AUDIO_OUT_BACKEND:-pulse})"
  echo "Display:      $SELECTED_DISPLAY"
  echo "Geometry:     $SCREEN_GEOMETRY"
}

case "$1" in
  record)
    record "$2" "$SCREEN_GEOMETRY"
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
        if [ -f "$ST_DIR/clips.txt" ]; then
          clip_info=$(awk -F: -v file="$3" -v label="$4" '$1 == file && $4 == label {print $2 ":" $3}' "$ST_DIR/clips.txt")
          if [ -n "$clip_info" ]; then
            IFS=: read -r start duration <<< "$clip_info"
            output_file="${3%.*}_${4}.mp4"
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
    configure_all
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
  audio)
    configure_audio
    ;;
  *)
    usage
    ;;
esac
