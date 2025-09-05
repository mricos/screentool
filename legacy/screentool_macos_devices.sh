#!/usr/bin/env bash
# screentool_macos_devices.sh

print_macos_devices() {
  echo
  echo "Querying AVFoundation video and audio devices (macOS only)..."
  echo "-----------------------------------------------------------"
  local output
  output="$(ffmpeg -f avfoundation -list_devices true -i dummy 2>&1)"
  if [[ "$output" == "" ]]; then
    echo "ffmpeg output was empty; is ffmpeg installed?"
    return 1
  fi

  # Extract and display video devices
  echo "VIDEO DEVICES:"
  echo "$output" | sed -n '/AVFoundation video devices:/,/AVFoundation audio devices:/p' | \
    grep -E '\[[0-9]+\]' | sed 's/.*\[\([0-9]*\)\] \(.*\)/  [\1] \2/'

  echo
  echo "AUDIO DEVICES:"
  echo "$output" | sed -n '/AVFoundation audio devices:/,$p' | \
    grep -E '\[[0-9]+\]' | sed 's/.*\[\([0-9]*\)\] \(.*\)/  [\1] \2/'

  if ! echo "$output" | grep -q '\[AVFoundation'; then
    echo
    echo "⚠️  No AVFoundation devices found. Troubleshooting:"
    echo " - Make sure ffmpeg has avfoundation enabled"
    echo " - Check System Preferences > Security & Privacy > Privacy"
    echo "   - Grant Terminal access to 'Screen Recording'"
    echo "   - Grant Terminal access to 'Microphone'"
    echo " - Try running: which ffmpeg"
    return 2
  fi
  return 0
}

