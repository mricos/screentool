[1] /Users/mricos/src/screentool/screentool.env
[2] /Users/mricos/src/screentool/screentool.sh
[3] /Users/mricos/src/screentool/screentool_audio.sh
[4] /Users/mricos/src/screentool/screentool_env.sh
[5] /Users/mricos/src/screentool/screentool_info.sh
[6] /Users/mricos/src/screentool/screentool_record.sh


#MULTICAT_START#
# dir: /Users/mricos/src/screentool
# file: screentool.env
# notes:
#MULTICAT_END#
export ST_SRC="/home/mricos/src/screentool"
export ST_DIR="/home/mricos/recordings"
export DISPLAY=":0"
export SCREEN_GEOMETRY="1280x720+0+35"
export ST_AUDIO_BACKEND="pulse"
export ST_AUDIO_OUT_BACKEND="pulse"
export ST_PULSE_IN_DEVICE="alsa_input.usb-RODE_MICROPHONESj_Rode_Podcaster-00.mono-fallback"
export ST_PULSE_OUT_DEVICE="alsa_output.usb-Plantronics_Poly_BT700_00B9C9B18A674F0199A62D8B3D7A76D8-00.analog-stereo"
export ST_BUFFER_SIZE="1024"
export VIDEO_CODEC="libx264"
export PRESET="veryfast"
export CRF="23"
export COMPRESSION_TUNE="stillimage"
export COMPRESSION_GOP="300"
export FRAMERATE="5"
export AUDIO_CHANNELS="1"
export AUDIO_CODEC="aac"
export AUDIO_BITRATE="48000"

#MULTICAT_START#
# dir: /Users/mricos/src/screentool
# file: screentool.sh
# notes:
#MULTICAT_END#
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

#MULTICAT_START#
# dir: /Users/mricos/src/screentool
# file: screentool_audio.sh
# notes:
#MULTICAT_END#
#!/bin/bash
# screentool_audio.sh - Audio device selection and processing

# Format device name for display
format_device_name() {
  local device="$1"
  # Break up device name at dots while preserving USB device IDs
  echo "$device" | sed -E '
    # Keep USB IDs together
    s/(usb-[A-Za-z0-9_-]+)/\1@/g
    # Break at dots except last component
    s/([^.]+)\.([^.]+\.[^.]+$)/\1\n    \2/g
    s/([^.]+)\.([^.]+$)/\1\n    \2/g
    # Remove extra spaces
    s/  +/ /g
    # Restore USB IDs
    s/@/ /g
  '
}

# List available audio input devices with explanations
list_audio_inputs() {
  echo "=== Audio Input Devices ==="
  echo "Note: Devices marked (monitor) will record system audio output"
  echo
  pactl list sources short | awk '{print NR". "$2}' | while read -r num dev; do
    formatted=$(format_device_name "$dev")
    if [[ $dev =~ "monitor" ]]; then
      echo "$num. $formatted (records system audio)"
    else
      echo "$num. $formatted (records from device)"
    fi
    echo
  done
}

# List available audio output devices
list_audio_outputs() {
  echo "=== Audio Output Devices ==="
  echo
  pactl list sinks short | awk '{print NR". "$2}' | while read -r num dev; do
    formatted=$(format_device_name "$dev")
    echo "$num. $formatted"
    echo
    echo
  done
}

