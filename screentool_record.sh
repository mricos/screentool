#!/usr/bin/env bash
# screentool_record.sh

record() {
  local prefix timestamp geometry recording_path
  prefix="${1:-screen}"
  timestamp="$(date +'%Y%m%d_%H%M%S')"
  mkdir -p "$ST_DIR"
  recording_path="$ST_DIR/${prefix}_${timestamp}.mp4"

  if [[ "$ST_OS_TYPE" == "macos" ]]; then
    vid="${ST_AVFOUNDATION_VIDEO_DEVICE:-0}"
    aud="${ST_AVFOUNDATION_AUDIO_DEVICE:-0}"
    echo "Recording from video device index $vid and audio device index $aud"

    # Separate input options from output options
    local input_opts=()
    local output_opts=()
    
    if [[ -n "$ST_CROP_GEOMETRY" ]]; then
      # Area selection
      IFS=':' read -r width height x y <<< "$ST_CROP_GEOMETRY"
      output_opts+=(-vf "crop=${width}:${height}:${x}:${y}")
      echo "Video crop geometry: ${width}x${height} at ${x},${y}"
      
      # When cropping, we need to capture the full screen containing the area.
      # Use SCREEN_GEOMETRY if set, otherwise get main display geometry.
      if [[ -n "$SCREEN_GEOMETRY" ]]; then
        local full_width
        full_width=$(echo "$SCREEN_GEOMETRY" | awk -F'[x+]' '{print $1}')
        local full_height
        full_height=$(echo "$SCREEN_GEOMETRY" | awk -F'[x+]' '{print $2}')
        input_opts+=(-video_size "${full_width}x${full_height}")
        echo "Capturing from screen with geometry: ${full_width}x${full_height}"
      else
        # Fallback to getting main display geometry
        local res
        res=$(system_profiler SPDisplaysDataType | grep Resolution | head -n1 | awk -F: '{print $2}' | xargs)
        local screen_width
        screen_width=$(echo "$res" | awk '{print $1}')
        local screen_height
        screen_height=$(echo "$res" | awk '{print $3}')
        input_opts+=(-video_size "${screen_width}x${screen_height}")
        echo "Capturing from main screen with geometry: ${screen_width}x${screen_height}"
      fi
    else
      # Full screen recording
      w=$(echo "$SCREEN_GEOMETRY" | awk -F'[x+]' '{print $1}')
      h=$(echo "$SCREEN_GEOMETRY" | awk -F'[x+]' '{print $2}')
      input_opts+=(-video_size "${w}x${h}")
      echo "Video geometry: ${w}x${h}"
    fi

    # Proper FFmpeg command structure: [input options] -i [input] [output options] [output]
    ffmpeg \
      -f avfoundation \
      -framerate "$FRAMERATE" \
      "${input_opts[@]}" \
      -i "${vid}:${aud}" \
      "${output_opts[@]}" \
      -c:v "$VIDEO_CODEC" -preset "$PRESET" -crf "$CRF" -tune "$COMPRESSION_TUNE" -g "$COMPRESSION_GOP" \
      -pix_fmt yuv420p -c:a "$AUDIO_CODEC" -b:a "$AUDIO_BITRATE" -ac "$AUDIO_CHANNELS" -movflags +faststart \
      "$recording_path"
  else
    IFS='x+' read -r WIDTH HEIGHT OFFSET_X OFFSET_Y <<< "$SCREEN_GEOMETRY"
    ffmpeg \
      -f x11grab \
      -video_size "${WIDTH}x${HEIGHT}" \
      -framerate "$FRAMERATE" \
      -i "$DISPLAY+${OFFSET_X},${OFFSET_Y}" \
      -f pulse \
      -i "${ST_PULSE_IN_DEVICE:-@DEFAULT_SOURCE@}" \
      -c:v "$VIDEO_CODEC" -preset "$PRESET" -crf "$CRF" -tune "$COMPRESSION_TUNE" -g "$COMPRESSION_GOP" \
      -pix_fmt yuv420p -c:a "$AUDIO_CODEC" -b:a "$AUDIO_BITRATE" -ac "$AUDIO_CHANNELS" -movflags +faststart \
      "$recording_path"
  fi

  ln -sf "$recording_path" "$ST_DIR/latest.mp4"
}

