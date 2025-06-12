#!/usr/bin/env bash
# screentool_macos_devices.sh

print_macos_devices() {
  echo
  echo "Querying AVFoundation video and audio devices (macOS only)..."
  echo "-----------------------------------------------------------"
  local output
  output="$(ffmpeg -f avfoundation -list_devices true -i "" 2>&1)"
  if [[ "$output" == "" ]]; then
    echo "ffmpeg output was empty; is ffmpeg installed?"
    return 1
  fi

  local found=0

  # Print video devices section
  echo "$output" | grep -A10 'AVFoundation video devices' | while read -r line; do
    [[ "$line" == "" ]] && continue
    [[ "$line" =~ 'AVFoundation video devices' ]] && found=1
    [[ "$found" -eq 1 ]] && echo "$line"
    [[ "$line" =~ 'AVFoundation audio devices' ]] && break
  done

  found=0
  # Print audio devices section
  echo
  echo "$output" | grep -A10 'AVFoundation audio devices' | while read -r line; do
    [[ "$line" == "" ]] && continue
    [[ "$line" =~ 'AVFoundation audio devices' ]] && found=1
    [[ "$found" -eq 1 ]] && echo "$line"
  done

  if ! echo "$output" | grep -q '\[AVFoundation'; then
    echo "No AVFoundation devices found. Troubleshooting:"
    echo " - Make sure ffmpeg has avfoundation enabled."
    echo " - Check System Preferences > Security & Privacy > Privacy (Microphone, Screen Recording)."
    echo " - Try running: which ffmpeg"
    return 2
  fi
  return 0
}

