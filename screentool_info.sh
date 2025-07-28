#!/usr/bin/env bash

usage() {
  cat << 'EOF'
screentool - Screen Recording Tool

USAGE:
  record [file]         Record screen
  play [file]           Play recording
  list                  List recordings
  geometry              Show screen layout
  select-area           Set recording area
  help                  Show detailed help

Quick start: ./screentool.sh record demo.mp4
For full help: ./screentool.sh help
EOF
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
  env | grep '^ST_\|^DISPLAY\|^VIDEO_CODEC\|^AUDIO_CODEC\|^PRESET\|^CRF\|^FRAMERATE\|^COMPRESSION_\|^SCREEN_GEOMETRY'
  echo "-------------------------------"
  if [[ -n "$ST_CROP_GEOMETRY" ]]; then
    echo "Area recording is ENABLED. Crop geometry: $ST_CROP_GEOMETRY"
  else
    echo "Area recording is DISABLED. Recording full screen."
  fi
}

ascii_geometry() {
  echo "Screen Geometry Visualization"
  echo "============================"
  echo
  
  # Get screen resolution
  case "$ST_OS_TYPE" in
    macos)
      # Get display info from system_profiler
      local displays_info
      displays_info=$(system_profiler SPDisplaysDataType 2>/dev/null)
      
      if [[ -n "$displays_info" ]]; then
        echo "Detected Displays:"
        echo "$displays_info" | grep -E "(Display|Resolution)" | while read -r line; do
          if [[ "$line" =~ Display ]]; then
            echo "  $line"
          elif [[ "$line" =~ Resolution ]]; then
            echo "    $line"
          fi
        done
        echo
      fi
      
      # Parse current screen geometry
      local width height x_offset y_offset
      if [[ -n "$SCREEN_GEOMETRY" ]]; then
        # Parse format like "1920x1080+0+0"
        width=$(echo "$SCREEN_GEOMETRY" | sed 's/x.*//')
        height=$(echo "$SCREEN_GEOMETRY" | sed 's/.*x\([0-9]*\)+.*/\1/')
        x_offset=$(echo "$SCREEN_GEOMETRY" | sed 's/.*+\([0-9]*\)+.*/\1/')
        y_offset=$(echo "$SCREEN_GEOMETRY" | sed 's/.*+[0-9]*+\([0-9]*\).*/\1/')
      else
        # Try to get from system_profiler
        local res=$(echo "$displays_info" | grep Resolution | head -n1 | awk -F: '{print $2}' | xargs)
        width=$(echo "$res" | awk '{print $1}')
        height=$(echo "$res" | awk '{print $3}')
        x_offset=0
        y_offset=0
      fi
      ;;
    linux)
      # Use xrandr for Linux
      local xrandr_output
      xrandr_output=$(xrandr 2>/dev/null | grep " connected")
      echo "Detected Displays:"
      echo "$xrandr_output"
      echo
      
      # Parse SCREEN_GEOMETRY or get primary display
      if [[ -n "$SCREEN_GEOMETRY" ]]; then
        width=$(echo "$SCREEN_GEOMETRY" | sed 's/x.*//')
        height=$(echo "$SCREEN_GEOMETRY" | sed 's/.*x\([0-9]*\)+.*/\1/')
        x_offset=$(echo "$SCREEN_GEOMETRY" | sed 's/.*+\([0-9]*\)+.*/\1/')
        y_offset=$(echo "$SCREEN_GEOMETRY" | sed 's/.*+[0-9]*+\([0-9]*\).*/\1/')
      else
        local primary=$(echo "$xrandr_output" | grep "primary" | head -n1)
        if [[ -n "$primary" ]]; then
          local geom=$(echo "$primary" | grep -o '[0-9]*x[0-9]*+[0-9]*+[0-9]*')
          width=$(echo "$geom" | sed 's/x.*//')
          height=$(echo "$geom" | sed 's/.*x\([0-9]*\)+.*/\1/')
          x_offset=$(echo "$geom" | sed 's/.*+\([0-9]*\)+.*/\1/')
          y_offset=$(echo "$geom" | sed 's/.*+[0-9]*+\([0-9]*\).*/\1/')
        fi
      fi
      ;;
  esac
  
  # Default values if parsing failed
  width=${width:-1920}
  height=${height:-1080}
  x_offset=${x_offset:-0}
  y_offset=${y_offset:-0}
  
  echo "Recording Configuration:"
  echo "  Screen Geometry: ${width}x${height}+${x_offset}+${y_offset}"
  
  if [[ -n "$ST_CROP_GEOMETRY" ]]; then
    # Parse crop geometry format "width:height:x:y"
    local crop_width crop_height crop_x crop_y
    crop_width=$(echo "$ST_CROP_GEOMETRY" | cut -d: -f1)
    crop_height=$(echo "$ST_CROP_GEOMETRY" | cut -d: -f2)
    crop_x=$(echo "$ST_CROP_GEOMETRY" | cut -d: -f3)
    crop_y=$(echo "$ST_CROP_GEOMETRY" | cut -d: -f4)
    echo "  Crop Area: ${crop_width}x${crop_height} at (${crop_x},${crop_y})"
  else
    echo "  Crop Area: Full screen"
  fi
  echo
  
  # Generate ASCII representation
  echo "ASCII Visualization:"
  local ascii_width=60
  local ascii_height=20
  
  # Calculate scale factors
  local scale_x scale_y
  scale_x=$(echo "$ascii_width $width" | awk '{printf "%.6f", $1 / $2}')
  scale_y=$(echo "$ascii_height $height" | awk '{printf "%.6f", $1 / $2}')
  
  # Draw the screen border
  echo "┌$(printf '─%.0s' $(seq 1 $ascii_width))┐"
  
  for ((row=1; row<=ascii_height; row++)); do
    echo -n "│"
    
    for ((col=1; col<=ascii_width; col++)); do
      local in_crop=false
      
      if [[ -n "$ST_CROP_GEOMETRY" ]]; then
        # Calculate actual pixel coordinates
        local actual_x actual_y
        actual_x=$(echo "$col $scale_x" | awk '{printf "%.0f", $1 / $2}')
        actual_y=$(echo "$row $scale_y" | awk '{printf "%.0f", $1 / $2}')
        
        # Check if this point is within the crop area
        if [[ $actual_x -ge $crop_x ]] && [[ $actual_x -lt $((crop_x + crop_width)) ]] && \
           [[ $actual_y -ge $crop_y ]] && [[ $actual_y -lt $((crop_y + crop_height)) ]]; then
          in_crop=true
        fi
      fi
      
      if [[ "$in_crop" == "true" ]]; then
        echo -n "█"  # Recording area
      elif [[ $row -eq 1 ]] || [[ $row -eq $ascii_height ]] || [[ $col -eq 1 ]] || [[ $col -eq $ascii_width ]]; then
        echo -n "▓"  # Screen edge
      else
        echo -n "░"  # Screen background
      fi
    done
    
    echo "│"
  done
  
  echo "└$(printf '─%.0s' $(seq 1 $ascii_width))┘"
  echo
  echo "Legend:"
  echo "  ░ Screen area"
  echo "  ▓ Screen edges"
  if [[ -n "$ST_CROP_GEOMETRY" ]]; then
    echo "  █ Recording area (crop)"
  else
    echo "  (Recording full screen)"
  fi
  echo
  echo "Aspect Ratio: $(echo "$width $height" | awk '{printf "%.2f", $1 / $2}'):1"
  local total_pixels
  total_pixels=$(echo "$width $height" | awk '{printf "%d", $1 * $2}')
  # Add comma formatting for readability
  echo "Total Pixels: $(printf "%'d" "$total_pixels" 2>/dev/null || echo "$total_pixels")"
}
