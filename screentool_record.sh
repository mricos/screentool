#!/usr/bin/env bash
# screentool_record.sh

record() {
  local prefix timestamp geometry recording_path
  prefix="${1:-screen}"
  timestamp="$(date +'%Y%m%d_%H%M%S')"
  mkdir -p "$ST_DIR"
  recording_path="$ST_DIR/${prefix}_${timestamp}.mp4"

  if [[ "$ST_OS_TYPE" == "macos" ]]; then
    w=$(echo "$SCREEN_GEOMETRY" | awk -F'[x+]' '{print $1}')
    h=$(echo "$SCREEN_GEOMETRY" | awk -F'[x+]' '{print $2}')
    vid="${ST_AVFOUNDATION_VIDEO_DEVICE:-0}"
    aud="${ST_AVFOUNDATION_AUDIO_DEVICE:-0}"
    echo "Recording from video device index $vid and audio device index $aud"
    echo "Video geometry: ${w}x${h}"
    ffmpeg \
      -f avfoundation \
      -framerate "$FRAMERATE" \
      -video_size "${w}x${h}" \
      -i "${vid}:${aud}" \
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