# Select audio input and output devices
select_audio() {
  echo "Selecting audio input device..."
  list_audio_inputs
  
  # Get current device number and name if set
  current_num=""
  current_name=""
  if [ -n "$AUDIO_DEVICE_IN" ]; then
    current_num=$(pactl list sources short | awk -v dev="$AUDIO_DEVICE_IN" '{if ($2 == dev) print NR}')
    current_name="$AUDIO_DEVICE_IN"
  fi
  
  # Show prompt with current device number and name
  if [ -n "$current_num" ]; then
    echo "Current: $current_name"
    read -rp "Enter PulseAudio device number [$current_num]: " input_choice
    input_choice=${input_choice:-$current_num}
  else
    read -rp "Enter PulseAudio device number: " input_choice
  fi
  
  # Process selection
  if [ -n "$input_choice" ]; then
    AUDIO_DEVICE_IN=$(pactl list sources short | awk -v choice="$input_choice" 'NR==choice {print $2}')
    if [ -z "$AUDIO_DEVICE_IN" ]; then
      echo "Error: Invalid selection"
      exit 1
    fi
    echo "Selected input device: $AUDIO_DEVICE_IN"
  fi

  echo -e "\nSelecting audio output device..."
  list_audio_outputs
  
  # Get current output device number and name if set
  current_num=""
  current_name=""
  if [ -n "$AUDIO_DEVICE_OUT" ]; then
    current_num=$(pactl list sinks short | awk -v dev="$AUDIO_DEVICE_OUT" '{if ($2 == dev) print NR}')
    current_name="$AUDIO_DEVICE_OUT"
  fi
  
  # Show prompt with current device number and name
  if [ -n "$current_num" ]; then
    echo "Current: $current_name"
    read -rp "Enter PulseAudio device number [$current_num]: " output_choice
    output_choice=${output_choice:-$current_num}
  else
    read -rp "Enter PulseAudio device number: " output_choice
  fi
  
  # Process selection
  if [ -n "$output_choice" ]; then
    AUDIO_DEVICE_OUT=$(pactl list sinks short | awk -v choice="$output_choice" 'NR==choice {print $2}')
    if [ -z "$AUDIO_DEVICE_OUT" ]; then
      echo "Error: Invalid selection"
      exit 1
    fi
    echo "Selected output device: $AUDIO_DEVICE_OUT"
  fi
}

# Configure audio settings
configure_audio() {
  echo "=== Audio Configuration ==="
  echo "1. Configure Recording Device"
  echo "2. Configure Playback Device"
  read -rp "Select option [1]: " config_choice
  config_choice=${config_choice:-1}

  case "$config_choice" in
    1)
      configure_recording
      ;;
    2)
      configure_playback
      ;;
  esac
}

configure_recording() {
  echo "=== Recording Device Setup ==="
  echo "1. PulseAudio (default)"
  echo "2. ALSA (direct hardware access)"
  read -rp "Select audio backend [1]: " audio_choice
  audio_choice=${audio_choice:-1}

  case "$audio_choice" in
    1)
      export ST_AUDIO_BACKEND="pulse"
      list_audio_inputs
      
      # Get current device number if set
      current_num=""
      if [ -n "$ST_PULSE_IN_DEVICE" ]; then
        current_num=$(pactl list sources short | awk -v dev="$ST_PULSE_IN_DEVICE" '{if ($2 == dev) print NR}')
        echo "Current: $ST_PULSE_IN_DEVICE"
      fi
      
      read -rp "Enter PulseAudio device number ${current_num:+[$current_num]}: " pulse_choice
      pulse_choice=${pulse_choice:-$current_num}
      
      if [ -n "$pulse_choice" ]; then
        device=$(pactl list sources short | awk -v choice="$pulse_choice" 'NR==choice {print $2}')
        if [ -n "$device" ]; then
          export ST_PULSE_IN_DEVICE="$device"
          export ST_AUDIO_IN_DEVICE="$device"  # For compatibility
        else
          echo "Invalid device number, using default"
          export ST_PULSE_IN_DEVICE="@DEFAULT_SOURCE@"
          export ST_AUDIO_IN_DEVICE="@DEFAULT_SOURCE@"
        fi
      fi
      configure_buffer_size
      ;;
    2)
      export ST_AUDIO_BACKEND="alsa"
      list_audio_inputs
      
      # Get current ALSA device number if set
      current_num=""
      if [ -n "$ST_ALSA_IN_DEVICE" ] && [[ "$ST_ALSA_IN_DEVICE" =~ ^hw:[0-9]+$ ]]; then
        card_num=${ST_ALSA_IN_DEVICE#hw:}
        current_num=$(arecord -l | grep "^card" | awk -v card="$card_num" '$2 == card {print NR}')
        echo "Current: $ST_ALSA_IN_DEVICE"
      fi
      
      read -rp "Enter ALSA device number ${current_num:+[$current_num]}: " alsa_choice
      alsa_choice=${alsa_choice:-$current_num}
      
      if [ -n "$alsa_choice" ]; then
        device=$(arecord -l | grep "^card" | sed -n "${alsa_choice}p" | sed 's/^card \([0-9]*\):.*$/hw:\1/')
        if [ -n "$device" ]; then
          export ST_ALSA_IN_DEVICE="$device"
          export ST_AUDIO_IN_DEVICE="$device"  # For compatibility
        else
          echo "Invalid device number, using default"
          export ST_ALSA_IN_DEVICE="default"
          export ST_AUDIO_IN_DEVICE="default"
        fi
      fi
      ;;
  esac
  save_env
}

