#!/bin/bash
# screentool_audio.sh - Audio device selection and processing

# List available audio input devices
list_audio_inputs() {
  echo "Available Audio Input Devices:"
  pactl list sources short | awk '{print NR". "$2}'
}

# List available audio output devices
list_audio_outputs() {
  echo "Available Audio Output Devices:"
  pactl list sinks short | awk '{print NR". "$2}'
}

# Select audio input and output devices
select_audio() {
  echo "Selecting audio input device..."
  list_audio_inputs
  read -rp "Select input device number: " input_choice
  AUDIO_DEVICE_IN=$(pactl list sources short | awk -v choice="$input_choice" 'NR==choice {print $2}')

  echo "Selecting audio output device..."
  list_audio_outputs
  read -rp "Select output device number: " output_choice
  AUDIO_DEVICE_OUT=$(pactl list sinks short | awk -v choice="$output_choice" 'NR==choice {print $2}')

  if [ -z "$AUDIO_DEVICE_IN" ] || [ -z "$AUDIO_DEVICE_OUT" ]; then
    echo "Error: Invalid selection. Please try again."
    exit 1
  fi
}
