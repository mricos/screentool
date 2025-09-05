#!/usr/bin/env bash
# screentool_audio.sh
# Audio analysis and processing functions

analyze_audio() {
  local file="$1"
  
  if [[ ! -f "$file" ]]; then
    echo "File not found: $file"
    return 1
  fi
  
  echo "🎵 Audio Analysis: $(basename "$file")"
  echo "=================================="
  echo
  
  # Basic audio stream info
  if command -v ffprobe >/dev/null; then
    local probe_data
    probe_data=$(ffprobe -v quiet -print_format json -show_format -show_streams "$file" 2>/dev/null)
    
    if [[ -z "$probe_data" ]]; then
      echo "❌ Unable to probe file"
      return 1
    fi
    
    # Check if audio streams exist
    local audio_streams
    audio_streams=$(echo "$probe_data" | jq -r '.streams[] | select(.codec_type=="audio") | .index' 2>/dev/null)
    
    if [[ -z "$audio_streams" ]]; then
      echo "❌ No audio streams found in file"
      echo
      echo "🔧 Possible Issues:"
      echo "   • Recording was made without audio capture"
      echo "   • Audio device was not properly configured"
      echo "   • macOS screencapture -v flag may not be working"
      echo
      echo "🎯 Next Steps:"
      echo "   1. Check audio input device: st audio"
      echo "   2. Test audio recording: st record-test-audio"
      echo "   3. Verify microphone permissions in System Preferences"
      return 1
    fi
    
    # Detailed audio analysis for each stream
    local stream_count=0
    while IFS= read -r stream_index; do
      ((stream_count++))
      echo "📊 Audio Stream $stream_count (index: $stream_index):"
      
      # Basic stream info
      local codec=$(echo "$probe_data" | jq -r ".streams[$stream_index].codec_name // \"unknown\"")
      local channels=$(echo "$probe_data" | jq -r ".streams[$stream_index].channels // 0")
      local sample_rate=$(echo "$probe_data" | jq -r ".streams[$stream_index].sample_rate // 0")
      local bitrate=$(echo "$probe_data" | jq -r ".streams[$stream_index].bit_rate // 0")
      local duration=$(echo "$probe_data" | jq -r ".streams[$stream_index].duration // 0")
      local layout=$(echo "$probe_data" | jq -r ".streams[$stream_index].channel_layout // \"unknown\"")
      
      echo "   Codec: $codec"
      echo "   Channels: $channels ($layout)"
      echo "   Sample Rate: ${sample_rate}Hz"
      if [[ "$bitrate" != "0" ]]; then
        echo "   Bitrate: $(echo "$bitrate" | awk '{printf "%.0fkbps", $1/1000}')"
      fi
      if [[ "$duration" != "0" ]]; then
        echo "   Duration: $(printf "%.2fs" "$duration")"
      fi
      echo
      
    done <<< "$audio_streams"
    
    # Audio level analysis
    echo "🔊 Audio Level Analysis:"
    if command -v ffmpeg >/dev/null; then
      echo "   Analyzing audio levels..."
      local level_analysis
      level_analysis=$(ffmpeg -i "$file" -af "volumedetect" -f null - 2>&1 | grep -E "(mean_volume|max_volume)")
      
      if [[ -n "$level_analysis" ]]; then
        echo "$level_analysis" | while IFS= read -r line; do
          echo "   $line"
        done
      else
        echo "   Unable to analyze audio levels"
      fi
    else
      echo "   ffmpeg not available for level analysis"
    fi
    echo
    
    # Audio processing suggestions
    echo "🎯 Audio Processing Suggestions:"
    echo
    echo "📈 Voice Detection & Analysis:"
    echo "   st audio-voice-detect $file    # Detect speech segments"
    echo "   st audio-silence-detect $file  # Find silent parts"
    echo
    echo "🔧 Audio Enhancement:"
    echo "   st audio-normalize $file        # Normalize audio levels"
    echo "   st audio-denoise $file          # Remove background noise"
    echo "   st audio-compress $file         # Apply compression"
    echo
    echo "🎚️ Audio Mixing & Editing:"
    echo "   st audio-extract $file          # Extract audio to separate file"
    echo "   st audio-mix file1.wav file2.wav # Mix two audio tracks"
    echo "   st audio-trim $file start end   # Trim audio segment"
    echo
    echo "📊 Advanced Analysis:"
    echo "   st audio-spectrum $file         # Generate frequency spectrum"
    echo "   st audio-waveform $file         # Generate waveform image"
    
  else
    echo "❌ ffprobe not available - install ffmpeg for audio analysis"
    return 1
  fi
}

