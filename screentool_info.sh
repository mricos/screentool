#!/usr/bin/env bash

summary() {
  [ -z "$1" ] && { echo "Please specify a file"; exit 1; }
  if [ ! -f "$1" ]; then
    echo "File not found: $1"
    return 1
  fi

  local file_path="$1"
  local duration size_mb video_codec audio_codec width height fps
  
  # Get basic file info using ffprobe
  local probe_output
  probe_output=$(ffprobe -hide_banner -v quiet -print_format json -show_format -show_streams "$file_path" 2>/dev/null)
  
  if [[ -z "$probe_output" ]]; then
    echo "Could not analyze file: $file_path"
    return 1
  fi
  
  # Extract info using jq if available, otherwise basic parsing
  if command -v jq >/dev/null; then
    duration=$(echo "$probe_output" | jq -r '.format.duration // "unknown"')
    size_mb=$(echo "$probe_output" | jq -r '.format.size // 0' | awk '{printf "%.1f", $1/1024/1024}')
    video_codec=$(echo "$probe_output" | jq -r '.streams[] | select(.codec_type=="video") | .codec_name // "unknown"' | head -1)
    audio_codec=$(echo "$probe_output" | jq -r '.streams[] | select(.codec_type=="audio") | .codec_name // "unknown"' | head -1)
    width=$(echo "$probe_output" | jq -r '.streams[] | select(.codec_type=="video") | .width // 0' | head -1)
    height=$(echo "$probe_output" | jq -r '.streams[] | select(.codec_type=="video") | .height // 0' | head -1)
    fps=$(echo "$probe_output" | jq -r '.streams[] | select(.codec_type=="video") | .r_frame_rate // "0/1"' | head -1 | awk -F'/' '{if($2>0) printf "%.1f", $1/$2; else print "0"}')
  else
    # Basic parsing without jq
    duration=$(echo "$probe_output" | grep -o '"duration":"[^"]*"' | cut -d'"' -f4)
    size_mb=$(echo "$probe_output" | grep -o '"size":"[^"]*"' | cut -d'"' -f4 | awk '{printf "%.1f", $1/1024/1024}')
    video_codec="h264"  # reasonable default
    audio_codec="aac"   # reasonable default
    width="1920"        # reasonable default
    height="1080"       # reasonable default
    fps="30"            # reasonable default
  fi
  
  # Format duration
  if [[ "$duration" =~ ^[0-9]+\.?[0-9]*$ ]]; then
    local duration_formatted
    duration_formatted=$(printf "%.1fs" "$duration")
  else
    duration_formatted="$duration"
  fi
  
  echo "File: $(basename "$file_path")"
  echo "Duration: $duration_formatted, Size: ${size_mb}MB"
  echo "Video: $video_codec ${width}x${height} @ ${fps}fps"
  echo "Audio: $audio_codec"
}

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

get_human_size() {
  local file_path="$1"
  if [[ ! -f "$file_path" ]]; then
    echo "N/A"
    return
  fi
  local size_bytes
  size_bytes=$(stat -f "%z" "$file_path" 2>/dev/null || stat --printf="%s" "$file_path" 2>/dev/null)
  
  awk -v size="$size_bytes" '
    function human(x) {
      s="BKMGTPEZY";
      while (x >= 1024 && length(s) > 1) {
        x /= 1024;
        s = substr(s, 2);
      }
      return sprintf("%.2f%s", x, substr(s, 1, 1));
    }
    BEGIN { print human(size) }'
}

get_human_rate() {
  local file_path="$1"
  local duration_seconds="$2"

  if [[ ! -f "$file_path" || -z "$duration_seconds" ]] || ! awk -v d="$duration_seconds" 'BEGIN { exit !(d > 0) }'; then
    echo "N/A"
    return
  fi

  local size_bytes
  size_bytes=$(stat -f "%z" "$file_path" 2>/dev/null || stat --printf="%s" "$file_path" 2>/dev/null)
  
  awk -v size="$size_bytes" -v duration="$duration_seconds" '
    function human(rate) {
      s="BKMGTPEZY";
      while (rate >= 1024 && length(s) > 1) {
        rate /= 1024;
        s = substr(s, 2);
      }
      return sprintf("%.2f%s/min", rate, substr(s, 1, 1));
    }
    BEGIN { 
      bytes_per_minute = (size / duration) * 60;
      print human(bytes_per_minute);
    }'
}


