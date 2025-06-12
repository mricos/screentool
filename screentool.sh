#!/usr/bin/env bash
# screentool.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export ST_SRC=${ST_SRC:-"$HOME/src/screentool"}
export ST_DIR=${ST_DIR:-"$HOME/recordings"}

source "$SCRIPT_DIR/screentool_env.sh"
source "$SCRIPT_DIR/screentool_macos_devices.sh"
source "$SCRIPT_DIR/screentool_audio.sh"
source "$SCRIPT_DIR/screentool_video.sh"
source "$SCRIPT_DIR/screentool_record.sh"
source "$SCRIPT_DIR/screentool_play.sh"
source "$SCRIPT_DIR/screentool_info.sh"

load_env

usage() {
  echo "Usage: $0 {record|play|list|info <file>|summary <file>|json <file>|input|output|video|select|audio|save|load|env}"
  exit 1
}

check_dependencies() {
  case "$ST_OS_TYPE" in
    macos)
      for dep in ffmpeg; do
        command -v "$dep" >/dev/null || { echo "Missing $dep"; exit 1; }
      done
      ;;
    linux)
      for dep in ffmpeg jq pactl xrandr; do
        command -v "$dep" >/dev/null || { echo "Missing $dep"; exit 1; }
      done
      ;;
  esac
}

select_display() {
  case "$ST_OS_TYPE" in
    macos)
      print_macos_devices
      read -rp "Enter AVFoundation video device index for screen (default 0): " vid
      export ST_AVFOUNDATION_VIDEO_DEVICE="${vid:-0}"
      # Try to auto-detect geometry
      res=$(system_profiler SPDisplaysDataType | grep Resolution | head -n1 | awk -F: '{print $2}' | xargs)
      width=$(echo "$res" | awk '{print $1}')
      height=$(echo "$res" | awk '{print $3}')
      SCREEN_GEOMETRY="${width}x${height}+0+0"
      export SCREEN_GEOMETRY
      save_env
      ;;
    linux)
      # Existing xrandr/selection logic (not shown, no change)
      ;;
  esac
}

case "$1" in
  record)      record "$2" "$SCREEN_GEOMETRY" ;;
  play)        play_recording "$2" ;;
  list)        list_recordings ;;
  info)        summary "$2" ;;
  summary)     summary "$2" ;;
  json)        json_metadata "$2" ;;
  input)       list_audio_inputs ;;
  output)      list_audio_outputs ;;
  video)       list_video_inputs ;;
  select)      select_display ;;
  audio)       configure_audio ;;
  save)        save_env ;;
  load)        load_env ;;
  env)         env_display ;;
  *)           usage ;;
esac

