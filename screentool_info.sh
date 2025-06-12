#!/usr/bin/env bash

usage() {
  echo "Usage: $0 {record|play|list|info <file>|summary <file>|json <file>|input|output|video|select|audio|save|load|env}"
  exit 1
}

list_recordings() {
  local dir="${1:-$ST_DIR}"
  local clips_file="$ST_DIR/clips.txt"
  printf "%-3s %-30s %-10s %-12s %s\n" "n" "name" "len" "res" "clips"
  echo "------------------------------------------------------------------------"

  if [ -f "$clips_file" ]; then
    while IFS=: read -r file start duration label; do
      [ -z "$file" ] && continue
      # Just print, don't try associative arrays (bash 3 compat)
      echo "Clip: $file @ $start+$duration $label"
    done < "$clips_file"
  fi

  local n=1
  for file in "$dir"/*.mp4; do
    [ -e "$file" ] || continue
    local filename=$(basename "$file")
    local info
    info=$(ffprobe -v quiet -print_format json -show_format -show_streams "$file")
    local duration
    duration=$(echo "$info" | grep -m1 '"duration"' | sed 's/[^0-9.]//g' | awk '{print int($1/60)":"int($1%60)}')
    local width height
    width=$(echo "$info" | grep -A4 video | grep '"width"' | head -1 | sed 's/[^0-9]//g')
    height=$(echo "$info" | grep -A4 video | grep '"height"' | head -1 | sed 's/[^0-9]//g')
    local resolution="${width}x${height}"
    printf "%-3d %-30s %-10s %-12s %s\n" "$n" "$filename" "${duration:--}" "${resolution:--}" "-"
    n=$((n + 1))
  done
}

summary() {
  [ -z "$1" ] && { echo "Please specify a file"; exit 1; }
  if [ ! -f "$1" ]; then
    echo "Error: File not found."
    exit 1
  fi
  local info
  info=$(ffprobe -hide_banner -v quiet -print_format json -show_format -show_streams "$1")
  local duration
  duration=$(echo "$info" | grep -m1 '"duration"' | sed 's/[^0-9.]//g' | awk '{print int($1)}')
  local size
  size=$(stat -f "%z" "$1" 2>/dev/null || stat --printf="%s" "$1" 2>/dev/null)
  size=$(awk "BEGIN {printf \"%.1f\", $size/1048576}")
  local video_codec
  video_codec=$(echo "$info" | grep -A2 video | grep '"codec_name"' | head -1 | cut -d\" -f4)
  local audio_codec
  audio_codec=$(echo "$info" | grep -A2 audio | grep '"codec_name"' | head -1 | cut -d\" -f4)
  echo "Duration: ${duration}s, Size: ${size} MB, Video: $video_codec, Audio: $audio_codec"
}

json_metadata() {
  [ -z "$1" ] && { echo "Please specify a file"; exit 1; }
  ffprobe -hide_banner -v quiet -print_format json -show_format -show_streams "$1"
}

env_display() {
  echo "Current Environment Variables:"
echo "-------------------------------"
env | grep '^ST\_|^DISPLAY|^VIDEO\_CODEC|^AUDIO\_CODEC'
echo "-------------------------------"
}
