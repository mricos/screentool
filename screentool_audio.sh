#!/usr/bin/env bash
# screentool_audio.sh

source "$ST_SRC/screentool_macos_devices.sh"

list_audio_inputs() {
  if [[ "$ST_OS_TYPE" == "macos" ]]; then
    print_macos_devices
    echo
    echo "Refer to the '[index] Device Name' lines above."
    echo "If you do not see your microphone or virtual device, ensure:"
    echo " - The device is enabled in System Preferences."
    echo " - You have granted Terminal permissions for microphone."
  else
    pactl list sources short | awk '{print NR". "$2}'
  fi
}

list_audio_outputs() {
  if [[ "$ST_OS_TYPE" == "macos" ]]; then
    echo "(audio output selection not directly supported via avfoundation; use system audio routing or BlackHole/Loopback.)"
    print_macos_devices
  else
    pactl list sinks short | awk '{print NR". "$2}'
  fi
}

configure_audio() {
  if [[ "$ST_OS_TYPE" == "macos" ]]; then
    print_macos_devices
    echo
    read -rp "Enter AVFoundation audio input device index as shown above (e.g. 0): " idx
    if [[ ! "$idx" =~ ^[0-9]+$ ]]; then
      echo "Invalid input, using default (0)."
      idx="0"
    fi
    export ST_AVFOUNDATION_AUDIO_DEVICE="$idx"
    save_env
    echo "Saved audio device index: $ST_AVFOUNDATION_AUDIO_DEVICE"
  else
    configure_recording
    configure_playback
  fi
}

