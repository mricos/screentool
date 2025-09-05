#!/usr/bin/env bash
# screentool_record_ffmpeg.sh  
# FFmpeg-based recording for Linux and advanced macOS use cases

record_ffmpeg() {
  local prefix duration recording_id recording_dir recording_path
  prefix="${1:-screen}"
  duration="${2:-}"  # Optional duration parameter
  recording_id="$(date +%s)"
  recording_dir="$ST_DIR/$recording_id"
  recording_path="$recording_dir/recording.mov"
  
  # Create recording directory
  mkdir -p "$recording_dir"
  
  # Create recording metadata
  cat > "$recording_dir/recording.meta" << EOF
RECORDING_NAME="$prefix"
RECORDING_ID="$recording_id"
RECORDING_PATH="$recording_path"
RECORDING_LOG="recording.log"
START_TIME="$(date)"
SCREEN_DEVICE="$ST_AVFOUNDATION_VIDEO_DEVICE"
AUDIO_DEVICE="$ST_AVFOUNDATION_AUDIO_DEVICE"
CROP_GEOMETRY="$ST_CROP_GEOMETRY"
SCREEN_GEOMETRY="$SCREEN_GEOMETRY"
RECORDING_FORMAT="mov"
EDIT_FORMAT="mkv"
FINAL_FORMAT="mp4"
RECORDING_METHOD="ffmpeg"
EOF
  
  echo "Recording ID: $recording_id"
  echo "Recording will be saved to: $recording_path"
  echo "Press Ctrl+C to stop recording, or wait for timeout..."
  echo

  if [[ "$ST_OS_TYPE" == "macos" ]]; then
    # FFmpeg AVFoundation approach for macOS (advanced)
    vid="${ST_AVFOUNDATION_VIDEO_DEVICE:-2}"  # Default to screen capture device
    aud="${ST_AVFOUNDATION_AUDIO_DEVICE:-1}"  # Default to microphone
    echo "Recording from video device index $vid and audio device index $aud"

    # Separate input options from output options
    local input_opts=()
    local output_opts=()
    
    # Handle crop geometry
    if [[ -n "$ST_CROP_GEOMETRY" ]]; then
      # Area selection - parse WxH+X+Y format
      if [[ "$ST_CROP_GEOMETRY" =~ ^([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+)$ ]]; then
        width="${BASH_REMATCH[1]}"
        height="${BASH_REMATCH[2]}"
        x="${BASH_REMATCH[3]}"
        y="${BASH_REMATCH[4]}"
        output_opts+=(-vf "crop=${width}:${height}:${x}:${y}")
        echo "Video crop geometry: ${width}x${height} at ${x},${y}"
      else
        echo "Warning: Invalid crop geometry format: $ST_CROP_GEOMETRY"
        echo "Expected format: WxH+X+Y (e.g., 1920x1080+100+100)"
      fi
    fi

    # Build ffmpeg command with proper AVFoundation parameters
    local ffmpeg_cmd=(
      ffmpeg
      -f avfoundation
      -pixel_format uyvy422  # Use supported input format
      -framerate "$FRAMERATE"
      -i "${vid}:${aud}"
      "${output_opts[@]}"
      -c:v "$VIDEO_CODEC" -preset "$PRESET" -crf "$CRF"
      -pix_fmt yuv420p  # Convert to standard output format
      -c:a "$AUDIO_CODEC" -b:a "$AUDIO_BITRATE" -ac "$AUDIO_CHANNELS"
    )
    
    # Add duration if specified
    if [[ -n "$duration" ]]; then
      ffmpeg_cmd+=(-t "$duration")
      echo "Recording for $duration seconds..."
    fi
    
    # Add output file
    ffmpeg_cmd+=("$recording_path")
    
    # Set up signal handling
    trap 'echo "Recording stopped by user"; exit 0' SIGINT SIGTERM
    
    echo "FFmpeg command: ${ffmpeg_cmd[*]}"
    echo "Starting ffmpeg recording..."
    
    # Execute with error handling
    if "${ffmpeg_cmd[@]}"; then
      echo "✓ Recording completed successfully: $recording_path"
    else
      local exit_code=$?
      if [[ $exit_code -eq 130 ]] || [[ $exit_code -eq 255 ]]; then
        echo "Recording stopped by user"
        if [[ -f "$recording_path" ]]; then
          echo "✓ Recording saved: $recording_path"
        fi
      else
        echo "✗ FFmpeg recording failed (exit code: $exit_code)"
        echo "💡 Try: st record-mac for native macOS recording"
        return 1
      fi
    fi
    
  else
    # Linux X11 recording
    echo "Linux FFmpeg recording..."
    IFS='x+' read -r WIDTH HEIGHT OFFSET_X OFFSET_Y <<< "$SCREEN_GEOMETRY"
    
    local ffmpeg_cmd=(
      ffmpeg
      -f x11grab
      -video_size "${WIDTH}x${HEIGHT}"
      -framerate "$FRAMERATE"
      -i "$DISPLAY+${OFFSET_X},${OFFSET_Y}"
      -f pulse
      -i "${ST_PULSE_IN_DEVICE:-@DEFAULT_SOURCE@}"
      -c:v "$VIDEO_CODEC" -preset "$PRESET" -crf "$CRF"
      -c:a "$AUDIO_CODEC" -b:a "$AUDIO_BITRATE" -ac "$AUDIO_CHANNELS"
    )
    
    # Add duration if specified
    if [[ -n "$duration" ]]; then
      ffmpeg_cmd+=(-t "$duration")
    fi
    
    # Add output file
    ffmpeg_cmd+=("$recording_path")
    
    echo "Linux recording command: ${ffmpeg_cmd[*]}"
    
    # Execute recording
    if "${ffmpeg_cmd[@]}"; then
      echo "✓ Recording completed: $recording_path"
    else
      echo "✗ Linux recording failed"
      return 1
    fi
  fi
  
  # Update recording metadata with completion info
  cat >> "$recording_dir/recording.meta" << EOF
END_TIME="$(date)"
RECORDING_COMPLETE="true"
RECORDING_METHOD="ffmpeg"
EOF
  
  # Create/update latest symlink as sibling
  local latest_link="$ST_DIR/latest"
  rm -f "$latest_link"
  ln -sf "$recording_id" "$latest_link"
  echo "Updated latest -> $recording_id"
  
  # Reset trap
  trap - SIGINT SIGTERM
  
  echo
  echo "✅ FFmpeg recording complete!"
  echo "📁 Recording ID: $recording_id"
  echo "🎬 File: $recording_path"
  echo "▶️  Play: st play latest"
}
