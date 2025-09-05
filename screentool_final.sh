#!/usr/bin/env bash
# Screentool final export script
# Process edit.mkv (or recording.mov) to final.mp4 for distribution

final_export() {
  local recording_id="$1"
  
  if [[ -z "$recording_id" ]]; then
    echo "Usage: st final <recording_id>"
    echo "Run 'st list' to see available recordings"
    return 1
  fi
  
  # Handle both index numbers and recording IDs
  local recording_dir
  if [[ "$recording_id" =~ ^[0-9]+$ ]] && [[ "$recording_id" -lt 100 ]]; then
    # Treat as index number
    local recording_file
    recording_file=$(get_recording_by_index "$recording_id")
    if [[ $? -ne 0 ]]; then
      return 1
    fi
    recording_dir=$(dirname "$recording_file")
    recording_id=$(basename "$recording_dir")
  else
    # Treat as recording ID
    recording_dir="$ST_DIR/$recording_id"
    if [[ ! -d "$recording_dir" ]]; then
      echo "Recording not found: $recording_id"
      echo "Run 'st list' to see available recordings"
      return 1
    fi
  fi
  
  local edit_file="$recording_dir/edit.mkv"
  # Look for any video file in the recording directory
  local source_file
  source_file=$(find "$recording_dir" \( -name "*.mkv" -o -name "*.mov" -o -name "*.mp4" \) | head -1)
  
  if [[ -f "$source_file" ]]; then
    source_file="$source_file"  # OBS output or legacy recording
    echo "Found recording: $source_file"
  else
    echo "Expected: edit.mkv, recording.mkv (OBS), or recording.mov (legacy)"
    return 1
  fi
  local final_file="$recording_dir/final.mp4"
  local stats_file="$recording_dir/final.stats"
  local log_file="$recording_dir/final.log"
  
  # Determine source file (prefer edit.mkv, fallback to original recording)
  local input_file
  if [[ -f "$edit_file" ]]; then
    input_file="$edit_file"
    echo "Using edited version: $(basename "$edit_file")"
  elif [[ -n "$source_file" && -f "$source_file" ]]; then
    input_file="$source_file"
    echo "Using original recording: $(basename "$source_file")"
  else
    echo "No source file found in $recording_dir"
    echo "Expected: edit.mkv, recording.mkv (OBS), or recording.mov (legacy)"
    return 1
  fi
  
  echo "Creating final MP4 for distribution..."
  echo "Input: $input_file"
  echo "Output: $final_file"
  echo
  
  # Analyze input file
  echo "Analyzing input file..."
  if command -v ffprobe >/dev/null; then
    ffprobe -v quiet -print_format json -show_format -show_streams "$input_file" > "$stats_file.json" 2>/dev/null
    
    # Extract key stats for optimization
    local duration size_mb width height fps bitrate
    if command -v jq >/dev/null; then
      duration=$(jq -r '.format.duration // "unknown"' "$stats_file.json")
      size_mb=$(jq -r '.format.size // 0' "$stats_file.json" | awk '{printf "%.1f", $1/1024/1024}')
      width=$(jq -r '.streams[] | select(.codec_type=="video") | .width // 0' "$stats_file.json" | head -1)
      height=$(jq -r '.streams[] | select(.codec_type=="video") | .height // 0' "$stats_file.json" | head -1)
      fps=$(jq -r '.streams[] | select(.codec_type=="video") | .r_frame_rate // "0/1"' "$stats_file.json" | head -1 | awk -F'/' '{if($2>0) printf "%.1f", $1/$2; else print "0"}')
      bitrate=$(jq -r '.format.bit_rate // 0' "$stats_file.json" | awk '{printf "%.0f", $1/1000}')
    fi
    
    echo "Input: ${width}x${height}, ${duration}s, ${size_mb}MB, ${fps}fps"
    
    # Create stats file
    cat > "$stats_file" << EOF
Final Export Analysis - $(date)
===============================
Input File: $(basename "$input_file")
Input Size: ${size_mb}MB
Resolution: ${width}x${height}
Duration: ${duration}s
FPS: ${fps}
Input Bitrate: ${bitrate}kbps

Export Settings
===============
Output: $(basename "$final_file")
Format: MP4 (H.264 + AAC)
Quality: Distribution optimized
Target: Web/sharing friendly
EOF
  fi
  
  # Build final export command optimized for distribution
  local export_cmd=(
    ffmpeg
    -i "$input_file"
    -c:v libx264          # H.264 for compatibility
    -preset slower        # Better compression
    -crf 20              # High quality for final
    -pix_fmt yuv420p     # Maximum compatibility
    -c:a aac             # AAC audio for web
    -b:a 128k            # Good audio quality
    -ac 2                # Stereo output
    -movflags +faststart # Fast web streaming
    "$final_file"
  )
  
  echo "Export command: ${export_cmd[*]}"
  echo
  echo "Creating final MP4..."
  
  # Execute final export
  if "${export_cmd[@]}" 2>&1 | tee "$log_file"; then
    echo
    echo "✅ Final export completed!"
    
    # Get final file info
    if [[ -f "$final_file" ]]; then
      local final_size
      final_size=$(stat -f "%z" "$final_file" 2>/dev/null)
      if [[ -n "$final_size" ]]; then
        final_size=$(echo "$final_size" | awk '{printf "%.1fMB", $1/1024/1024}')
        echo "Final file size: $final_size"
        
        # Calculate compression ratio
        if [[ -n "$size_mb" ]] && [[ "$size_mb" != "0.0" ]]; then
          local ratio
          ratio=$(echo "$size_mb $final_size" | awk '{printf "%.1fx", $1/$2}')
          echo "Compression: $ratio smaller"
        fi
        
        # Update stats with final results
        cat >> "$stats_file" << EOF

Final Export Results - $(date)
==============================
Final File: $(basename "$final_file")
Final Size: ${final_size}
Compression Ratio: ${ratio:-unknown}
Export: SUCCESS
Log: $(basename "$log_file")

Files in Recording $recording_id:
=================================
recording.mov - Original capture
edit.mkv      - Editing version (if exists)
final.mp4     - Distribution version ✓
EOF
      fi
    fi
    
    echo
    echo "📁 Recording $recording_id files:"
    echo "   🎬 recording.mov (original)"
    if [[ -f "$edit_file" ]]; then
      echo "   ✏️  edit.mkv (editing)"
    fi
    echo "   🎯 final.mp4 (distribution) ← NEW"
    echo "   📊 final.stats"
    echo "   📝 final.log"
    echo
    echo "🎉 Ready for sharing: $final_file"
    
  else
    echo "✗ Final export failed"
    echo "Check log: $log_file"
    return 1
  fi

  # Audio export for final.mp4
  local audio_input="$recording_dir/edit_audio.wav"
  if [[ ! -f "$audio_input" ]]; then
    audio_input="$recording_dir/recording.mov"
  fi

  # Audio export command
  local audio_export_cmd=(
    ffmpeg
    -i "$audio_input"
    -acodec aac           # AAC codec for distribution
    -ar 48000             # 48kHz sample rate
    -ac "$AUDIO_CHANNELS" # Mono/Stereo from env
    -b:a "$AUDIO_FINAL_BITRATE"  # High-quality distribution bitrate
    -cutoff 18000         # Preserve high frequencies
    "$recording_dir/final_audio.m4a"
  )

  # Execute audio export
  if "${audio_export_cmd[@]}"; then
    echo "✓ Audio exported for distribution: final_audio.m4a"
  else
    echo "⚠️ Audio export for distribution failed"
  fi
}