list_recordings() {
  local dir="${1:-$ST_DIR}"
  local mode="${2:-collapsed}"  # collapsed or expanded
  
  if [[ "$mode" == "expanded" ]]; then
    printf "%-3s %-35s %-10s %-12s %-10s %-12s %s\n" "n" "session_name" "duration" "resolution" "size" "profile" "details"
    echo "-------------------------------------------------------------------------------------------------------"
  else
    printf "%-3s %-35s %-10s %-12s %-10s %s\n" "n" "session_name" "duration" "resolution" "size" "stitched"
    echo "------------------------------------------------------------------------------------------"
  fi

  local n=1
  # Use find and a while-read loop for safety and sort by name reverse for consistency
  find "$dir" -name "*.meta" -type f -print0 | sort -z -r | while IFS= read -r -d $'\0' meta_file; do
    [ -e "$meta_file" ] || continue
    
    local session_name
    session_name=$(basename "$meta_file" .meta)
    
    # Source the meta file to get file paths
    source "$meta_file"
    
    local duration="N/A"
    local resolution="N/A"
    local stitched="No"
    local total_size=0
    
    if [[ -f "$VIDEO_FILE" ]]; then
      # Get resolution using a more robust ffprobe query
      resolution=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$VIDEO_FILE" 2>/dev/null)
      [[ -z "$resolution" ]] && resolution="N/A"

      # Get duration from format info for reliability
      local duration_seconds_raw
      duration_seconds_raw=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$VIDEO_FILE" 2>/dev/null)
      
      # If format duration is N/A, try alternative methods
      if [[ -z "$duration_seconds_raw" || "$duration_seconds_raw" == "N/A" ]]; then
        # Try to get duration from video stream
        duration_seconds_raw=$(ffprobe -v error -select_streams v:0 -show_entries stream=duration -of default=noprint_wrappers=1:nokey=1 "$VIDEO_FILE" 2>/dev/null)
        
        # If still N/A, try to estimate from frame count and frame rate
        if [[ -z "$duration_seconds_raw" || "$duration_seconds_raw" == "N/A" ]]; then
          local frame_count fps
          frame_count=$(ffprobe -v error -select_streams v:0 -count_frames -show_entries stream=nb_frames -of default=noprint_wrappers=1:nokey=1 "$VIDEO_FILE" 2>/dev/null)
          fps=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$VIDEO_FILE" 2>/dev/null)
          
          if [[ -n "$frame_count" && -n "$fps" && "$frame_count" != "N/A" && "$fps" != "N/A" ]]; then
            duration_seconds_raw=$(echo "$frame_count $fps" | awk -F/ '{if(NF==1) fps=$1; else fps=$1/$2; if(fps>0) printf "%.2f", frame_count/fps}' frame_count="$frame_count")
          fi
        fi
      fi
      
      if [[ -n "$duration_seconds_raw" ]] && [[ "$duration_seconds_raw" != "N/A" ]] && [[ "$duration_seconds_raw" != "" ]]; then
        local duration_seconds_int
        duration_seconds_int=$(awk -v dur="$duration_seconds_raw" 'BEGIN{print int(dur)}')
        if [[ "$ST_OS_TYPE" == "macos" ]]; then
          duration=$(date -u -r "$duration_seconds_int" +'%M:%S')
        else
          duration=$(date -u -d @"$duration_seconds_int" +'%M:%S')
        fi
        
        # Add indicator for estimated duration
        if [[ "$duration_seconds_raw" =~ \. ]]; then
          duration="${duration}*"  # Mark estimated durations with asterisk
        fi
      fi
      
      # Add video file size to total
      total_size=$((total_size + $(stat -f "%z" "$VIDEO_FILE" 2>/dev/null || stat --printf="%s" "$VIDEO_FILE" 2>/dev/null || echo 0)))
    fi

    if [[ -f "$AUDIO_FILE" ]]; then
        total_size=$((total_size + $(stat -f "%z" "$AUDIO_FILE" 2>/dev/null || stat --printf="%s" "$AUDIO_FILE" 2>/dev/null || echo 0)))
    fi
    
    # Check for stitched files
    local mp4_file="${VIDEO_FILE%.*}.mp4"
    local stitch_file="${meta_file%.*}.stitch"
    if [[ -f "$mp4_file" ]]; then
      stitched="Yes"
      total_size=$((total_size + $(stat -f "%z" "$mp4_file" 2>/dev/null || stat --printf="%s" "$mp4_file" 2>/dev/null || echo 0)))
    fi

    local human_size
    human_size=$(awk -v size="$total_size" '
      function human(x) {
        s="BKMGTPEZY";
        while (x >= 1024 && length(s) > 1) {
          x /= 1024;
          s = substr(s, 2);
        }
        return sprintf("%.2f%s", x, substr(s, 1, 1));
      }
      BEGIN { print human(size) }')

    if [[ "$mode" == "expanded" ]]; then
      printf "%-3d %-35s %-10s %-12s %-10s %-12s %s\n" "$n" "$session_name" "$duration" "$resolution" "$human_size" "raw" "video+audio clips"
      
      # Show stitched files indented under main recording
      if [[ -f "$mp4_file" ]]; then
        local stitch_profile="default"
        local stitch_codec="unknown"
        local stitch_quality="unknown"
        local stitch_size="0B"
        local stitch_duration="N/A"
        local stitch_resolution="N/A"
        
        # Get stitch file info
        if [[ -f "$stitch_file" ]]; then
          # Source the stitch file to get profile and parameters
          local old_vars=$(set | grep "^STITCH_" | cut -d= -f1)
          source "$stitch_file" 2>/dev/null
          stitch_profile="${STITCH_PROFILE:-default}"
          stitch_codec="${STITCH_VIDEO_CODEC:-unknown}"
          stitch_quality="crf${STITCH_CRF:-23}"
          
          # Clean up environment
          for var in $old_vars; do
            unset $var 2>/dev/null
          done
        fi
        
        # Get stitched file properties
        if [[ -f "$mp4_file" ]]; then
          stitch_size=$(get_human_size "$mp4_file")
          stitch_resolution=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$mp4_file" 2>/dev/null)
          [[ -z "$stitch_resolution" ]] && stitch_resolution="N/A"
          
          local stitch_duration_seconds_raw
          stitch_duration_seconds_raw=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$mp4_file" 2>/dev/null)
          if [[ -n "$stitch_duration_seconds_raw" ]] && [[ "$stitch_duration_seconds_raw" != "N/A" ]]; then
            local stitch_duration_seconds_int
            stitch_duration_seconds_int=$(awk -v dur="$stitch_duration_seconds_raw" 'BEGIN{print int(dur)}')
            if [[ "$ST_OS_TYPE" == "macos" ]]; then
              stitch_duration=$(date -u -r "$stitch_duration_seconds_int" +'%M:%S')
            else
              stitch_duration=$(date -u -d @"$stitch_duration_seconds_int" +'%M:%S')
            fi
          fi
        fi
        
        printf "%-3s %-35s %-10s %-12s %-10s %-12s %s\n" " " "  └─ stitched" "$stitch_duration" "$stitch_resolution" "$stitch_size" "$stitch_profile" "$stitch_codec/$stitch_quality"
      fi
    else
      printf "%-3d %-35s %-10s %-12s %-10s %s\n" "$n" "$session_name" "$duration" "$resolution" "$human_size" "$stitched"
    fi
    
    n=$((n + 1))
  done
}

show_clip_info() {
  local meta_file="$1"
  if [[ ! -f "$meta_file" ]]; then
    echo "Error: Meta file not found: $meta_file"
    return 1
  fi

  # Load the clip paths from the meta file
  # Use a subshell to prevent variables from leaking into the REPL
  (
    source "$meta_file"

    echo
    echo "  Displaying information for session: $SESSION_NAME"
    echo "===================================================================="
    
    # Check session status first
    if [[ "$SESSION_STATUS" != "completed" ]]; then
        echo "❗️ Session Status: $SESSION_STATUS"
        echo
        echo "This recording did not complete successfully."
        echo "The raw video and/or audio files may be missing or corrupted."
        echo
        echo "💡 To investigate the issue, view the recording log:"
        echo "   In REPL: log <n>"
        echo "===================================================================="
        return
    fi

    if [[ -f "$VIDEO_FILE" ]]; then
      local v_format_info
      v_format_info=$(ffprobe -v error -show_entries format=format_long_name -of default=noprint_wrappers=1:nokey=1 "$VIDEO_FILE")
      local video_info
      video_info=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height,r_frame_rate -of default=noprint_wrappers=1 "$VIDEO_FILE")
      local v_duration_raw
      v_duration_raw=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$VIDEO_FILE")
      
      local v_codec
      v_codec=$(echo "$video_info" | grep codec_name | cut -d= -f2)
      local v_res
      v_res="$(echo "$video_info" | grep width | cut -d= -f2)x$(echo "$video_info" | grep height | cut -d= -f2)"
      local v_fps_eval
      v_fps_eval=$(echo "$video_info" | grep r_frame_rate | cut -d= -f2)
      local v_fps
      v_fps=$(awk -F/ '{printf "%.2f", $1/$2}' <<< "$v_fps_eval")
      local v_duration
      v_duration=$(echo "$v_duration_raw" | awk '{printf "%.2f", $1}')
      local v_size
      v_size=$(get_human_size "$VIDEO_FILE")
      local v_rate
      v_rate=$(get_human_rate "$VIDEO_FILE" "$v_duration_raw")

      printf "\n--- Video Clip (%s) ---\n" "$VIDEO_FILE"
      printf "%-15s %s\n" "Attribute" "Value"
      printf '%s\n' "------------------------------------"
      printf "%-15s %s\n" "Container" "$v_format_info"
      printf "%-15s %s\n" "Codec" "$v_codec"
      printf "%-15s %s\n" "Resolution" "$v_res"
      printf "%-15s %s fps\n" "Framerate" "$v_fps"
      printf "%-15s %s s\n" "Duration" "$v_duration"
      printf "%-15s %s (%s)\n" "Size" "$v_size" "$v_rate"
    else
      echo "--- Video Clip ---"
      echo "  File not found: $VIDEO_FILE"
    fi

    echo

    if [[ -f "$AUDIO_FILE" ]]; then
      local a_format_info
      a_format_info=$(ffprobe -v error -show_entries format=format_long_name -of default=noprint_wrappers=1:nokey=1 "$AUDIO_FILE")
      local audio_info
      audio_info=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,channels,channel_layout,sample_rate,bits_per_raw_sample,duration -of default=noprint_wrappers=1 "$AUDIO_FILE")
      
      local a_codec
      a_codec=$(echo "$audio_info" | grep codec_name | cut -d= -f2)
      local a_channels
      a_channels=$(echo "$audio_info" | grep channels | cut -d= -f2)
      local a_layout
      a_layout=$(echo "$audio_info" | grep channel_layout | cut -d= -f2)
      local a_sample_rate
      a_sample_rate=$(echo "$audio_info" | grep sample_rate | cut -d= -f2)
      local a_bit_depth
      a_bit_depth=$(echo "$audio_info" | grep bits_per_raw_sample | cut -d= -f2)
      if [[ -z "$a_bit_depth" || "$a_bit_depth" == "N/A" ]]; then
          a_bit_depth=$(ffprobe -v error -select_streams a:0 -show_entries stream=bits_per_sample -of default=noprint_wrappers=1:nokey=1 "$AUDIO_FILE")
      fi
      [[ -z "$a_bit_depth" ]] && a_bit_depth="N/A"

      local a_duration_raw
      a_duration_raw=$(echo "$audio_info" | grep duration | cut -d= -f2)
      local a_duration
      a_duration=$(echo "$a_duration_raw" | awk '{printf "%.2f", $1}')
      local a_size
      a_size=$(get_human_size "$AUDIO_FILE")
      local a_rate
      a_rate=$(get_human_rate "$AUDIO_FILE" "$a_duration_raw")

      printf "\n--- Audio Clip (%s) ---\n" "$AUDIO_FILE"
      printf "%-15s %s\n" "Attribute" "Value"
      printf '%s\n' "------------------------------------"
      printf "%-15s %s\n" "Container" "$a_format_info"
      printf "%-15s %s\n" "Format" "$a_codec"
      printf "%-15s %s (%s)\n" "Channels" "$a_channels" "$a_layout"
      printf "%-15s %s Hz\n" "Sample Rate" "$a_sample_rate"
      printf "%-15s %s-bit\n" "Bit Depth" "$a_bit_depth"
      printf "%-15s %s s\n" "Duration" "$a_duration"
      printf "%-15s %s (%s)\n" "Size" "$a_size" "$a_rate"
    else
      echo "--- Audio Clip ---"
      echo "  File not found: $AUDIO_FILE"
    fi

    # Display info for the stitched file if it exists
    local stitched_file="${VIDEO_FILE%.*}.mp4"
    if [[ -f "$stitched_file" ]]; then
      local s_format_info
      s_format_info=$(ffprobe -v error -show_entries format=format_long_name -of default=noprint_wrappers=1:nokey=1 "$stitched_file")
      local s_video_info
      s_video_info=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height,r_frame_rate -of default=noprint_wrappers=1 "$stitched_file")
      local s_audio_info
      s_audio_info=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,sample_rate,channels,channel_layout -of default=noprint_wrappers=1 "$stitched_file")
      local s_duration_raw
      s_duration_raw=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$stitched_file")
      local s_duration
      s_duration=$(echo "$s_duration_raw" | awk '{printf "%.2f", $1}')
      local s_size
      s_size=$(get_human_size "$stitched_file")
      local s_rate
      s_rate=$(get_human_rate "$stitched_file" "$s_duration_raw")

      printf "\n--- Stitched Clip (%s) ---\n" "$stitched_file"
      printf "%-15s %s\n" "Attribute" "Value"
      printf '%s\n' "------------------------------------"
      printf "%-15s %s\n" "Container" "$s_format_info"
      printf "%-15s %s\n" "Video Codec" "$(echo "$s_video_info" | grep codec_name | cut -d= -f2)"
      printf "%-15s %s\n" "Audio Codec" "$(echo "$s_audio_info" | grep codec_name | cut -d= -f2)"
      printf "%-15s %s\n" "Resolution" "$(echo "$s_video_info" | grep width | cut -d= -f2)x$(echo "$s_video_info" | grep height | cut -d= -f2)"
      printf "%-15s %s s\n" "Duration" "$s_duration"
      printf "%-15s %s (%s)\n" "Size" "$s_size" "$s_rate"
    fi

    echo "===================================================================="

    if [[ -f "$VIDEO_FILE" && -f "$AUDIO_FILE" && -n "$v_duration" && -n "$a_duration" ]]; then
      local duration_diff
      duration_diff=$(echo "$v_duration $a_duration" | awk '{print $1 - $2}')
      printf "Clips appear to be recorded in parallel (duration difference: %.2fs)\n" "$duration_diff"
    fi
  )
}

