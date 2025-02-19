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
