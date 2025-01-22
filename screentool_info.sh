# Display usage information
usage() {
  echo "Usage: $0 {record|list|info <file>|summary <file>|json <file>|input|output|select|save|load|env}"
  echo ""
  echo "Commands:"
  echo "  record             Start screen recording (Ctrl-C to stop)."
  echo "  list               List recordings with their properties."
  echo "  summary <file>     Show a brief summary of the video file."
  echo "  json <file>        Show detailed JSON metadata of the video file."
  echo "  info <file>        Show human-readable info for the given file."
  echo "  input              Show available audio input devices."
  echo "  output             Show available audio output devices."
  echo "  select             Select audio input and output devices."
  echo "  save               Save environment to ST_DIR/screentool.env."
  echo "  load               Load environment to ST_DIR/screentool.env."
  echo "  env                Show all environment variables being used."
  exit 0
}

# Parse time format to seconds
parse_time() {
    local time="$1"
    local seconds=0
    
    # Handle HhMmSs.ms format (e.g., 3h2m3s13ms or 2m30s)
    if [[ $time =~ ([0-9]+h)?([0-9]+m)?([0-9]+s)?([0-9]+ms)? ]]; then
        [[ $time =~ ([0-9]+)h ]] && seconds=$((seconds + ${BASH_REMATCH[1]} * 3600))
        [[ $time =~ ([0-9]+)m ]] && seconds=$((seconds + ${BASH_REMATCH[1]} * 60))
        [[ $time =~ ([0-9]+)s ]] && seconds=$((seconds + ${BASH_REMATCH[1]}))
        [[ $time =~ ([0-9]+)ms ]] && seconds=$(bc <<< "scale=3; $seconds + ${BASH_REMATCH[1]}/1000")
    # Handle MM:SS format
    elif [[ $time =~ ^[0-9]+:[0-9]+$ ]]; then
        local min=${time%:*}
        local sec=${time#*:}
        seconds=$(( min * 60 + sec ))
    # Handle HH:MM:SS format
    elif [[ $time =~ ^[0-9]+:[0-9]+:[0-9]+$ ]]; then
        IFS=: read -r h m s <<< "$time"
        seconds=$(( h * 3600 + m * 60 + s ))
    # Handle raw seconds
    elif [[ $time =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        seconds=$time
    fi
    echo "$seconds"
}

# Format seconds to human readable time
format_time() {
    local seconds="$1"
    local format="${2:-human}" # human, colon, or short
    
    case $format in
        human)
            local h=$((seconds/3600))
            local m=$(((seconds%3600)/60))
            local s=$((seconds%60))
            local ms=$(echo "scale=3; $seconds - ($h*3600 + $m*60 + $s)" | bc | sed 's/0\+$//')
            local result=""
            [[ $h -gt 0 ]] && result+="${h}h"
            [[ $m -gt 0 ]] && result+="${m}m"
            [[ $s -gt 0 ]] && result+="${s}s"
            [[ $ms != "0" && $ms != "" ]] && result+="${ms#.}ms"
            echo "$result"
            ;;
        colon)
            printf "%02d:%02d:%02d" $((seconds/3600)) $((seconds%3600/60)) $((seconds%60))
            ;;
        short)
            printf "%.3fs" "$seconds"
            ;;
    esac
}

