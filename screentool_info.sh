# Display usage information
usage() {
  echo "Usage: $0 {start|info <file>|summary <file>|json <file>|input|output|select|save|load|env}"
  echo ""
  echo "Commands:"
  echo "  start              Start screen recording in the foreground (Ctrl-C to stop)."
  echo "  info <file>        Show human-readable info for the given file."
  echo "  summary <file>     Show a brief summary of the video file."
  echo "  json <file>        Show detailed JSON metadata of the video file."
  echo "  input              Show available audio input devices."
  echo "  output             Show available audio output devices."
  echo "  select             Select audio input and output devices."
  echo "  save               Save environment variables to the configuration file."
  echo "  load               Load environment variables from the configuration file."
  echo "  env                Show all environment variables being used."
  exit 1
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