configure_playback() {
  echo "=== Playback Device Setup ==="
  echo "1. PulseAudio (default)"
  echo "2. ALSA (direct hardware access)"
  read -rp "Select audio backend [1]: " audio_choice
  audio_choice=${audio_choice:-1}

  case "$audio_choice" in
    1)
      export ST_AUDIO_OUT_BACKEND="pulse"
      list_audio_outputs
      
      # Get current device number if set
      current_num=""
      if [ -n "$ST_PULSE_OUT_DEVICE" ]; then
        current_num=$(pactl list sinks short | awk -v dev="$ST_PULSE_OUT_DEVICE" '{if ($2 == dev) print NR}')
        echo "Current: $ST_PULSE_OUT_DEVICE"
      fi
      
      read -rp "Enter PulseAudio device number ${current_num:+[$current_num]}: " pulse_choice
      pulse_choice=${pulse_choice:-$current_num}
      
      if [ -n "$pulse_choice" ]; then
        device=$(pactl list sinks short | awk -v choice="$pulse_choice" 'NR==choice {print $2}')
        if [ -n "$device" ]; then
          export ST_PULSE_OUT_DEVICE="$device"
          export ST_AUDIO_OUT_DEVICE="$device"  # For compatibility
        else
          echo "Invalid device number, using default"
          export ST_PULSE_OUT_DEVICE="@DEFAULT_SINK@"
          export ST_AUDIO_OUT_DEVICE="@DEFAULT_SINK@"
        fi
      fi
      ;;
    2)
      export ST_AUDIO_OUT_BACKEND="alsa"
      list_audio_outputs
      
      # Get current ALSA device number if set
      current_num=""
      if [ -n "$ST_ALSA_OUT_DEVICE" ] && [[ "$ST_ALSA_OUT_DEVICE" =~ ^hw:[0-9]+$ ]]; then
        card_num=${ST_ALSA_OUT_DEVICE#hw:}
        current_num=$(aplay -l | grep "^card" | awk -v card="$card_num" '$2 == card {print NR}')
        echo "Current: $ST_ALSA_OUT_DEVICE"
      fi
      
      read -rp "Enter ALSA device number ${current_num:+[$current_num]}: " alsa_choice
      alsa_choice=${alsa_choice:-$current_num}
      
      if [ -n "$alsa_choice" ]; then
        device=$(aplay -l | grep "^card" | sed -n "${alsa_choice}p" | sed 's/^card \([0-9]*\):.*$/hw:\1/')
        if [ -n "$device" ]; then
          export ST_ALSA_OUT_DEVICE="$device"
          export ST_AUDIO_OUT_DEVICE="$device"  # For compatibility
        else
          echo "Invalid device number, using default"
          export ST_ALSA_OUT_DEVICE="default"
          export ST_AUDIO_OUT_DEVICE="default"
        fi
      fi
      ;;
  esac
  save_env
}

configure_buffer_size() {
  echo "Buffer Size Options:"
  echo "1. Normal (1024, default)"
  echo "2. Large (2048, may help with choppy audio)"
  echo "3. Small (512, lower latency)"
  echo "4. Custom"
  read -rp "Select buffer size [1]: " buffer_choice
  
  case "${buffer_choice:-1}" in
    1) export ST_BUFFER_SIZE=1024 ;;
    2) export ST_BUFFER_SIZE=2048 ;;
    3) export ST_BUFFER_SIZE=512 ;;
    4)
      read -rp "Enter custom buffer size [1024]: " custom_buffer
      export ST_BUFFER_SIZE=${custom_buffer:-1024}
      ;;
  esac
}

#MULTICAT_START#
# dir: /Users/mricos/src/screentool
# file: screentool_env.sh
# notes:
#MULTICAT_END#
#!/bin/bash
# screentool_env.sh - Environment variable management for screentool

# Define default paths
ST_SRC=${ST_SRC:-"$HOME/src/screentool"}
ST_DIR=${ST_DIR:-"$HOME/recordings"}

# Define environment configuration files
SRC_ENV="$ST_SRC/screentool.env"
DIR_ENV="$ST_DIR/screentool.env"

