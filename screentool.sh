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
  echo "Available Monitors on $DISPLAY:"
  xrandr --query | grep " connected" | nl | while read -r num display rest; do
    geometry=$(echo "$rest" | grep -o '[0-9]\+x[0-9]\++[0-9]\++[0-9]\+')
    echo "$num. $display ($geometry)"
  done
}

select_display() {
  echo "=== Display Selection ==="
  echo "Available displays:"
  echo
  
  # Get list of available displays and monitors
  available_displays=""
  display_monitors=()
  for d in $(ls /tmp/.X11-unix/X* | sed 's#/tmp/.X11-unix/X##' | sort -n); do
    if xrandr --display ":$d" &>/dev/null; then
      echo "Display :$d"
      i=1
      while read -r output mode rest; do
        geometry=$(echo "$rest" | grep -o '[0-9]\+x[0-9]\++[0-9]\++[0-9]\+')
        printf "%2d) %-8s (%s)\n" $i "$output" "$geometry"
        display_monitors+=("$d:$output:$geometry")
        i=$((i+1))
      done < <(xrandr --display ":$d" --query | grep " connected")
      available_displays="$available_displays $d"
      echo
    fi
  done

  # Get current monitor number if set
  current_num=""
  if [ -n "$SELECTED_DISPLAY" ]; then
    current_num=$(echo "${display_monitors[@]}" | tr ' ' '\n' | nl | grep ":$SELECTED_DISPLAY:" | cut -f1)
  fi
  
  read -rp "Select monitor number${current_num:+ [$current_num]}: " monitor_choice
  monitor_choice=${monitor_choice:-$current_num}
  monitor_choice=${monitor_choice:-1}

  if [[ ! "$monitor_choice" =~ ^[0-9]+$ ]] || [ "$monitor_choice" -lt 1 ] || [ "$monitor_choice" -gt ${#display_monitors[@]} ]; then
    echo "Error: Invalid monitor selection"
    exit 1
  fi

  # Get selected monitor info
  IFS=: read -r display_num SELECTED_DISPLAY FULL_GEOMETRY <<< "${display_monitors[$((monitor_choice-1))]}"
  export DISPLAY=":$display_num"

  # Parse geometry for recording options
  IFS=x+ read -r width height offset_x offset_y <<< "$FULL_GEOMETRY"

  # Display recording options
  echo -e "\nRecording options for $SELECTED_DISPLAY:"
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
      read -rp "Enter X offset from monitor left [0]: " custom_x
      read -rp "Enter Y offset from monitor top [0]: " custom_y
      
      # Use defaults if empty
      custom_width=${custom_width:-1280}
      custom_height=${custom_height:-720}
      custom_x=${custom_x:-0}
      custom_y=${custom_y:-0}
      
      # Calculate final position relative to monitor's position
      # Add monitor's offset to custom offset
      final_x=$((offset_x + custom_x))
      final_y=$((offset_y + custom_y))
      
      # Validate custom geometry stays within monitor bounds
      if [ "$custom_x" -lt 0 ] || [ "$custom_y" -lt 0 ] || \
         [ "$((custom_x + custom_width))" -gt "$width" ] || \
         [ "$((custom_y + custom_height))" -gt "$height" ]; then
        echo "Warning: Custom geometry extends beyond monitor bounds"
      fi
      
      # Set geometry with absolute coordinates
      SCREEN_GEOMETRY="${custom_width}x${custom_height}+${final_x}+${final_y}"
      
      # Show both relative and absolute positions for clarity
      echo "Recording area will be ${custom_width}x${custom_height}"
      echo "  Relative to $SELECTED_DISPLAY: +${custom_x},+${custom_y}"
      echo "  Absolute screen position: +${final_x},+${final_y}"
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
