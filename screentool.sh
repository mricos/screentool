#!/bin/bash
# screentool.sh
# Records a specific region of the screen (size + offset) and mono audio using ffmpeg with x11grab + pulse.
# Includes compression settings via environment variables.
# Also includes functions for environment display and human-readable metadata.

# ====================================================================
#                     DEFAULT CONFIGURATION
# ====================================================================

# Directory for saving recordings and logs
RECORD_DIR="$HOME/screen_recordings"
mkdir -p "$RECORD_DIR"

# -------------------- Audio Defaults --------------------
# Default Audio Input Device (Mono)
AUDIO_DEVICE_IN="${AUDIO_DEVICE_IN:-alsa_input.usb-Antlion_Audio_Antlion_Wireless_Microphone-00.mono-fallback}"

# Default Audio Output Device
AUDIO_DEVICE_OUT="${AUDIO_DEVICE_OUT:-alsa_output.usb-Schiit_Audio_I_m_Fulla_Schiit-00.analog-stereo}"

# Audio Sampling Rate
RATE="${RATE:-48000}"

# PulseAudio Buffer and Period Sizes
BUFFER_SIZE="${BUFFER_SIZE:-2048}"
PERIOD_SIZE="${PERIOD_SIZE:-1024}"

# Audio Channels (1 for Mono)
AUDIO_CHANNELS="${AUDIO_CHANNELS:-1}"

# -------------------- Video Defaults --------------------
# Screen Capture Size (Width x Height)
SCREEN_SIZE="${SCREEN_SIZE:-1920x1080}"

# Screen Capture Position (X,Y)
SCREEN_POSITION="${SCREEN_POSITION:-0,0}"

# Video Framerate
FRAMERATE="${FRAMERATE:-5}"

# Video Encoding Preset
PRESET="${PRESET:-veryfast}"

# Video Codec
VIDEO_CODEC="${VIDEO_CODEC:-libx264}"

# Constant Rate Factor (Quality; Lower is better quality)
CRF="${CRF:-23}"

# -------------------- Compression Settings --------------------
# GOP (Group of Pictures) Size (e.g., 300)
COMPRESSION_GOP="${COMPRESSION_GOP:-300}"

# Tune for compression
COMPRESSION_TUNE="${COMPRESSION_TUNE:-stillimage}"  # Default for libx264

# -------------------- Audio Encoding Defaults --------------------
AUDIO_CODEC="${AUDIO_CODEC:-aac}"
AUDIO_BITRATE="${AUDIO_BITRATE:-192k}"

# ====================================================================
#                         FUNCTIONS
# ====================================================================

# Function to list audio input devices
input() {
  echo "Available Audio Input Devices:"
  pactl list sources short | awk '{print $1"\t"$2"\t"$3"\t"$4}'
}

# Function to list audio output devices
output() {
  echo "Available Audio Output Devices:"
  pactl list sinks short | awk '{print $1"\t"$2"\t"$3"\t"$4}'
}

# Function to display environment variables
env_display() {
  echo "Current Environment Variables:"
  echo "-------------------------------"
  echo "VIDEO_CODEC=$VIDEO_CODEC"
  echo "PRESET=$PRESET"
  echo "CRF=$CRF"
  echo "COMPRESSION_TUNE=$COMPRESSION_TUNE"
  echo "COMPRESSION_GOP=$COMPRESSION_GOP"
  echo "FRAMERATE=$FRAMERATE"
  echo "SCREEN_SIZE=$SCREEN_SIZE"
  echo "SCREEN_POSITION=$SCREEN_POSITION"
  echo "AUDIO_DEVICE_IN=$AUDIO_DEVICE_IN"
  echo "AUDIO_DEVICE_OUT=$AUDIO_DEVICE_OUT"
  echo "RATE=$RATE"
  echo "BUFFER_SIZE=$BUFFER_SIZE"
  echo "PERIOD_SIZE=$PERIOD_SIZE"
  echo "AUDIO_CHANNELS=$AUDIO_CHANNELS"
  echo "AUDIO_CODEC=$AUDIO_CODEC"
  echo "AUDIO_BITRATE=$AUDIO_BITRATE"
  echo "-------------------------------"
}