# Load environment variables from files
load_env() {
    local found=0
    [ -n true ] && echo "ST_SRC=$ST_SRC"
    [ -n true ] && echo "ST_DIR=$ST_DIR"

    # First try source directory config
    if [ -f "$SRC_ENV" ]; then
        echo "SRC_ENV=$SRC_ENV"
        source "$SRC_ENV"
        found=1
    fi
    
    # Then try recordings directory config (will override if exists)
    if [ -f "$DIR_ENV" ]; then
        echo "DIR_ENV=$DIR_ENV"
        source "$DIR_ENV"
        found=1
    fi
    
    if [ $found -eq 0 ]; then
        echo "No environment configuration files found."
        echo "Looked in:"
        echo "  $SRC_ENV"
        echo "  $DIR_ENV"
    fi
}

save_env() {
    echo "Saving environment variables..."
    
    # Create directories if they don't exist
    mkdir -p "$(dirname "$SRC_ENV")"
    mkdir -p "$(dirname "$DIR_ENV")"
    
    # Remove old env files
    rm -f "$SRC_ENV"
    rm -f "$DIR_ENV"
    
    # Create new env file with current settings
    {
        # Base paths
        echo "export ST_SRC=\"$ST_SRC\""
        echo "export ST_DIR=\"$ST_DIR\""
        
        # Display settings
        echo "export DISPLAY=\"$DISPLAY\""
        echo "export SCREEN_GEOMETRY=\"$SCREEN_GEOMETRY\""
        
        # Audio settings
        echo "export ST_AUDIO_BACKEND=\"${ST_AUDIO_BACKEND:-pulse}\""
        echo "export ST_AUDIO_OUT_BACKEND=\"${ST_AUDIO_OUT_BACKEND:-pulse}\""
        echo "export ST_PULSE_IN_DEVICE=\"${ST_PULSE_IN_DEVICE}\""
        echo "export ST_PULSE_OUT_DEVICE=\"${ST_PULSE_OUT_DEVICE}\""
        echo "export ST_BUFFER_SIZE=\"${ST_BUFFER_SIZE:-1024}\""
        
        # Video settings
        echo "export VIDEO_CODEC=\"${VIDEO_CODEC:-libx264}\""
        echo "export PRESET=\"${PRESET:-veryfast}\""
        echo "export CRF=\"${CRF:-23}\""
        echo "export COMPRESSION_TUNE=\"${COMPRESSION_TUNE:-zerolatency}\""
        echo "export COMPRESSION_GOP=\"${COMPRESSION_GOP:-60}\""
        echo "export FRAMERATE=\"${FRAMERATE:-30}\""
        
        # Audio encoding settings
        echo "export AUDIO_CHANNELS=\"${AUDIO_CHANNELS:-2}\""
        echo "export AUDIO_CODEC=\"${AUDIO_CODEC:-aac}\""
        echo "export AUDIO_BITRATE=\"${AUDIO_BITRATE:-192k}\""
    } | tee "$SRC_ENV" > "$DIR_ENV"
    
    echo "Environment saved to:"
    echo "  $SRC_ENV"
    echo "  $DIR_ENV"
}

# Display environment variables
env_display() {
    echo "Current Environment Variables:"
    echo "-------------------------------"
    echo "ST_SRC=$ST_SRC"
    echo "ST_DIR=$ST_DIR"
    if [ -f "$SRC_ENV" ]; then
        echo "Source environment ($SRC_ENV):"
        cat "$SRC_ENV"
    fi
    if [ -f "$DIR_ENV" ]; then
        echo "Directory environment ($DIR_ENV):"
        cat "$DIR_ENV"
    fi
    echo "-------------------------------"
}

#MULTICAT_START#
# dir: /Users/mricos/src/screentool
# file: screentool_info.sh
# notes:
#MULTICAT_END#
# Display usage information
usage() {
  echo "Usage: $0 {record|list|info <file>|summary <file>|json <file>|input|output|select|save|load|env}"
  echo ""
  echo "Commands:"
  echo "  record             Start screen recording (Ctrl-C to stop)."
  echo "  list               List recordings with their properties."
  echo "  summary <file>     Show a brief summary of the video file."
  echo "  json <file>        Show detailed JSON metadata of the video file."
  echo "  info <file>        Show human-readable info for the given file."
  echo "  input              Show available audio input devices."
  echo "  output             Show available audio output devices."
  echo "  select             Select audio input and output devices."
  echo "  save               Save environment to ST_DIR/screentool.env."
  echo "  load               Load environment to ST_DIR/screentool.env."
  echo "  env                Show all environment variables being used."
  exit 0
}

