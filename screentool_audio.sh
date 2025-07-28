#!/usr/bin/env bash
# screentool_audio.sh

source "$ST_SRC/screentool_macos_devices.sh"

list_audio_inputs() {
  if [[ "$ST_OS_TYPE" == "macos" ]]; then
    print_macos_devices
    echo
    echo "Refer to the '[index] Device Name' lines above."
    echo "If you do not see your microphone or virtual device, ensure:"
    echo " - The device is enabled in System Preferences."
    echo " - You have granted Terminal permissions for microphone."
  else
    pactl list sources short | awk '{print NR". "$2}'
  fi
}

list_audio_outputs() {
  if [[ "$ST_OS_TYPE" == "macos" ]]; then
    echo "(audio output selection not directly supported via avfoundation; use system audio routing or BlackHole/Loopback.)"
    print_macos_devices
  else
    pactl list sinks short | awk '{print NR". "$2}'
  fi
}

configure_audio() {
  if [[ "$ST_OS_TYPE" == "macos" ]]; then
    echo "Audio Configuration"
    echo "=================="
    echo
    
    print_macos_devices
    
    echo
    echo "Current audio settings:"
    echo "  Device index: ${ST_AVFOUNDATION_AUDIO_DEVICE:-0}"
    echo "  Codec: ${AUDIO_CODEC:-aac}"
    echo "  Sample rate: ${AUDIO_BITRATE:-48000} Hz"
    echo "  Channels: ${AUDIO_CHANNELS:-1} (1=mono, 2=stereo)"
    echo
    
    # Audio device selection
    read -rp "Enter audio input device index (or press Enter for current): " idx
    if [[ -n "$idx" ]]; then
      if [[ "$idx" =~ ^[0-9]+$ ]]; then
        export ST_AVFOUNDATION_AUDIO_DEVICE="$idx"
        echo "✓ Audio device set to index: $idx"
      else
        echo "⚠️  Invalid input, keeping current setting"
      fi
    fi
    
    # Audio quality options
    echo
    echo "Audio quality options:"
    echo "1) High (48kHz stereo) - ~192 kbps"
    echo "2) Medium (48kHz mono) - ~96 kbps [current]"
    echo "3) Low (22kHz mono) - ~48 kbps"
    echo "4) Keep current settings"
    echo
    read -rp "Select audio quality (1-4, default 4): " quality
    
    case $quality in
      1)
        export AUDIO_BITRATE="48000"
        export AUDIO_CHANNELS="2"
        echo "✓ Set to high quality (48kHz stereo)"
        ;;
      2)
        export AUDIO_BITRATE="48000"
        export AUDIO_CHANNELS="1"
        echo "✓ Set to medium quality (48kHz mono)"
        ;;
      3)
        export AUDIO_BITRATE="22050"
        export AUDIO_CHANNELS="1"
        echo "✓ Set to low quality (22kHz mono)"
        ;;
      *)
        echo "✓ Keeping current settings"
        ;;
    esac
    
    save_env
    echo
    echo "Audio configuration saved!"
    echo "💡 Tip: Test your audio with './screentool.sh record test.mp4' (Ctrl+C to stop)"
  else
    configure_recording
    configure_playback
  fi
}

