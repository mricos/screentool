#!/usr/bin/env bash
# screentool_env.sh

load_env() {
  if [ -f "$ST_SRC/screentool.env" ]; then
    source "$ST_SRC/screentool.env"
  fi

  case "$(uname)" in
    Darwin)
      export ST_OS_TYPE="macos"
      export ST_VIDEO_BACKEND="avfoundation"
      export ST_AUDIO_BACKEND="avfoundation"
      export ST_AVFOUNDATION_VIDEO_DEVICE="${ST_AVFOUNDATION_VIDEO_DEVICE:-0}"   # Default: screen 0
      export ST_AVFOUNDATION_AUDIO_DEVICE="${ST_AVFOUNDATION_AUDIO_DEVICE:-0}"   # Default: first audio input
      ;;
    Linux)
      export ST_OS_TYPE="linux"
      export DISPLAY="${DISPLAY:-:0}"
      export ST_VIDEO_BACKEND="x11grab"
      export ST_AUDIO_BACKEND="pulse"
      export ST_PULSE_IN_DEVICE="${ST_PULSE_IN_DEVICE:-@DEFAULT_SOURCE@}"
      export ST_PULSE_OUT_DEVICE="${ST_PULSE_OUT_DEVICE:-@DEFAULT_SINK@}"
      ;;
  esac
}

save_env() {
  # Always write out all platform-relevant vars
  {
    echo "export ST_SRC=\"$ST_SRC\""
    echo "export ST_DIR=\"$ST_DIR\""
    echo "export SCREEN_GEOMETRY=\"$SCREEN_GEOMETRY\""
    echo "export ST_OS_TYPE=\"$ST_OS_TYPE\""
    echo "export ST_VIDEO_BACKEND=\"$ST_VIDEO_BACKEND\""
    echo "export ST_AUDIO_BACKEND=\"$ST_AUDIO_BACKEND\""
    case "$ST_OS_TYPE" in
      macos)
        echo "export ST_AVFOUNDATION_VIDEO_DEVICE=\"$ST_AVFOUNDATION_VIDEO_DEVICE\""
        echo "export ST_AVFOUNDATION_AUDIO_DEVICE=\"$ST_AVFOUNDATION_AUDIO_DEVICE\""
        ;;
      linux)
        echo "export DISPLAY=\"$DISPLAY\""
        echo "export ST_PULSE_IN_DEVICE=\"$ST_PULSE_IN_DEVICE\""
        echo "export ST_PULSE_OUT_DEVICE=\"$ST_PULSE_OUT_DEVICE\""
        ;;
    esac
    echo "export ST_BUFFER_SIZE=\"$ST_BUFFER_SIZE\""
    echo "export VIDEO_CODEC=\"$VIDEO_CODEC\""
    echo "export PRESET=\"$PRESET\""
    echo "export CRF=\"$CRF\""
    echo "export COMPRESSION_TUNE=\"$COMPRESSION_TUNE\""
    echo "export COMPRESSION_GOP=\"$COMPRESSION_GOP\""
    echo "export FRAMERATE=\"$FRAMERATE\""
    echo "export AUDIO_CHANNELS=\"$AUDIO_CHANNELS\""
    echo "export AUDIO_CODEC=\"$AUDIO_CODEC\""
    echo "export AUDIO_BITRATE=\"$AUDIO_BITRATE\""
    # Save crop geometry if set
    if [[ -n "$ST_CROP_GEOMETRY" ]]; then
      echo "export ST_CROP_GEOMETRY=\"$ST_CROP_GEOMETRY\""
    fi
  } > "$ST_SRC/screentool.env"
}