# Parse time format to seconds
parse_time() {
    local time="$1"
    local seconds=0
    
    # Handle HhMmSs.ms format (e.g., 3h2m3s13ms or 2m30s)
    if [[ $time =~ ([0-9]+h)?([0-9]+m)?([0-9]+s)?([0-9]+ms)? ]]; then
        [[ $time =~ ([0-9]+)h ]] && seconds=$((seconds + ${BASH_REMATCH[1]} * 3600))
        [[ $time =~ ([0-9]+)m ]] && seconds=$((seconds + ${BASH_REMATCH[1]} * 60))
        [[ $time =~ ([0-9]+)s ]] && seconds=$((seconds + ${BASH_REMATCH[1]}))
        [[ $time =~ ([0-9]+)ms ]] && seconds=$(bc <<< "scale=3; $seconds + ${BASH_REMATCH[1]}/1000")
    # Handle MM:SS format
    elif [[ $time =~ ^[0-9]+:[0-9]+$ ]]; then
        local min=${time%:*}
        local sec=${time#*:}
        seconds=$(( min * 60 + sec ))
    # Handle HH:MM:SS format
    elif [[ $time =~ ^[0-9]+:[0-9]+:[0-9]+$ ]]; then
        IFS=: read -r h m s <<< "$time"
        seconds=$(( h * 3600 + m * 60 + s ))
    # Handle raw seconds
    elif [[ $time =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        seconds=$time
    fi
    echo "$seconds"
}

# Format seconds to human readable time
format_time() {
    local seconds="$1"
    local format="${2:-human}" # human, colon, or short
    
    case $format in
        human)
            local h=$((seconds/3600))
            local m=$(((seconds%3600)/60))
            local s=$((seconds%60))
            local ms=$(echo "scale=3; $seconds - ($h*3600 + $m*60 + $s)" | bc | sed 's/0\+$//')
            local result=""
            [[ $h -gt 0 ]] && result+="${h}h"
            [[ $m -gt 0 ]] && result+="${m}m"
            [[ $s -gt 0 ]] && result+="${s}s"
            [[ $ms != "0" && $ms != "" ]] && result+="${ms#.}ms"
            echo "$result"
            ;;
        colon)
            printf "%02d:%02d:%02d" $((seconds/3600)) $((seconds%3600/60)) $((seconds%60))
            ;;
        short)
            printf "%.3fs" "$seconds"
            ;;
    esac
}