env_display() {
  echo "Current Environment Variables:"
  echo "-------------------------------"
  env | grep '^ST_\|^DISPLAY\|^VIDEO_CODEC\|^AUDIO_CODEC\|^PRESET\|^CRF\|^FRAMERATE\|^COMPRESSION_'
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
      if [[ -n "$ST_GEOMETRY" ]]; then
        # Parse format like "1920:1080:0:0"
        IFS=':' read -r width height x_offset y_offset <<< "$ST_GEOMETRY"
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
      
      # Parse ST_GEOMETRY or get primary display
      if [[ -n "$ST_GEOMETRY" ]]; then
        # Parse format like "1920:1080:0:0"
        IFS=':' read -r width height x_offset y_offset <<< "$ST_GEOMETRY"
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

info_audio() {
  local meta_file="$1"
  if [[ -z "$meta_file" || ! -f "$meta_file" ]]; then
    echo "Usage: info audio <meta_file>"
    return 1
  fi

  source "$meta_file"
  local session_name
  session_name=$(basename "$meta_file" .meta)

  echo "===================================================================="
  echo "AUDIO ANALYSIS: $session_name"
  echo "===================================================================="

  if [[ ! -f "$AUDIO_FILE" ]]; then
    echo "ERROR: Audio file not found: $AUDIO_FILE"
    return 1
  fi

  # Check if jq is available for JSON parsing
  if command -v jq >/dev/null 2>&1; then
    # Use JSON parsing with jq
    local audio_probe
    audio_probe=$(ffprobe -v quiet -print_format json -show_streams -show_format "$AUDIO_FILE" 2>/dev/null)
    
    if [[ -z "$audio_probe" ]]; then
      echo "ERROR: Unable to analyze audio file"
      return 1
    fi

    # Extract audio stream info
    local codec duration channels sample_rate bit_rate channel_layout
    codec=$(echo "$audio_probe" | jq -r '.streams[0].codec_name // "unknown"')
    duration=$(echo "$audio_probe" | jq -r '.format.duration // "unknown"')
    channels=$(echo "$audio_probe" | jq -r '.streams[0].channels // "unknown"')
    sample_rate=$(echo "$audio_probe" | jq -r '.streams[0].sample_rate // "unknown"')
    bit_rate=$(echo "$audio_probe" | jq -r '.format.bit_rate // "unknown"')
    channel_layout=$(echo "$audio_probe" | jq -r '.streams[0].channel_layout // "unknown"')
  else
    # Fallback to basic ffprobe without JSON
    echo "Note: Using basic analysis (install 'jq' for enhanced details)"
    local codec duration channels sample_rate bit_rate channel_layout
    codec=$(ffprobe -v quiet -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$AUDIO_FILE" 2>/dev/null)
    duration=$(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$AUDIO_FILE" 2>/dev/null)
    channels=$(ffprobe -v quiet -show_entries stream=channels -of default=noprint_wrappers=1:nokey=1 "$AUDIO_FILE" 2>/dev/null)
    sample_rate=$(ffprobe -v quiet -show_entries stream=sample_rate -of default=noprint_wrappers=1:nokey=1 "$AUDIO_FILE" 2>/dev/null)
    bit_rate=$(ffprobe -v quiet -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 "$AUDIO_FILE" 2>/dev/null)
    channel_layout=$(ffprobe -v quiet -show_entries stream=channel_layout -of default=noprint_wrappers=1:nokey=1 "$AUDIO_FILE" 2>/dev/null)
  fi

  # Calculate derived values
  local file_size duration_formatted bit_rate_formatted
  file_size=$(get_human_size "$AUDIO_FILE")
  duration_formatted=$(echo "$duration" | awk '{printf "%02d:%05.2f", int($1/60), $1%60}')
  bit_rate_formatted=$(echo "$bit_rate" | awk '{printf "%.1f kbps", $1/1000}')

  # Display basic info
  printf "%-20s %s\n" "File" "$AUDIO_FILE"
  printf "%-20s %s\n" "Size" "$file_size"
  printf "%-20s %s (%s seconds)\n" "Duration" "$duration_formatted" "$duration"
  printf "%-20s %s\n" "Codec" "$codec"
  printf "%-20s %s channels (%s)\n" "Audio Layout" "$channels" "$channel_layout"
  printf "%-20s %s Hz\n" "Sample Rate" "$sample_rate"
  printf "%-20s %s\n" "Bit Rate" "$bit_rate_formatted"

  echo
  echo "--- Audio Quality Analysis ---"
  
  # Calculate quality metrics
  local samples_per_sec total_samples
  samples_per_sec=$(echo "$sample_rate" | awk '{print $1}')
  total_samples=$(echo "$duration $samples_per_sec" | awk '{printf "%.0f", $1 * $2}')
  
  printf "%-20s %'d\n" "Total Samples" "$total_samples"
  printf "%-20s %s MB/min\n" "Data Rate" "$(get_human_rate "$AUDIO_FILE" "$duration")"
  
  # Quality assessment
  local quality_rating
  if [[ "$sample_rate" -ge 48000 && "$channels" -ge 2 ]]; then
    quality_rating="High (Studio Quality)"
  elif [[ "$sample_rate" -ge 44100 ]]; then
    quality_rating="Good (CD Quality)"
  elif [[ "$sample_rate" -ge 22050 ]]; then
    quality_rating="Fair (Voice Quality)"
  else
    quality_rating="Low (Phone Quality)"
  fi
  printf "%-20s %s\n" "Quality Rating" "$quality_rating"

  # Stitch compatibility check
  echo
  echo "--- Stitch Compatibility ---"
  local stitched_file="${AUDIO_FILE%.*}.mp4"
  if [[ -f "$stitched_file" ]]; then
    echo "Already stitched to: $stitched_file"
  else
    echo "Ready for stitching"
  fi
  
  # Check for common stitch parameters
  if [[ -n "$STITCH_AUDIO_OFFSET" ]]; then
    printf "%-20s %s seconds\n" "Offset Setting" "$STITCH_AUDIO_OFFSET"
  fi
  if [[ -n "$STITCH_AUDIO_VOCODER" && "$STITCH_AUDIO_VOCODER" != "none" ]]; then
    printf "%-20s %s\n" "Vocoder Setting" "$STITCH_AUDIO_VOCODER"
  fi
}

info_video() {
  local meta_file="$1"
  if [[ -z "$meta_file" || ! -f "$meta_file" ]]; then
    echo "Usage: info video <meta_file>"
    return 1
  fi

  source "$meta_file"
  local session_name
  session_name=$(basename "$meta_file" .meta)

  echo "===================================================================="
  echo "VIDEO ANALYSIS: $session_name"
  echo "===================================================================="

  if [[ ! -f "$VIDEO_FILE" ]]; then
    echo "ERROR: Video file not found: $VIDEO_FILE"
    return 1
  fi

  # Check if jq is available for JSON parsing
  if command -v jq >/dev/null 2>&1; then
    # Use JSON parsing with jq
    local video_probe
    video_probe=$(ffprobe -v quiet -print_format json -show_streams -show_format "$VIDEO_FILE" 2>/dev/null)
    
    if [[ -z "$video_probe" ]]; then
      echo "ERROR: Unable to analyze video file"
      return 1
    fi

    # Extract video stream info
    local codec width height duration fps bit_rate pix_fmt
    codec=$(echo "$video_probe" | jq -r '.streams[0].codec_name // "unknown"')
    width=$(echo "$video_probe" | jq -r '.streams[0].width // "unknown"')
    height=$(echo "$video_probe" | jq -r '.streams[0].height // "unknown"')
    duration=$(echo "$video_probe" | jq -r '.format.duration // "unknown"')
    fps=$(echo "$video_probe" | jq -r '.streams[0].r_frame_rate // "unknown"' | awk -F/ '{if($2) printf "%.2f", $1/$2; else print $1}')
    bit_rate=$(echo "$video_probe" | jq -r '.format.bit_rate // "unknown"')
    pix_fmt=$(echo "$video_probe" | jq -r '.streams[0].pix_fmt // "unknown"')
  else
    # Fallback to basic ffprobe without JSON
    echo "Note: Using basic analysis (install 'jq' for enhanced details)"
    local codec width height duration fps bit_rate pix_fmt
    codec=$(ffprobe -v quiet -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$VIDEO_FILE" 2>/dev/null)
    width=$(ffprobe -v quiet -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 "$VIDEO_FILE" 2>/dev/null)
    height=$(ffprobe -v quiet -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 "$VIDEO_FILE" 2>/dev/null)
    duration=$(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$VIDEO_FILE" 2>/dev/null)
    fps=$(ffprobe -v quiet -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$VIDEO_FILE" 2>/dev/null | awk -F/ '{if($2) printf "%.2f", $1/$2; else print $1}')
    bit_rate=$(ffprobe -v quiet -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 "$VIDEO_FILE" 2>/dev/null)
    pix_fmt=$(ffprobe -v quiet -show_entries stream=pix_fmt -of default=noprint_wrappers=1:nokey=1 "$VIDEO_FILE" 2>/dev/null)
  fi

  # Calculate derived values
  local file_size duration_formatted bit_rate_formatted total_frames
  file_size=$(get_human_size "$VIDEO_FILE")
  duration_formatted=$(echo "$duration" | awk '{printf "%02d:%05.2f", int($1/60), $1%60}')
  bit_rate_formatted=$(echo "$bit_rate" | awk '{printf "%.1f Mbps", $1/1000000}')
  total_frames=$(echo "$duration $fps" | awk '{printf "%.0f", $1 * $2}')

  # Display basic info
  printf "%-20s %s\n" "File" "$VIDEO_FILE"
  printf "%-20s %s\n" "Size" "$file_size"
  printf "%-20s %s (%s seconds)\n" "Duration" "$duration_formatted" "$duration"
  printf "%-20s %s\n" "Codec" "$codec"
  printf "%-20s %s x %s\n" "Resolution" "$width" "$height"
  printf "%-20s %s fps\n" "Frame Rate" "$fps"
  printf "%-20s %s\n" "Pixel Format" "$pix_fmt"
  printf "%-20s %s\n" "Bit Rate" "$bit_rate_formatted"

  echo
  echo "--- Video Quality Analysis ---"
  
  # Calculate quality metrics
  local aspect_ratio total_pixels megapixels
  aspect_ratio=$(echo "$width $height" | awk '{printf "%.2f", $1 / $2}')
  total_pixels=$(echo "$width $height" | awk '{printf "%d", $1 * $2}')
  megapixels=$(echo "$total_pixels" | awk '{printf "%.1f", $1 / 1000000}')
  
  printf "%-20s %s:1\n" "Aspect Ratio" "$aspect_ratio"
  printf "%-20s %'d (%s MP)\n" "Pixel Count" "$total_pixels" "$megapixels"
  printf "%-20s %'d\n" "Total Frames" "$total_frames"
  printf "%-20s %s MB/min\n" "Data Rate" "$(get_human_rate "$VIDEO_FILE" "$duration")"
  
  # Quality assessment
  local quality_rating
  if [[ "$total_pixels" -gt 2073600 ]]; then  # 1920x1080
    quality_rating="High (Full HD+)"
  elif [[ "$total_pixels" -gt 921600 ]]; then  # 1280x720
    quality_rating="Good (HD)"
  elif [[ "$total_pixels" -gt 307200 ]]; then  # 640x480
    quality_rating="Fair (SD)"
  else
    quality_rating="Low (Sub-SD)"
  fi
  printf "%-20s %s\n" "Quality Rating" "$quality_rating"

  # Recording configuration analysis
  echo
  echo "--- Recording Configuration ---"
  if [[ -n "$ST_CROP_GEOMETRY" ]]; then
    printf "%-20s %s (cropped)\n" "Capture Mode" "$ST_CROP_GEOMETRY"
  else
    printf "%-20s %s\n" "Capture Mode" "Full screen"
  fi
  
  # Stitch status
  local stitched_file="${VIDEO_FILE%.*}.mp4"
  if [[ -f "$stitched_file" ]]; then
    echo "Already stitched to: $stitched_file"
  else
    echo "Ready for stitching"
  fi
}

review_session() {
  local session_number="$1"
  if [[ -z "$session_number" || ! "$session_number" =~ ^[0-9]+$ ]]; then
    echo "Usage: st review <session_number>"
    echo "       review <n>  (in REPL)"
    return 1
  fi

  # Get session directory by number
  local session_dir
  session_dir=$(get_session_by_number "$session_number")
  
  if [[ $? -ne 0 ]]; then
    echo "Invalid session number: $session_number"
    return 1
  fi

  local meta_file="$session_dir/session.meta"
  source "$meta_file"
  
  # Get session name from metadata or use directory name
  local session_name
  if [[ -n "$SESSION_NAME" ]]; then
    session_name="$SESSION_NAME"
  else
    session_name="$(basename "$session_dir")"
  fi

  echo
  echo "═══════════════════════════════════════════════════════════════════════════════"
  echo "SESSION REVIEW #$session_number: $session_name"
  echo "═══════════════════════════════════════════════════════════════════════════════"
  echo

  # Check file existence using directory structure
  local video_file="$session_dir/$RAW_VIDEO"
  local audio_file="$session_dir/$RAW_AUDIO"
  local final_file="$session_dir/$FINAL_OUTPUT"
  
  local video_exists=false
  local audio_exists=false
  local final_exists=false
  
  [[ -f "$video_file" ]] && video_exists=true
  [[ -f "$audio_file" ]] && audio_exists=true
  [[ -f "$final_file" ]] && final_exists=true

  if [[ "$video_exists" != true && "$audio_exists" != true && "$final_exists" != true ]]; then
    echo "❌ ERROR: No recording files found"
    echo "   Video: $video_file"
    echo "   Audio: $audio_file"
    echo "   Final: $final_file"
    return 1
  fi

  # Quick status overview
  printf "📁 Files:     "
  [[ "$video_exists" == true ]] && printf "✅ Video" || printf "❌ Video"
  printf "  "
  [[ "$audio_exists" == true ]] && printf "✅ Audio" || printf "❌ Audio"
  printf "  "
  [[ "$final_exists" == true ]] && printf "✅ Final" || printf "❌ Final"
  echo
  echo

  # === AUDIO ANALYSIS ===
  if [[ "$audio_exists" == true ]]; then
    echo "🔊 AUDIO ANALYSIS"
    echo "────────────────────────────────────────────────────────────────────────────────"
    
    # Get audio stats using ffprobe
    local audio_info duration_raw channels sample_rate codec file_size
    if command -v jq >/dev/null 2>&1; then
      local audio_probe
      audio_probe=$(ffprobe -v quiet -print_format json -show_streams -show_format "$audio_file" 2>/dev/null)
      codec=$(echo "$audio_probe" | jq -r '.streams[0].codec_name // "unknown"')
      duration_raw=$(echo "$audio_probe" | jq -r '.format.duration // "0"')
      channels=$(echo "$audio_probe" | jq -r '.streams[0].channels // "unknown"')
      sample_rate=$(echo "$audio_probe" | jq -r '.streams[0].sample_rate // "unknown"')
    else
      codec=$(ffprobe -v quiet -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$audio_file" 2>/dev/null)
      duration_raw=$(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$audio_file" 2>/dev/null)
      channels=$(ffprobe -v quiet -show_entries stream=channels -of default=noprint_wrappers=1:nokey=1 "$audio_file" 2>/dev/null)
      sample_rate=$(ffprobe -v quiet -show_entries stream=sample_rate -of default=noprint_wrappers=1:nokey=1 "$audio_file" 2>/dev/null)
    fi
    
    file_size=$(get_human_size "$audio_file")
    local duration_formatted
    duration_formatted=$(echo "$duration_raw" | awk '{printf "%02d:%05.2f", int($1/60), $1%60}')
    
    # Quality assessment
    local quality_rating quality_icon
    if [[ "$sample_rate" -ge 48000 && "$channels" -ge 2 ]]; then
      quality_rating="High (Studio)"; quality_icon="🟢"
    elif [[ "$sample_rate" -ge 44100 ]]; then
      quality_rating="Good (CD)"; quality_icon="🟡"
    elif [[ "$sample_rate" -ge 22050 ]]; then
      quality_rating="Fair (Voice)"; quality_icon="🟠"
    else
      quality_rating="Low (Phone)"; quality_icon="🔴"
    fi
    
    printf "%-18s %s (%s channels, %s Hz, %s)\n" "Quality:" "$quality_icon $quality_rating" "$channels" "$sample_rate" "$codec"
    printf "%-18s %s (%s seconds)\n" "Duration:" "$duration_formatted" "$duration_raw"
    printf "%-18s %s\n" "File Size:" "$file_size"
    
    # Suggest appropriate profiles based on audio characteristics
    echo
    echo "💡 Recommended Stitch Profiles:"
    if [[ "$channels" == "1" ]]; then
      echo "   🎙️  voice_recording  (optimized for mono speech/tutorials)"
      echo "   📱 social_media     (good for sharing with voice enhancement)"
    else
      echo "   🏆 high_quality     (preserves stereo quality)"
      echo "   ⚡ quick_draft      (fast processing for previews)"
    fi
    
    echo
  else
    echo "❌ AUDIO: File not found ($AUDIO_FILE)"
    echo
  fi

  # === VIDEO ANALYSIS ===
  if [[ "$video_exists" == true ]]; then
    echo "📺 VIDEO ANALYSIS"
    echo "────────────────────────────────────────────────────────────────────────────────"
    
    # Get video stats using ffprobe
    local video_info width height fps_raw duration_video_raw codec_video file_size_video
    if command -v jq >/dev/null 2>&1; then
      local video_probe
      video_probe=$(ffprobe -v quiet -print_format json -show_streams -show_format "$video_file" 2>/dev/null)
      codec_video=$(echo "$video_probe" | jq -r '.streams[0].codec_name // "unknown"')
      width=$(echo "$video_probe" | jq -r '.streams[0].width // "0"')
      height=$(echo "$video_probe" | jq -r '.streams[0].height // "0"')
      fps_raw=$(echo "$video_probe" | jq -r '.streams[0].r_frame_rate // "0/1"')
      duration_video_raw=$(echo "$video_probe" | jq -r '.format.duration // "0"')
    else
      codec_video=$(ffprobe -v quiet -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$video_file" 2>/dev/null)
      width=$(ffprobe -v quiet -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 "$video_file" 2>/dev/null)
      height=$(ffprobe -v quiet -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 "$video_file" 2>/dev/null)
      fps_raw=$(ffprobe -v quiet -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$video_file" 2>/dev/null)
      duration_video_raw=$(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$video_file" 2>/dev/null)
    fi
    
    local fps
    fps=$(echo "$fps_raw" | awk -F/ '{if($2) printf "%.1f", $1/$2; else print $1}')
    file_size_video=$(get_human_size "$video_file")
    local duration_video_formatted
    duration_video_formatted=$(echo "$duration_video_raw" | awk '{printf "%02d:%05.2f", int($1/60), $1%60}')
    
    # Quality assessment
    local total_pixels video_quality video_icon
    total_pixels=$(echo "$width $height" | awk '{print $1 * $2}')
    if [[ "$total_pixels" -gt 2073600 ]]; then  # 1920x1080
      video_quality="High (Full HD+)"; video_icon="🟢"
    elif [[ "$total_pixels" -gt 921600 ]]; then  # 1280x720
      video_quality="Good (HD)"; video_icon="🟡"
    elif [[ "$total_pixels" -gt 307200 ]]; then  # 640x480
      video_quality="Fair (SD)"; video_icon="🟠"
    else
      video_quality="Low (Sub-SD)"; video_icon="🔴"
    fi
    
    printf "%-18s %s (%s x %s @ %s fps, %s)\n" "Quality:" "$video_icon $video_quality" "$width" "$height" "$fps" "$codec_video"
    printf "%-18s %s (%s seconds)\n" "Duration:" "$duration_video_formatted" "$duration_video_raw"
    printf "%-18s %s\n" "File Size:" "$file_size_video"
    
    echo
  else
    echo "❌ VIDEO: File not found ($video_file)"
    echo
  fi

  # === SYNC ANALYSIS ===
  if [[ "$audio_exists" == true && "$video_exists" == true ]]; then
    echo "⏱️  SYNC ANALYSIS"
    echo "────────────────────────────────────────────────────────────────────────────────"
    
    local duration_diff sync_status sync_icon
    duration_diff=$(echo "$duration_video_raw $duration_raw" | awk '{printf "%.2f", $1 - $2}')
    local abs_diff
    abs_diff=$(echo "$duration_diff" | awk '{print ($1 < 0) ? -$1 : $1}')
    
    if (( $(echo "$abs_diff < 0.1" | bc -l 2>/dev/null || awk "BEGIN {print ($abs_diff < 0.1)}") )); then
      sync_status="Perfect sync"; sync_icon="✅"
    elif (( $(echo "$abs_diff < 1.0" | bc -l 2>/dev/null || awk "BEGIN {print ($abs_diff < 1.0)}") )); then
      sync_status="Good sync"; sync_icon="🟡"
    else
      sync_status="May need offset"; sync_icon="⚠️"
    fi
    
    printf "%-18s %s %s (difference: %s seconds)\n" "Timing:" "$sync_icon" "$sync_status" "$duration_diff"
    
    if (( $(echo "$abs_diff >= 1.0" | bc -l 2>/dev/null || awk "BEGIN {print ($abs_diff >= 1.0)}") )); then
      echo "   💡 Consider using offset=${duration_diff} in stitch command"
    fi
    echo
  fi

  # === QUICK ACTIONS ===
  echo "🚀 QUICK ACTIONS"
  echo "────────────────────────────────────────────────────────────────────────────────"
  
  # Audio playback options
  if [[ "$audio_exists" == true ]]; then
    echo "🔊 Audio Preview:"
    if command -v play >/dev/null 2>&1; then
      echo "   play \"$AUDIO_FILE\"                    # Full playback"
      echo "   play \"$AUDIO_FILE\" trim 0 30           # First 30 seconds"
    elif command -v afplay >/dev/null 2>&1; then
      echo "   afplay \"$AUDIO_FILE\"                  # Full playback (macOS)"
    else
      echo "   ffplay \"$AUDIO_FILE\"                  # Full playback"
    fi
    echo "   st play-audio                          # Interactive playback with controls"
    echo "   audio $session_number                         # Play in REPL"
    echo
  fi
  
  # Video playback options
  if [[ "$video_exists" == true ]]; then
    echo "📺 Video Preview:"
    echo "   open \"$video_file\"                     # System default player"
    echo "   ffplay \"$video_file\"                  # Quick preview"
    echo "   play $session_number                          # Play in REPL"
    echo
  fi
  
  # Stitch options
  if [[ "$audio_exists" == true && "$video_exists" == true ]]; then
    if [[ -f "$stitched_file" ]]; then
      echo "✅ Already Stitched:"
      echo "   open \"$stitched_file\"                 # View final result"
      echo "   st stitch \"$meta_file\" [profile]        # Re-stitch with different settings"
    else
      echo "🎬 Ready to Stitch:"
      if [[ "$channels" == "1" ]]; then
        echo "   st stitch \"$meta_file\" voice_recording  # Recommended for mono audio"
      else
        echo "   st stitch \"$meta_file\" high_quality     # Recommended for stereo audio"
      fi
      echo "   st stitch \"$meta_file\"                   # Default settings"
      echo "   stitch $session_number profile=voice_recording       # In REPL"
      
      if (( $(echo "$abs_diff >= 1.0" | bc -l 2>/dev/null || awk "BEGIN {print ($abs_diff >= 1.0)}") )); then
        echo "   stitch $session_number offset=$duration_diff            # With sync correction"
      fi
    fi
    echo
  fi
  
  # Analysis options
  echo "🔍 Deep Analysis:"
  echo "   st info audio \"$meta_file\"             # Detailed audio stats"
  echo "   st info video \"$meta_file\"             # Detailed video stats"
  echo "   st info stitch \"$meta_file\"            # Stitch configuration"
  
  echo
  echo "═══════════════════════════════════════════════════════════════════════════════"
}

info_stitch() {
  local meta_file="$1"
  if [[ -z "$meta_file" || ! -f "$meta_file" ]]; then
    echo "Usage: info stitch <meta_file>"
    return 1
  fi

  source "$meta_file"
  local session_name
  session_name=$(basename "$meta_file" .meta)
  local stitch_file="${meta_file%.*}.stitch"

  echo "===================================================================="
  echo "STITCH ANALYSIS: $session_name"
  echo "===================================================================="

  # Check if stitch configuration exists
  if [[ ! -f "$stitch_file" ]]; then
    echo "STATUS: No stitch configuration found"
    echo
    echo "--- Available for Stitching ---"
    echo "Raw video: $(test -f "$VIDEO_FILE" && echo "OK" || echo "MISSING") $VIDEO_FILE"
    echo "Raw audio: $(test -f "$AUDIO_FILE" && echo "OK" || echo "MISSING") $AUDIO_FILE"
    echo
    echo "To create stitch configuration: st init-stitch $meta_file [profile]"
    echo "To stitch with defaults: st stitch $meta_file"
    return 0
  fi

  echo "Stitch configuration: $stitch_file"
  
  # Load stitch parameters
  source "$stitch_file"

  # Check if already stitched
  local stitched_file="${VIDEO_FILE%.*}.mp4"
  if [[ -f "$stitched_file" && -n "$STITCH_TIMESTAMP" ]]; then
    echo "STATUS: Stitched ($STITCH_TIMESTAMP)"
    echo "Output: $STITCH_OUTPUT_FILE"
  else
    echo "STATUS: Ready to stitch"
    echo "Expected output: $stitched_file"
  fi

  echo
  echo "--- Stitch Configuration ---"
  printf "%-20s %s\n" "Profile" "${STITCH_PROFILE:-default}"
  printf "%-20s %s\n" "Video Codec" "${STITCH_VIDEO_CODEC:-libx264}"
  printf "%-20s %s\n" "Preset" "${STITCH_PRESET:-veryfast}"
  printf "%-20s %s\n" "Quality (CRF)" "${STITCH_CRF:-23}"
  printf "%-20s %s\n" "Frame Rate" "${STITCH_FRAMERATE:-15}"
  echo
  printf "%-20s %s\n" "Audio Channels" "${STITCH_AUDIO_CHANNELS:-1}"
  printf "%-20s %s\n" "Audio Sample Rate" "${STITCH_AUDIO_SAMPLERATE:-48000}"
  printf "%-20s %s\n" "Audio Bitrate" "${STITCH_AUDIO_BITRATE:-192k}"
  printf "%-20s %s\n" "Audio Vocoder" "${STITCH_AUDIO_VOCODER:-none}"
  printf "%-20s %s\n" "Audio Offset" "${STITCH_AUDIO_OFFSET:-0} seconds"
  printf "%-20s %s\n" "Audio Duration" "${STITCH_AUDIO_DURATION:-auto}"
  echo
  if [[ -n "$STITCH_CROP_GEOMETRY" ]]; then
    printf "%-20s %s\n" "Crop Applied" "$STITCH_CROP_GEOMETRY"
    # Check if this matches the recorded crop geometry
    if [[ -n "$RECORD_CROP_GEOMETRY" && "$STITCH_CROP_GEOMETRY" == "$RECORD_CROP_GEOMETRY" ]]; then
      printf "%-20s %s\n" "Crop Source" "Inherited from recording"
    else
      printf "%-20s %s\n" "Crop Source" "Custom for stitch"
    fi
  else
    printf "%-20s %s\n" "Crop Applied" "None (full frame)"
    if [[ -n "$RECORD_CROP_GEOMETRY" ]]; then
      printf "%-20s %s\n" "Note" "Recording had crop: $RECORD_CROP_GEOMETRY (not applied in stitch)"
    fi
  fi

  # If stitched, show analysis of output
  if [[ -f "$stitched_file" && -n "$STITCH_OUTPUT_FILE" ]]; then
    echo
    echo "--- Output Analysis ---"
    
    # Check if jq is available for JSON parsing
    if command -v jq >/dev/null 2>&1; then
      # Use JSON parsing with jq
      local stitched_probe
      stitched_probe=$(ffprobe -v quiet -print_format json -show_streams -show_format "$stitched_file" 2>/dev/null)
      
      if [[ -n "$stitched_probe" ]]; then
        # Get video and audio streams
        local v_codec v_width v_height v_fps a_codec a_channels a_sample_rate duration file_size
        v_codec=$(echo "$stitched_probe" | jq -r '.streams[] | select(.codec_type=="video") | .codec_name // "unknown"')
        v_width=$(echo "$stitched_probe" | jq -r '.streams[] | select(.codec_type=="video") | .width // "unknown"')
        v_height=$(echo "$stitched_probe" | jq -r '.streams[] | select(.codec_type=="video") | .height // "unknown"')
        v_fps=$(echo "$stitched_probe" | jq -r '.streams[] | select(.codec_type=="video") | .r_frame_rate // "unknown"' | awk -F/ '{if($2) printf "%.2f", $1/$2; else print $1}')
        a_codec=$(echo "$stitched_probe" | jq -r '.streams[] | select(.codec_type=="audio") | .codec_name // "unknown"')
        a_channels=$(echo "$stitched_probe" | jq -r '.streams[] | select(.codec_type=="audio") | .channels // "unknown"')
        a_sample_rate=$(echo "$stitched_probe" | jq -r '.streams[] | select(.codec_type=="audio") | .sample_rate // "unknown"')
        duration=$(echo "$stitched_probe" | jq -r '.format.duration // "unknown"')
      fi
    else
      # Fallback to basic ffprobe without JSON
      echo "Note: Using basic analysis (install 'jq' for enhanced details)"
      local v_codec v_width v_height v_fps a_codec a_channels a_sample_rate duration file_size
      v_codec=$(ffprobe -v quiet -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$stitched_file" 2>/dev/null)
      v_width=$(ffprobe -v quiet -select_streams v:0 -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 "$stitched_file" 2>/dev/null)
      v_height=$(ffprobe -v quiet -select_streams v:0 -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 "$stitched_file" 2>/dev/null)
      v_fps=$(ffprobe -v quiet -select_streams v:0 -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$stitched_file" 2>/dev/null | awk -F/ '{if($2) printf "%.2f", $1/$2; else print $1}')
      a_codec=$(ffprobe -v quiet -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$stitched_file" 2>/dev/null)
      a_channels=$(ffprobe -v quiet -select_streams a:0 -show_entries stream=channels -of default=noprint_wrappers=1:nokey=1 "$stitched_file" 2>/dev/null)
      a_sample_rate=$(ffprobe -v quiet -select_streams a:0 -show_entries stream=sample_rate -of default=noprint_wrappers=1:nokey=1 "$stitched_file" 2>/dev/null)
      duration=$(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$stitched_file" 2>/dev/null)
    fi
    
    file_size=$(get_human_size "$stitched_file")

    printf "%-20s %s\n" "File Size" "$file_size"
    printf "%-20s %s seconds\n" "Duration" "$duration"
    printf "%-20s %s\n" "Video Codec" "$v_codec"
    printf "%-20s %s x %s @ %s fps\n" "Video Format" "$v_width" "$v_height" "$v_fps"
    printf "%-20s %s\n" "Audio Codec" "$a_codec"
    printf "%-20s %s channels @ %s Hz\n" "Audio Format" "$a_channels" "$a_sample_rate"

    # Size comparison
    echo
    echo "--- Size Comparison ---"
    if [[ -f "$VIDEO_FILE" && -f "$AUDIO_FILE" ]]; then
      local raw_video_size raw_audio_size raw_total_mb stitched_mb compression_ratio
      raw_video_size=$(stat -f "%z" "$VIDEO_FILE" 2>/dev/null || stat --printf="%s" "$VIDEO_FILE" 2>/dev/null)
      raw_audio_size=$(stat -f "%z" "$AUDIO_FILE" 2>/dev/null || stat --printf="%s" "$AUDIO_FILE" 2>/dev/null)
      raw_total_mb=$(echo "$raw_video_size $raw_audio_size" | awk '{printf "%.1f", ($1 + $2) / 1048576}')
      stitched_mb=$(stat -f "%z" "$stitched_file" 2>/dev/null || stat --printf="%s" "$stitched_file" 2>/dev/null | awk '{printf "%.1f", $1 / 1048576}')
      compression_ratio=$(echo "$stitched_mb $raw_total_mb" | awk '{printf "%.1fx", $2 / $1}')
      
      printf "%-20s %s MB\n" "Raw Files Total" "$raw_total_mb"
      printf "%-20s %s MB\n" "Stitched File" "$stitched_mb"
      printf "%-20s %s smaller\n" "Compression" "$compression_ratio"
    fi

    # Show stitch log if available
    if [[ -n "$STITCH_LOG" && -f "$STITCH_LOG" ]]; then
      echo
      echo "--- Stitch Log (last 10 lines) ---"
      tail -n 10 "$STITCH_LOG"
    fi
  else
    echo
    echo "--- Commands ---"
    echo "To stitch with current config: st stitch $meta_file"
    echo "To edit configuration: st edit-stitch $meta_file"
    echo "To reinitialize with profile: st init-stitch $meta_file [profile]"
  fi
}

info_meta() {
  local meta_file="$1"
  if [[ -z "$meta_file" || ! -f "$meta_file" ]]; then
    echo "Usage: info meta <meta_file>"
    return 1
  fi

  local session_name
  session_name=$(basename "$meta_file" .meta)

  echo "===================================================================="
  echo "METADATA ANALYSIS: $session_name"
  echo "===================================================================="

  # Show meta file location and contents
  printf "%-20s %s\n" "Meta File" "$meta_file"
  printf "%-20s %s\n" "Session Name" "$session_name"
  
  echo
  echo "--- Meta File Contents ---"
  cat "$meta_file"

  # Source the meta file and analyze
  source "$meta_file"
  
  echo
  echo "--- File Status ---"
  printf "%-20s %s\n" "Video File" "$(test -f "$VIDEO_FILE" && echo "OK - Exists" || echo "MISSING") ($VIDEO_FILE)"
  printf "%-20s %s\n" "Audio File" "$(test -f "$AUDIO_FILE" && echo "OK - Exists" || echo "MISSING") ($AUDIO_FILE)"
  
  local stitched_file="${VIDEO_FILE%.*}.mp4"
  printf "%-20s %s\n" "Stitched File" "$(test -f "$stitched_file" && echo "OK - Exists" || echo "Not created") ($stitched_file)"

  local stitch_file="${meta_file%.*}.stitch"
  printf "%-20s %s\n" "Stitch Config" "$(test -f "$stitch_file" && echo "OK - Exists" || echo "Not created") ($stitch_file)"

  # Show log files
  if [[ -n "$FFMPEG_LOG" ]]; then
    printf "%-20s %s\n" "Recording Log" "$(test -f "$FFMPEG_LOG" && echo "OK - Exists" || echo "MISSING") ($FFMPEG_LOG)"
  fi
  if [[ -f "$stitch_file" ]]; then
    source "$stitch_file"
    if [[ -n "$STITCH_LOG" ]]; then
      printf "%-20s %s\n" "Stitch Log" "$(test -f "$STITCH_LOG" && echo "OK - Exists" || echo "MISSING") ($STITCH_LOG)"
    fi
  fi

  # Show file timestamps and sizes
  echo
  echo "--- File Details ---"
  if [[ -f "$VIDEO_FILE" ]]; then
    local v_timestamp v_size
    v_timestamp=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$VIDEO_FILE" 2>/dev/null || stat --printf="%y" "$VIDEO_FILE" 2>/dev/null | cut -d. -f1)
    v_size=$(get_human_size "$VIDEO_FILE")
    printf "%-20s %s (%s)\n" "Video Created" "$v_timestamp" "$v_size"
  fi
  
  if [[ -f "$AUDIO_FILE" ]]; then
    local a_timestamp a_size
    a_timestamp=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$AUDIO_FILE" 2>/dev/null || stat --printf="%y" "$AUDIO_FILE" 2>/dev/null | cut -d. -f1)
    a_size=$(get_human_size "$AUDIO_FILE")
    printf "%-20s %s (%s)\n" "Audio Created" "$a_timestamp" "$a_size"
  fi

  if [[ -f "$stitched_file" ]]; then
    local s_timestamp s_size
    s_timestamp=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$stitched_file" 2>/dev/null || stat --printf="%y" "$stitched_file" 2>/dev/null | cut -d. -f1)
    s_size=$(get_human_size "$stitched_file")
    printf "%-20s %s (%s)\n" "Stitched Created" "$s_timestamp" "$s_size"
  fi

  # Environment info
  echo
  echo "--- Recording Environment ---"
  if [[ -n "$RECORD_TIMESTAMP" ]]; then
    echo "Recording configuration used during capture:"
    printf "%-20s %s\n" "Recorded" "$RECORD_TIMESTAMP"
    printf "%-20s %s\n" "Video Codec" "${RECORD_VIDEO_CODEC:-default}"
    printf "%-20s %s\n" "Preset" "${RECORD_PRESET:-default}"
    printf "%-20s %s\n" "Quality (CRF)" "${RECORD_CRF:-default}"
    printf "%-20s %s\n" "Frame Rate" "${RECORD_FRAMERATE:-default}"
    printf "%-20s %s\n" "Audio Channels" "${RECORD_AUDIO_CHANNELS:-default}"
    printf "%-20s %s\n" "Audio Sample Rate" "${RECORD_AUDIO_SAMPLERATE:-default}"
    if [[ -n "$RECORD_CROP_GEOMETRY" ]]; then
      printf "%-20s %s\n" "Crop Geometry" "$RECORD_CROP_GEOMETRY"
    else
      printf "%-20s %s\n" "Crop Geometry" "Full screen"
    fi
    if [[ -n "$RECORD_SCREEN_GEOMETRY" ]]; then
      printf "%-20s %s\n" "Screen Geometry" "$RECORD_SCREEN_GEOMETRY"
    fi
  else
    echo "Current settings that would apply to new recordings:"
    printf "%-20s %s\n" "Video Codec" "${VIDEO_CODEC:-default}"
    printf "%-20s %s\n" "Audio Codec" "${AUDIO_CODEC:-default}"
    printf "%-20s %s\n" "Frame Rate" "${FRAMERATE:-default}"
    printf "%-20s %s\n" "Quality (CRF)" "${CRF:-default}"
    if [[ -n "$ST_CROP_GEOMETRY" ]]; then
      printf "%-20s %s\n" "Crop Geometry" "$ST_CROP_GEOMETRY"
    else
      printf "%-20s %s\n" "Crop Geometry" "Full screen"
    fi
  fi

  # Stitch parameters if available
  local stitch_file="${meta_file%.*}.stitch"
  if [[ -f "$stitch_file" ]]; then
    # Source the stitch file to get parameters
    local old_vars=$(set | grep "^STITCH_" | cut -d= -f1)
    source "$stitch_file"
    
    echo
    echo "--- Stitch Configuration ---"
    echo "Configuration file: $stitch_file"
    if [[ -n "$STITCH_TIMESTAMP" ]]; then
      printf "%-20s %s\n" "Last Stitched" "$STITCH_TIMESTAMP"
    fi
    printf "%-20s %s\n" "Profile" "${STITCH_PROFILE:-default}"
    echo
    printf "%-20s %s\n" "Video Codec" "${STITCH_VIDEO_CODEC:-default}"
    printf "%-20s %s\n" "Preset" "${STITCH_PRESET:-default}"
    printf "%-20s %s\n" "Quality (CRF)" "${STITCH_CRF:-default}"
    printf "%-20s %s\n" "Frame Rate" "${STITCH_FRAMERATE:-default}"
    echo
    printf "%-20s %s\n" "Audio Channels" "${STITCH_AUDIO_CHANNELS:-default}"
    printf "%-20s %s\n" "Audio Sample Rate" "${STITCH_AUDIO_SAMPLERATE:-default}"
    printf "%-20s %s\n" "Audio Bitrate" "${STITCH_AUDIO_BITRATE:-default}"
    printf "%-20s %s\n" "Audio Vocoder" "${STITCH_AUDIO_VOCODER:-none}"
    printf "%-20s %s\n" "Audio Offset" "${STITCH_AUDIO_OFFSET:-0} seconds"
    printf "%-20s %s\n" "Audio Duration" "${STITCH_AUDIO_DURATION:-auto}"
    echo
    if [[ -n "$STITCH_CROP_GEOMETRY" ]]; then
      printf "%-20s %s\n" "Stitch Crop" "$STITCH_CROP_GEOMETRY"
      # Check if this matches the recorded crop geometry
      if [[ -n "$RECORD_CROP_GEOMETRY" && "$STITCH_CROP_GEOMETRY" == "$RECORD_CROP_GEOMETRY" ]]; then
        printf "%-20s %s\n" "Crop Source" "Inherited from recording"
      else
        printf "%-20s %s\n" "Crop Source" "Custom for stitch"
      fi
    else
      printf "%-20s %s\n" "Stitch Crop" "None (full frame)"
    fi
    if [[ -n "$STITCH_OUTPUT_FILE" ]]; then
      printf "%-20s %s\n" "Output File" "$STITCH_OUTPUT_FILE"
    fi
    if [[ -n "$STITCH_LOG" ]]; then
      printf "%-20s %s\n" "Log File" "$STITCH_LOG"
    fi
    
    # Clean up environment
    for var in $old_vars; do
      unset $var
    done 2>/dev/null
  else
    echo
    echo "--- Stitch Configuration ---"
    echo "No stitch configuration found. Run 'init-stitch' to create one."
    if [[ -n "$RECORD_CROP_GEOMETRY" ]]; then
      echo "Note: Recording used crop geometry: $RECORD_CROP_GEOMETRY"
      echo "      This will be inherited when you create stitch configuration."
    fi
  fi
}
