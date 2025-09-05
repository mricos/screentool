#!/usr/bin/env bash
# screentool_edit.sh
# Convert recording.mov to edit.mkv with processing and stats

edit_mov() {
  local recording_id="$1"
  
  if [[ -z "$recording_id" ]]; then
    echo "Usage: st edit <recording_id>"
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
  
  # Look for any video file in the recording directory
  local source_file
  source_file=$(find "$recording_dir" \( -name "*.mkv" -o -name "*.mov" -o -name "*.mp4" \) | head -1)
  
  if [[ -f "$source_file" ]]; then
    source_file="$source_file"  # OBS output or legacy recording
    echo "Found recording: $source_file"
  else
    echo "Expected: recording.mkv (OBS) or recording.mov (legacy)"
    return 1
  fi
  local edit_file="$recording_dir/edit.mkv"
  local stats_file="$recording_dir/edit.stats"
  local log_file="$recording_dir/edit.log"
  
  # Check if source exists
  if [[ ! -f "$source_file" ]]; then
    echo "Source recording not found: $source_file"
    return 1
  fi
  
  echo "Converting recording to editable format..."
  echo "Source: $source_file"
  echo "Output: $edit_file"
  echo
  
  # Get source file info
  echo "Analyzing source file..."
  if command -v ffprobe >/dev/null; then
    ffprobe -v quiet -print_format json -show_format -show_streams "$source_file" > "$stats_file.json" 2>/dev/null
    
    # Extract key stats
    local duration size_mb width height fps
    if command -v jq >/dev/null; then
      duration=$(jq -r '.format.duration // "unknown"' "$stats_file.json")
      size_mb=$(jq -r '.format.size // 0' "$stats_file.json" | awk '{printf "%.1f", $1/1024/1024}')
      width=$(jq -r '.streams[] | select(.codec_type=="video") | .width // 0' "$stats_file.json" | head -1)
      height=$(jq -r '.streams[] | select(.codec_type=="video") | .height // 0' "$stats_file.json" | head -1)
      fps=$(jq -r '.streams[] | select(.codec_type=="video") | .r_frame_rate // "0/1"' "$stats_file.json" | head -1 | awk -F'/' '{if($2>0) printf "%.1f", $1/$2; else print "0"}')
    fi
    
    # Create human-readable stats
    cat > "$stats_file" << EOF
Source Analysis - $(date)
==========================
File: $(basename "$source_file")
Duration: ${duration}s
Size: ${size_mb}MB
Resolution: ${width}x${height}
FPS: ${fps}
Format: MOV (QuickTime)

Conversion Target
=================
Output: $(basename "$edit_file")
Format: MKV (Matroska)
Purpose: Editing-friendly format
EOF
    
    echo "Source: ${width}x${height}, ${duration}s, ${size_mb}MB"
  fi
  
  # Convert MOV to MKV with editing-friendly settings and crop/scale
  echo "Converting to MKV format..."
  
  # Build filter chain for crop and scale
  local video_filters=()
  
  # Apply crop geometry from recording metadata if it exists
  local meta_file="$(dirname "$source_file")/recording.meta"
  local crop_geometry=""
  if [[ -f "$meta_file" ]]; then
    crop_geometry=$(grep "^CROP_GEOMETRY=" "$meta_file" | cut -d'"' -f2 2>/dev/null)
  fi
  
  if [[ -n "$crop_geometry" ]] && [[ "$crop_geometry" =~ ^([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+)$ ]]; then
    local crop_w="${BASH_REMATCH[1]}"
    local crop_h="${BASH_REMATCH[2]}" 
    local crop_x="${BASH_REMATCH[3]}"
    local crop_y="${BASH_REMATCH[4]}"
    
    echo "Applying crop from recording: ${crop_w}x${crop_h} at ${crop_x},${crop_y}"
    video_filters+=("crop=${crop_w}:${crop_h}:${crop_x}:${crop_y}")
  fi
  
  # Add downscaling for upload-friendly size
  local target_width="${EDIT_TARGET_WIDTH:-1920}"
  local target_height="${EDIT_TARGET_HEIGHT:-1080}"
  
  echo "Downscaling to upload-friendly size: ${target_width}x${target_height}"
  video_filters+=("scale=${target_width}:${target_height}:force_original_aspect_ratio=decrease")
  video_filters+=("pad=${target_width}:${target_height}:(ow-iw)/2:(oh-ih)/2:black")
  
  # Join filters with comma
  local filter_string
  if [[ ${#video_filters[@]} -gt 0 ]]; then
    filter_string=$(IFS=','; echo "${video_filters[*]}")
  fi
  
  local convert_cmd=(
    ffmpeg
    -i "$source_file"
  )
  
  # Add video filters if any
  if [[ -n "$filter_string" ]]; then
    convert_cmd+=(-vf "$filter_string")
  fi
  
  # Add encoding options
  convert_cmd+=(
    -c:v libx264          # Re-encode for editing compatibility
    -preset medium        # Good quality/speed balance
    -crf 18              # High quality for editing
    -pix_fmt yuv420p     # Standard format
    -c:a pcm_s16le       # Uncompressed audio for editing
    -movflags +faststart # Fast seeking
    "$edit_file"
  )
  
  echo "Conversion command: ${convert_cmd[*]}"
  echo
  
  # Execute conversion with progress
  if "${convert_cmd[@]}" 2>&1 | tee "$log_file"; then
    echo
    echo "✅ Conversion completed successfully!"
    
    # Get output file info
    if [[ -f "$edit_file" ]]; then
      local edit_size
      edit_size=$(stat -f "%z" "$edit_file" 2>/dev/null)
      if [[ -n "$edit_size" ]]; then
        edit_size=$(echo "$edit_size" | awk '{printf "%.1fMB", $1/1024/1024}')
        echo "Edit file size: $edit_size"
        
        # Update stats with conversion results
        cat >> "$stats_file" << EOF

Conversion Results - $(date)
============================
Edit File: $(basename "$edit_file")
Edit Size: ${edit_size}
Conversion: SUCCESS
Log: $(basename "$log_file")
EOF
      fi
    fi
    
    echo
    echo "📁 Files created:"
    echo "   🎬 $edit_file"
    echo "   📊 $stats_file"
    echo "   📝 $log_file"
    echo
    echo "▶️  Play edit: st play $recording_id"
    echo "🎯 Finalize: st final $recording_id"
    
  else
    echo "✗ Conversion failed"
    echo "Check log: $log_file"
    return 1
  fi

  # Audio conversion for edit.mkv
  local audio_input="$recording_dir/processed_audio.wav"
  if [[ ! -f "$audio_input" ]]; then
    audio_input="$recording_dir/recording.mov"
  fi

  # Audio conversion command
  local audio_convert_cmd=(
    ffmpeg
    -i "$audio_input"
    -acodec pcm_s16le   # 16-bit PCM for editing
    -ar 48000           # 48kHz sample rate
    -ac "$AUDIO_CHANNELS"  # Mono/Stereo from env
    -b:a "$AUDIO_EDIT_BITRATE"  # High-quality editing bitrate
    "$recording_dir/edit_audio.wav"
  )

  # Execute audio conversion
  if "${audio_convert_cmd[@]}"; then
    echo "✓ Audio converted for editing: edit_audio.wav"
  else
    echo "⚠️ Audio conversion for editing failed"
  fi
}
