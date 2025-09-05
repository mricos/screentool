#!/usr/bin/env bash
# screentool_probe.sh
# Clean, filtered media file probing without configuration noise

screentool_probe() {
  local file="$1"
  local format="${2:-summary}"  # summary, json, or raw
  
  if [[ ! -f "$file" ]]; then
    echo "File not found: $file"
    return 1
  fi
  
  case "$format" in
    summary)
      probe_summary "$file"
      ;;
    json)
      probe_json "$file"
      ;;
    raw)
      probe_raw "$file"
      ;;
    *)
      echo "Usage: screentool_probe <file> [summary|json|raw]"
      return 1
      ;;
  esac
}

probe_summary() {
  local file="$1"
  
  # Get clean probe data
  local probe_data
  probe_data=$(ffprobe -v quiet -print_format json -show_format -show_streams "$file" 2>/dev/null)
  
  if [[ -z "$probe_data" ]]; then
    echo "Could not analyze file: $file"
    return 1
  fi
  
  # Extract key information using jq
  if command -v jq >/dev/null; then
    local duration size_mb width height fps video_codec audio_codec bitrate
    
    # Format info
    duration=$(echo "$probe_data" | jq -r '.format.duration // "unknown"')
    local size_bytes=$(echo "$probe_data" | jq -r '.format.size // 0')
    size_mb=$(echo "$size_bytes" | awk '{printf "%.1f", $1/1024/1024}')
    bitrate=$(echo "$probe_data" | jq -r '.format.bit_rate // 0' | awk '{printf "%.0f", $1/1000}')
    
    # Video stream info
    width=$(echo "$probe_data" | jq -r '.streams[] | select(.codec_type=="video") | .width // 0' | head -1)
    height=$(echo "$probe_data" | jq -r '.streams[] | select(.codec_type=="video") | .height // 0' | head -1)
    fps=$(echo "$probe_data" | jq -r '.streams[] | select(.codec_type=="video") | .r_frame_rate // "0/1"' | head -1 | awk -F'/' '{if($2>0) printf "%.1f", $1/$2; else print "0"}')
    video_codec=$(echo "$probe_data" | jq -r '.streams[] | select(.codec_type=="video") | .codec_name // "none"' | head -1)
    
    # Audio stream info
    audio_codec=$(echo "$probe_data" | jq -r '.streams[] | select(.codec_type=="audio") | .codec_name // "none"' | head -1)
    local audio_channels=$(echo "$probe_data" | jq -r '.streams[] | select(.codec_type=="audio") | .channels // 0' | head -1)
    local audio_rate=$(echo "$probe_data" | jq -r '.streams[] | select(.codec_type=="audio") | .sample_rate // 0' | head -1)
    local audio_bitrate=$(echo "$probe_data" | jq -r '.streams[] | select(.codec_type=="audio") | .bit_rate // 0' | head -1)
    local audio_layout=$(echo "$probe_data" | jq -r '.streams[] | select(.codec_type=="audio") | .channel_layout // "unknown"' | head -1)
    
    # Format duration nicely
    if [[ "$duration" =~ ^[0-9]+\.?[0-9]*$ ]]; then
      duration=$(printf "%.1fs" "$duration")
    fi
    
    # Clean output
    echo "File: $(basename "$file")"
    echo "Size: ${size_mb}MB"
    echo "Duration: $duration"
    echo "Video: ${width}x${height} @ ${fps}fps ($video_codec)"
    if [[ "$audio_codec" != "none" ]] && [[ "$audio_channels" != "0" ]] && [[ "$audio_rate" != "0" ]]; then
      local audio_bitrate_kb=""
      if [[ "$audio_bitrate" != "0" ]]; then
        audio_bitrate_kb=" @ $(echo "$audio_bitrate" | awk '{printf "%.0fkbps", $1/1000}')"
      fi
      echo "Audio: ${audio_channels}ch ${audio_rate}Hz ($audio_codec$audio_bitrate_kb)"
      if [[ "$audio_layout" != "unknown" ]] && [[ "$audio_layout" != "" ]]; then
        echo "Audio Layout: $audio_layout"
      fi
    else
      echo "Audio: No audio stream detected"
    fi
    echo "Bitrate: ${bitrate}kbps"
    
  else
    echo "jq not available - install for detailed analysis"
    echo "File: $(basename "$file")"
    local file_size
    file_size=$(stat -f "%z" "$file" 2>/dev/null || stat --printf="%s" "$file" 2>/dev/null)
    if [[ -n "$file_size" ]]; then
      file_size=$(echo "$file_size" | awk '{printf "%.1fMB", $1/1024/1024}')
      echo "Size: $file_size"
    fi
  fi
}

probe_json() {
  local file="$1"
  
  # Return clean JSON without ffmpeg configuration noise
  ffprobe -v quiet -print_format json -show_format -show_streams "$file" 2>/dev/null
}

probe_raw() {
  local file="$1"
  
  # Raw ffprobe output with minimal noise
  ffprobe -v error -show_format -show_streams "$file" 2>/dev/null
}

# Get current screen resolution (what user actually sees)
get_current_screen_resolution() {
  case "$ST_OS_TYPE" in
    macos)
      # Try multiple methods to get actual current resolution
      
      # Method 1: Get desktop bounds (actual current resolution)
      local bounds
      bounds=$(osascript -e 'tell application "Finder" to get bounds of window of desktop' 2>/dev/null)
      
      if [[ -n "$bounds" ]]; then
        local width height
        width=$(echo "$bounds" | awk -F', ' '{print $3}')
        height=$(echo "$bounds" | awk -F', ' '{print $4}')
        echo "${width}x${height}"
        return 0
      fi
      
      # Method 2: Parse system_profiler for "UI Looks like"
      local ui_res
      ui_res=$(system_profiler SPDisplaysDataType | grep "UI Looks like:" | head -1 | awk -F': ' '{print $2}' | awk '{print $1 "x" $3}')
      
      if [[ -n "$ui_res" ]]; then
        echo "$ui_res"
        return 0
      fi
      
      # Method 3: Fallback to main display resolution
      local main_res
      main_res=$(system_profiler SPDisplaysDataType | grep "Resolution:" | head -1 | sed 's/.*Resolution: //' | sed 's/ Retina//')
      if [[ -n "$main_res" ]]; then
        local width height
        width=$(echo "$main_res" | awk '{print $1}')
        height=$(echo "$main_res" | awk '{print $3}')
        echo "${width}x${height}"
        return 0
      fi
      
      echo "unknown"
      ;;
    linux)
      # Use xrandr to get current resolution
      xrandr | grep '\*' | awk '{print $1}' | head -1
      ;;
    *)
      echo "unknown"
      ;;
  esac
}
