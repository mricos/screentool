#!/usr/bin/env bash
# screentool_video.sh

source "$ST_SRC/screentool_macos_devices.sh"

list_video_inputs() {
  if [[ "$ST_OS_TYPE" == "macos" ]]; then
    print_macos_devices
    echo
    echo "Use the '[index] Device Name' lines above to pick a screen or camera."
    echo "For desktop capture: use the index for 'Capture screen 0' (usually 0) or 'Capture screen 1'."
  else
    xrandr --listmonitors
  fi
}

configure_video() {
  if [[ "$ST_OS_TYPE" == "macos" ]]; then
    print_macos_devices
    echo
    read -rp "Enter AVFoundation video device index (e.g. 0 for screen 0): " vidx
    if [[ ! "$vidx" =~ ^[0-9]+$ ]]; then
      echo "Invalid input, using default (0)."
      vidx="0"
    fi
    export ST_AVFOUNDATION_VIDEO_DEVICE="$vidx"
    save_env
    echo "Saved video device index: $ST_AVFOUNDATION_VIDEO_DEVICE"
  else
    echo "On Linux, video input selection is handled by xrandr and DISPLAY."
  fi
}