# Function to validate preset and tune based on codec
validate_preset_tune() {
  local codec="$1"
  local preset="$2"
  local tune="$3"

  local valid_presets=()
  local valid_tunes=()

  if [ "$codec" == "libx264" ]; then
    valid_presets=(ultrafast superfast veryfast faster fast medium slow slower veryslow placebo)
    valid_tunes=(psnr ssim grain zerolatency fastdecode animation stillimage)
  elif [ "$codec" == "libx265" ]; then
    valid_presets=(ultrafast superfast veryfast faster fast medium slow slower veryslow placebo)
    valid_tunes=(psnr ssim grain zerolatency fastdecode animation)
  else
    echo "Unsupported VIDEO_CODEC: $codec"
    exit 1
  fi

  # Check if preset is valid
  if [[ ! " ${valid_presets[@]} " =~ " ${preset} " ]]; then
    echo "Error: Invalid preset '$preset' for codec '$codec'."
    echo "Valid presets for $codec: ${valid_presets[*]}"
    exit 1
  fi

  # Check if tune is valid
  if [[ ! " ${valid_tunes[@]} " =~ " ${tune} " ]]; then
    echo "Error: Invalid tune '$tune' for codec '$codec'."
    echo "Valid tunes for $codec: ${valid_tunes[*]}"
    exit 1
  fi
}

# Function to start recording
start_recording() {
  # Generate timestamp for filenames
  timestamp=$(date +'%Y%m%d_%H%M%S')
  prefix=${1:-"screen"}
  # Define paths for recording and logs
  recording_path="$RECORD_DIR/${prefix}_$timestamp.mp4"
  log_path="$RECORD_DIR/ffmpeg_$timestamp.log"

  echo "Starting recording: $recording_path"
  echo "Capture region: ${SCREEN_SIZE} at offset +${SCREEN_POSITION}"
  echo "Environment Variables:"
  env_display

  # Validate Audio Input Device
  if ! pactl list sources short | awk '{print $2}' | grep -qw "$AUDIO_DEVICE_IN"; then
    echo "Error: Audio input device '$AUDIO_DEVICE_IN' not found."
    input
    exit 1
  fi

  # Validate Audio Output Device
  if ! pactl list sinks short | awk '{print $2}' | grep -qw "$AUDIO_DEVICE_OUT"; then
    echo "Error: Audio output device '$AUDIO_DEVICE_OUT' not found."
    output
    exit 1
  fi

  # Validate preset and tune based on codec
  validate_preset_tune "$VIDEO_CODEC" "$PRESET" "$COMPRESSION_TUNE"

  # Display the ffmpeg command for verification
  echo "Executing ffmpeg command:"
  echo "ffmpeg -f x11grab -framerate $FRAMERATE -video_size $SCREEN_SIZE -i :0.0+$SCREEN_POSITION \\"
  echo "       -f pulse -i \"${AUDIO_DEVICE_IN}?buffer_size=$BUFFER_SIZE&period_size=$PERIOD_SIZE\" \\"
  echo "       -c:v $VIDEO_CODEC -preset $PRESET -crf $CRF -tune $COMPRESSION_TUNE -g $COMPRESSION_GOP -pix_fmt yuv420p \\"
  echo "       -c:a $AUDIO_CODEC -b:a $AUDIO_BITRATE -ac $AUDIO_CHANNELS \\"
  echo "       -movflags +faststart \\"
  echo "       $recording_path"
  echo "Running ffmpeg in the foreground. Press Ctrl-C to stop gracefully."

  # Start ffmpeg in the foreground, redirect output to log file using exec for proper signal handling
  exec ffmpeg \
    -f x11grab \
    -framerate "$FRAMERATE" \
    -video_size "$SCREEN_SIZE" \
    -i ":0.0+$SCREEN_POSITION" \
    -f pulse \
    -i "${AUDIO_DEVICE_IN}?buffer_size=$BUFFER_SIZE&period_size=$PERIOD_SIZE" \
    -c:v "$VIDEO_CODEC" \
    -preset "$PRESET" \
    -crf "$CRF" \
    -tune "$COMPRESSION_TUNE" \
    -g "$COMPRESSION_GOP" \
    -pix_fmt yuv420p \
    -c:a "$AUDIO_CODEC" \
    -b:a "$AUDIO_BITRATE" \
    -ac "$AUDIO_CHANNELS" \
    -movflags +faststart \
    "$recording_path" > "$log_path" 2>&1
}