# Detect if recording has audio issues
check_audio_recording_setup() {
  echo "🎤 Audio Recording Setup Check"
  echo "=============================="
  echo
  
  # Check if audio input device is set
  if [[ -n "$ST_AVFOUNDATION_AUDIO_DEVICE" ]]; then
    echo "✓ Audio input device configured: $ST_AVFOUNDATION_AUDIO_DEVICE"
  else
    echo "❌ No audio input device configured"
    echo "   Run: st audio"
  fi
  
  # Check macOS audio permissions more thoroughly
  echo
  echo "🔐 macOS Audio Permissions Check:"
  echo "   screencapture requires microphone access for audio recording"
  echo
  
  # Test screencapture audio capability
  echo "🧪 Testing screencapture audio access..."
  local test_file="/tmp/screentool_audio_test.mov"
  
  # Try a very short test recording
  if screencapture -V 1 -v "$test_file" 2>/dev/null; then
    if [[ -f "$test_file" ]]; then
      # Check if the test file has audio
      local audio_streams
      audio_streams=$(ffprobe -v quiet -select_streams a -show_entries stream=codec_name -of csv=p=0 "$test_file" 2>/dev/null)
      
      if [[ -n "$audio_streams" ]]; then
        echo "✅ Audio recording is working!"
        echo "   Test file has audio stream: $audio_streams"
      else
        echo "❌ Audio recording failed - no audio stream in test file"
        echo "   This suggests a permissions issue"
      fi
      
      # Clean up test file
      rm -f "$test_file"
    else
      echo "❌ screencapture failed to create test file"
    fi
  else
    echo "❌ screencapture command failed"
    echo "   This usually means microphone permissions are denied"
  fi
  
  echo
  echo "🔧 If audio is not working:"
  echo "   1. Open System Preferences > Security & Privacy > Privacy > Microphone"
  echo "   2. Ensure your terminal app (Terminal, iTerm, etc.) is checked"
  echo "   3. You may need to restart your terminal after granting permissions"
  echo "   4. Try recording manually: screencapture -V 5 -v test.mov"
  
  # Show available devices for reference
  echo
  echo "🎵 Available Audio Input Devices:"
  if command -v system_profiler >/dev/null; then
    system_profiler SPAudioDataType | grep -A 5 -B 5 "Input"
  fi
}

# Stub functions for future audio pipeline
audio_voice_detect() {
  echo "🎙️ Voice Detection (Coming Soon)"
  echo "Will use sox/ffmpeg to detect speech segments"
}

audio_silence_detect() {
  echo "🔇 Silence Detection (Coming Soon)" 
  echo "Will identify quiet/silent segments for editing"
}

audio_normalize() {
  echo "📈 Audio Normalization (Coming Soon)"
  echo "Will normalize audio levels using sox/ffmpeg"
}

audio_denoise() {
  echo "🔧 Audio Denoising (Coming Soon)"
  echo "Will remove background noise using sox filters"
}

audio_extract() {
  echo "🎵 Audio Extraction (Coming Soon)"
  echo "Will extract audio track to separate WAV/FLAC file"
}

audio_mix() {
  echo "🎚️ Audio Mixing (Coming Soon)"
  echo "Will mix multiple audio tracks using sox"
}