# List recordings with their properties
list_recordings() {
    local dir="${1:-$ST_DIR}"
    local clips_file="$ST_DIR/clips.txt"
    
    # Print header
    printf "%-3s %-30s %-10s %-12s %s\n" "n" "name" "len" "res" "clips"
    echo "------------------------------------------------------------------------"
    
    # Load clip points if file exists
    declare -A markers
    if [ -f "$clips_file" ]; then
        while IFS=':' read -r file start duration label || [ -n "$file" ]; do
            # Skip empty lines and comments
            [[ -z "$file" || "$file" =~ ^[[:space:]]*# ]] && continue
            # Format times in human-readable format
            local start_fmt=$(format_time "$start")
            local duration_fmt=$(format_time "$duration")
            # Append to existing markers or create new entry
            if [ -n "${markers[$file]}" ]; then
                markers[$file]="${markers[$file]}, $label($start_fmt+$duration_fmt)"
            else
                markers[$file]="$label($start_fmt+$duration_fmt)"
            fi
        done < "$clips_file"
    fi
    
    # Process each MP4 file
    local n=1
    find "$dir" -maxdepth 1 -name "*.mp4" -type f | sort | while read -r file; do
        # Get basic file info
        local filename=$(basename "$file")
        
        # Get video info using ffprobe
        local info
        info=$(ffprobe -v quiet -print_format json -show_format -show_streams "$file")
        
        # Extract duration and round to nearest second
        local duration
        duration=$(echo "$info" | jq -r '.format.duration // empty' | awk '{printf "%d:%02d", $1/60, $1%60}')
        
        # Extract resolution from first video stream
        local resolution=""
        local width height
        width=$(echo "$info" | jq -r '.streams[] | select(.codec_type=="video") | .width // empty' | head -n1)
        height=$(echo "$info" | jq -r '.streams[] | select(.codec_type=="video") | .height // empty' | head -n1)
        if [ -n "$width" ] && [ -n "$height" ]; then
            resolution="${width}x${height}"
        fi
        
        # Get markers if any
        local marker_list="${markers[$filename]:-}"
        
        # Print formatted line
        printf "%-3d %-30s %-10s %-12s %s\n" \
            "$n" "$filename" "${duration:--}" "${resolution:--}" "$marker_list"
        
        n=$((n + 1))
    done
}

# Add clip point to a recording
add_marker() {
    local file="$1"
    local start="$2"
    local duration="$3"
    local label="$4"
    local clips_file="$ST_DIR/clips.txt"
    
    # Ensure file exists and is in ST_DIR
    if [ ! -f "$ST_DIR/$file" ]; then
        echo "Error: File $file not found in $ST_DIR"
        return 1
    fi
    
    # Convert start and duration to seconds
    local start_sec=$(parse_time "$start")
    local duration_sec=$(parse_time "$duration")
    
    # Create clips file if it doesn't exist
    if [ ! -f "$clips_file" ]; then
        echo "# Clip points for screentool recordings" > "$clips_file"
        echo "# Format: filename:start:duration:label" >> "$clips_file"
        echo "# Times can be in any of these formats:" >> "$clips_file"
        echo "#   - Human readable: 1h2m3s500ms" >> "$clips_file"
        echo "#   - Colon format: 01:02:03" >> "$clips_file"
        echo "#   - Raw seconds: 3600.500" >> "$clips_file"
        echo "" >> "$clips_file"
    fi
    
    # Add new clip point
    echo "$file:$start_sec:$duration_sec:$label" >> "$clips_file"
    echo "Added clip point '$label' to $file ($(format_time "$start_sec") for $(format_time "$duration_sec"))"
}

# Remove clip point from a recording
remove_marker() {
    local file="$1"
    local label="$2"
    local clips_file="$ST_DIR/clips.txt"
    local temp_file="$ST_DIR/clips.tmp"
    
    # Ensure clips file exists
    if [ ! -f "$clips_file" ]; then
        echo "Error: No clips file found"
        return 1
    fi
    
    # Remove clip point, preserving comments and empty lines
    awk -F: -v file="$file" -v label="$label" '
        $0 ~ /^[[:space:]]*#/ { print; next }  # Preserve comments
        /^[[:space:]]*$/ { print; next }       # Preserve empty lines
        $1 == file && $4 == label { next }     # Skip matching clip point
        { print }                              # Print everything else
    ' "$clips_file" > "$temp_file"
    
    # Replace original file
    mv "$temp_file" "$clips_file"
    echo "Removed clip point '$label' from $file"
}

# Generate JSON metadata for the video file
json_metadata() {
  [ -z "$1" ] && { echo "Error: Please specify a file."; exit 1; }
  
  if [ ! -f "$1" ]; then
    echo "Error: File not found."
    exit 1
  fi
  
  ffprobe -hide_banner -v quiet -print_format json -show_format -show_streams "$1" | jq .
}

# Generate a summary of the video file using ffmpeg JSON output and jq
summary() {
  [ -z "$1" ] && { echo "Error: Please specify a file."; exit 1; }
  
  if [ ! -f "$1" ]; then
    echo "Error: File not found."
    exit 1
  fi

  INFO=$(ffprobe -hide_banner -v quiet -print_format json -show_format -show_streams "$1")
  
  DURATION=$(echo "$INFO" | jq -r '.format.duration | tonumber | floor')
  SIZE=$(echo "$INFO" | jq -r '.format.size | tonumber / 1048576 | floor')
  BITRATE=$(echo "$INFO" | jq -r '.format.bit_rate | tonumber / 1000 | floor')
  VIDEO_CODEC=$(echo "$INFO" | jq -r '.streams[] | select(.codec_type=="video") | .codec_name' | head -n1)
  AUDIO_CODEC=$(echo "$INFO" | jq -r '.streams[] | select(.codec_type=="audio") | .codec_name' | head -n1)
  CHANNELS=$(echo "$INFO" | jq -r '.streams[] | select(.codec_type=="audio") | .channels' | head -n1)

  MINUTES=$((DURATION / 60))
  SECONDS=$((DURATION % 60))

  echo "Duration: ${MINUTES} min ${SECONDS} sec, Size: ${SIZE} MB, Bitrate: ${BITRATE} kbps, Streams: video: ${VIDEO_CODEC}, audio: ${AUDIO_CODEC}, Channels: ${CHANNELS}ch"
}

#MULTICAT_START#
# dir: /Users/mricos/src/screentool
# file: screentool_record.sh
# notes:
#MULTICAT_END#
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