# Function to display human-readable file info
pjv_file_info_human() {
  local file="$1"
  if [ ! -f "$file" ]; then
      echo "{\"error\": \"File not found: $file\"}"
      return
  fi

  # Get JSON metadata from ffprobe
  local info
  info="$(ffprobe -hide_banner -v quiet -print_format json -show_format -show_streams "$file")"

  # Extract top-level format info
  local duration size bit_rate
  duration="$(echo "$info" | jq -r '.format.duration')"
  size="$(echo "$info" | jq -r '.format.size')"
  bit_rate="$(echo "$info" | jq -r '.format.bit_rate')"

  # Validate numeric fields
  [[ "$duration" =~ ^[0-9]+(\.[0-9]+)?$ ]] || duration="0"
  [[ "$size" =~ ^[0-9]+$ ]] || size="0"
  [[ "$bit_rate" =~ ^[0-9]+$ ]] || bit_rate="0"

  # Convert units
  local mb
  mb="$(awk -v bytes="$size" 'BEGIN {printf "%.2f", (bytes/1048576)}')"
  local kbps
  kbps="$(awk -v br="$bit_rate" 'BEGIN {printf "%.1f", (br/1000)}')"

  # Convert float duration to simpler string
  local dur_str
  dur_str="$(awk -v d="$duration" 'BEGIN {printf "%.2f", d}')"

  # First video stream
  local vcodec width height raw_fps fps
  vcodec="$(echo "$info" | jq -r '.streams[] | select(.codec_type=="video") | .codec_name' | head -n1)"
  width="$(echo "$info" | jq -r '.streams[] | select(.codec_type=="video") | .width' | head -n1)"
  height="$(echo "$info" | jq -r '.streams[] | select(.codec_type=="video") | .height' | head -n1)"
  raw_fps="$(echo "$info" | jq -r '.streams[] | select(.codec_type=="video") | .r_frame_rate' | head -n1)"
  if [[ "$raw_fps" =~ ^[0-9]+/[0-9]+$ ]]; then
    fps="$(awk -F/ '{printf "%.2f", $1/$2}' <<< "$raw_fps")"
  else
    fps="$raw_fps"
  fi

  # First audio stream
  local acodec samplerate channels layout abr abr_kbps
  acodec="$(echo "$info" | jq -r '.streams[] | select(.codec_type=="audio") | .codec_name' | head -n1)"
  samplerate="$(echo "$info" | jq -r '.streams[] | select(.codec_type=="audio") | .sample_rate' | head -n1)"
  channels="$(echo "$info" | jq -r '.streams[] | select(.codec_type=="audio") | .channels' | head -n1)"
  layout="$(echo "$info" | jq -r '.streams[] | select(.codec_type=="audio") | .channel_layout' | head -n1)"
  abr="$(echo "$info" | jq -r '.streams[] | select(.codec_type=="audio") | .bit_rate' | head -n1)"
  [[ "$abr" =~ ^[0-9]+$ ]] || abr="0"
  abr_kbps="$(awk -v b="$abr" 'BEGIN {printf "%.1f", (b/1000)}')"

  # Convert sample rate to kHz
  [[ "$samplerate" =~ ^[0-9]+$ ]] || samplerate="0"
  local sr_khz
  sr_khz="$(awk -v sr="$samplerate" 'BEGIN {printf "%.1f", sr/1000}')"

  # If layout is unknown, use "#ch"
  if [ "$layout" = "unknown" ] || [ -z "$layout" ]; then
    layout="${channels}ch"
  fi

  # Print human-readable summary
  echo "File: $file"
  echo "Duration: ${dur_str}s, Size: ${mb}MB, Overall Bitrate: ${kbps} kb/s"
  if [ -n "$vcodec" ] && [ "$vcodec" != "null" ]; then
    echo "Video: $vcodec ${width}x${height} @ ${fps} fps"
  fi
  if [ -n "$acodec" ] && [ "$acodec" != "null" ]; then
    echo "Audio: $acodec (${layout}), ${sr_khz}kHz, ${abr_kbps} kb/s"
  fi
}

# ====================================================================
#                         MAIN DISPATCH
# ====================================================================

# Function to display usage information
usage() {
  echo "Usage: $0 {start|info <file>|input|output|env}"
  echo ""
  echo "Commands:"
  echo "  start              Start screen recording in the foreground (Ctrl-C to stop)."
  echo "  info <file>        Show human-readable info for the given file."
  echo "  input              Show available audio input devices."
  echo "  output             Show available audio output devices."
  echo "  env                Show all environment variables being used."
  exit 1
}

# Check for required dependencies
check_dependencies() {
  local deps=("ffmpeg" "jq" "pactl")
  for dep in "${deps[@]}"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      echo "Error: Required dependency '$dep' is not installed."
      echo "Please install it using your package manager."
      exit 1
    fi
  done
}

check_dependencies

# Parse command-line arguments
case "$1" in
  start)
    start_recording $2
    ;;
  info)
    if [ -z "$2" ]; then
      echo "Error: Please specify a file for info."
      echo "Usage: $0 info <file>"
      exit 1
    fi
    pjv_file_info_human "$2"
    ;;
  input)
    input
    ;;
  output)
    output
    ;;
  env)
    env_display
    ;;
  *)
    usage
    ;;
esac