# List recordings with their properties
list_recordings() {
    local dir="${1:-$ST_DIR}"
    local clips_file="$ST_DIR/clips.txt"
    
    # Print header
    printf "%-3s %-30s %-10s %-12s %s\n" "n" "name" "len" "res" "clips"
    echo "------------------------------------------------------------------------"
    
    # Load clip points if file exists
    declare -A markers
    if [ -f "$clips_file" ]; then
        while IFS=':' read -r file start duration label || [ -n "$file" ]; do
            # Skip empty lines and comments
            [[ -z "$file" || "$file" =~ ^[[:space:]]*# ]] && continue
            # Format times in human-readable format
            local start_fmt=$(format_time "$start")
            local duration_fmt=$(format_time "$duration")
            # Append to existing markers or create new entry
            if [ -n "${markers[$file]}" ]; then
                markers[$file]="${markers[$file]}, $label($start_fmt+$duration_fmt)"
            else
                markers[$file]="$label($start_fmt+$duration_fmt)"
            fi
        done < "$clips_file"
    fi
    
    # Process each MP4 file
    local n=1
    find "$dir" -maxdepth 1 -name "*.mp4" -type f | sort | while read -r file; do
        # Get basic file info
        local filename=$(basename "$file")
        
        # Get video info using ffprobe
        local info
        info=$(ffprobe -v quiet -print_format json -show_format -show_streams "$file")
        
        # Extract duration and round to nearest second
        local duration
        duration=$(echo "$info" | jq -r '.format.duration // empty' | awk '{printf "%d:%02d", $1/60, $1%60}')
        
        # Extract resolution from first video stream
        local resolution=""
        local width height
        width=$(echo "$info" | jq -r '.streams[] | select(.codec_type=="video") | .width // empty' | head -n1)
        height=$(echo "$info" | jq -r '.streams[] | select(.codec_type=="video") | .height // empty' | head -n1)
        if [ -n "$width" ] && [ -n "$height" ]; then
            resolution="${width}x${height}"
        fi
        
        # Get markers if any
        local marker_list="${markers[$filename]:-}"
        
        # Print formatted line
        printf "%-3d %-30s %-10s %-12s %s\n" \
            "$n" "$filename" "${duration:--}" "${resolution:--}" "$marker_list"
        
        n=$((n + 1))
    done
}

# Add clip point to a recording
add_marker() {
    local file="$1"
    local start="$2"
    local duration="$3"
    local label="$4"
    local clips_file="$ST_DIR/clips.txt"
    
    # Ensure file exists and is in ST_DIR
    if [ ! -f "$ST_DIR/$file" ]; then
        echo "Error: File $file not found in $ST_DIR"
        return 1
    fi
    
    # Convert start and duration to seconds
    local start_sec=$(parse_time "$start")
    local duration_sec=$(parse_time "$duration")
    
    # Create clips file if it doesn't exist
    if [ ! -f "$clips_file" ]; then
        echo "# Clip points for screentool recordings" > "$clips_file"
        echo "# Format: filename:start:duration:label" >> "$clips_file"
        echo "# Times can be in any of these formats:" >> "$clips_file"
        echo "#   - Human readable: 1h2m3s500ms" >> "$clips_file"
        echo "#   - Colon format: 01:02:03" >> "$clips_file"
        echo "#   - Raw seconds: 3600.500" >> "$clips_file"
        echo "" >> "$clips_file"
    fi
    
    # Add new clip point
    echo "$file:$start_sec:$duration_sec:$label" >> "$clips_file"
    echo "Added clip point '$label' to $file ($(format_time "$start_sec") for $(format_time "$duration_sec"))"
}

# Remove clip point from a recording
remove_marker() {
    local file="$1"
    local label="$2"
    local clips_file="$ST_DIR/clips.txt"
    local temp_file="$ST_DIR/clips.tmp"
    
    # Ensure clips file exists
    if [ ! -f "$clips_file" ]; then
        echo "Error: No clips file found"
        return 1
    fi
    
    # Remove clip point, preserving comments and empty lines
    awk -F: -v file="$file" -v label="$label" '
        $0 ~ /^[[:space:]]*#/ { print; next }  # Preserve comments
        /^[[:space:]]*$/ { print; next }       # Preserve empty lines
        $1 == file && $4 == label { next }     # Skip matching clip point
        { print }                              # Print everything else
    ' "$clips_file" > "$temp_file"
    
    # Replace original file
    mv "$temp_file" "$clips_file"
    echo "Removed clip point '$label' from $file"
}

# Generate JSON metadata for the video file
json_metadata() {
  [ -z "$1" ] && { echo "Error: Please specify a file."; exit 1; }
  
  if [ ! -f "$1" ]; then
    echo "Error: File not found."
    exit 1
  fi
  
  ffprobe -hide_banner -v quiet -print_format json -show_format -show_streams "$1" | jq .
}

# Generate a summary of the video file using ffmpeg JSON output and jq
summary() {
  [ -z "$1" ] && { echo "Error: Please specify a file."; exit 1; }
  
  if [ ! -f "$1" ]; then
    echo "Error: File not found."
    exit 1
  fi

  INFO=$(ffprobe -hide_banner -v quiet -print_format json -show_format -show_streams "$1")
  
  DURATION=$(echo "$INFO" | jq -r '.format.duration | tonumber | floor')
  SIZE=$(echo "$INFO" | jq -r '.format.size | tonumber / 1048576 | floor')
  BITRATE=$(echo "$INFO" | jq -r '.format.bit_rate | tonumber / 1000 | floor')
  VIDEO_CODEC=$(echo "$INFO" | jq -r '.streams[] | select(.codec_type=="video") | .codec_name' | head -n1)
  AUDIO_CODEC=$(echo "$INFO" | jq -r '.streams[] | select(.codec_type=="audio") | .codec_name' | head -n1)
  CHANNELS=$(echo "$INFO" | jq -r '.streams[] | select(.codec_type=="audio") | .channels' | head -n1)

  MINUTES=$((DURATION / 60))
  SECONDS=$((DURATION % 60))

  echo "Duration: ${MINUTES} min ${SECONDS} sec, Size: ${SIZE} MB, Bitrate: ${BITRATE} kbps, Streams: video: ${VIDEO_CODEC}, audio: ${AUDIO_CODEC}, Channels: ${CHANNELS}ch"
}
