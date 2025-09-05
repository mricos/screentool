#!/usr/bin/env bash
# screentool_mix_audio.sh
# Advanced audio mixing for multi-track recordings

# Source environment variables
source "$(dirname "$0")/env.sh"

# Display help information
show_mix_help() {
    echo "ScreenTool Audio Mixing Commands"
    echo "==============================="
    echo
    echo "BASIC MIXING:"
    echo "  st mix auto <recording_id>           Auto-mix all tracks to final.mp4"
    echo "  st mix custom <recording_id>         Interactive custom mixing"
    echo
    echo "TRACK ANALYSIS:"
    echo "  st mix analyze <recording_id>        Analyze all audio tracks"
    echo "  st mix levels <recording_id>         Show audio levels for each track"
    echo
    echo "ADVANCED MIXING:"
    echo "  st mix voice-only <recording_id>     Mix only voice track"
    echo "  st mix desktop-only <recording_id>   Mix only desktop audio"
    echo "  st mix balanced <recording_id>       Balanced voice + desktop mix"
    echo "  st mix original <recording_id>       Use original mixed audio (track 2)"
    echo
    echo "LEVEL ADJUSTMENTS:"
    echo "  st mix adjust <recording_id> --voice-gain 2.0 --desktop-gain 0.5"
    echo "  st mix adjust <recording_id> --voice-filter highpass --desktop-filter lowpass"
    echo
    echo "EXAMPLES:"
    echo "  st mix auto 2024-01-15_14-30-25      # Auto-mix all tracks"
    echo "  st mix balanced recording_001 --voice-gain 1.5 --desktop-gain 0.8"
    echo "  st mix voice-only recording_001       # Voice narration only"
}

# Analyze all audio tracks in a recording
analyze_tracks() {
    local recording_id="$1"
    
    if [[ -z "$recording_id" ]]; then
        echo "Usage: st mix analyze <recording_id>"
        return 1
    fi
    
    # Handle both index numbers and recording IDs
    local recording_dir
    if [[ "$recording_id" == "." ]]; then
        # Use current directory
        recording_dir="$(pwd)"
        recording_id="$(basename "$recording_dir")"
    elif [[ "$recording_id" =~ ^[0-9]+$ ]] && [[ "$recording_id" -lt 100 ]]; then
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
            return 1
        fi
    fi
    
    echo "🎵 Audio Track Analysis: $recording_id"
    echo "======================================"
    echo
    
    # Find all track files
    local tracks=()
    for i in {1..4}; do
        local track_file="$recording_dir/recording_track${i}.mkv"
        if [[ -f "$track_file" ]]; then
            tracks+=("$track_file")
        fi
    done
    
    if [[ ${#tracks[@]} -eq 0 ]]; then
        echo "❌ No track files found in $recording_dir"
        echo "Expected: recording_track1.mkv, recording_track2.mkv, etc."
        return 1
    fi
    
    # Analyze each track
    for track_file in "${tracks[@]}"; do
        local track_num=$(basename "$track_file" | grep -o 'track[0-9]' | grep -o '[0-9]')
        local track_type=""
        
        case "$track_num" in
            1) track_type="Video Only" ;;
            2) track_type="Voice + Desktop" ;;
            3) track_type="Voice Only" ;;
            4) track_type="Desktop Only" ;;
        esac
        
        echo "📊 Track $track_num: $track_type"
        echo "   File: $(basename "$track_file")"
        
        # Check if track has audio
        local audio_streams
        audio_streams=$(ffprobe -v quiet -select_streams a -show_entries stream=codec_name -of csv=p=0 "$track_file" 2>/dev/null)
        
        if [[ -n "$audio_streams" ]]; then
            echo "   Audio: ✓ ($audio_streams)"
            
            # Get audio level analysis
            local level_info
            level_info=$(ffmpeg -i "$track_file" -af "volumedetect" -f null - 2>&1 | grep -E "(mean_volume|max_volume)" | head -2)
            
            if [[ -n "$level_info" ]]; then
                echo "$level_info" | while IFS= read -r line; do
                    echo "   $line"
                done
            fi
        else
            echo "   Audio: ❌ No audio stream"
        fi
        echo
    done
    
    # Suggest mixing strategy
    echo "🎯 Mixing Recommendations:"
    echo "========================="
    echo
    echo "For Voice Narration:"
    echo "  st mix voice-only $recording_id"
    echo
    echo "For Balanced Mix:"
    echo "  st mix balanced $recording_id --voice-gain 1.2 --desktop-gain 0.6"
    echo
    echo "For Desktop Audio Only:"
    echo "  st mix desktop-only $recording_id"
    echo
}

# Auto-mix all tracks with intelligent defaults
auto_mix() {
    local recording_id="$1"
    shift
    
    if [[ -z "$recording_id" ]]; then
        echo "Usage: st mix auto <recording_id>"
        return 1
    fi
    
    # Parse additional options
    local voice_gain=1.0
    local desktop_gain=0.7
    local output_file=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --voice-gain)
                voice_gain="$2"
                shift 2
                ;;
            --desktop-gain)
                desktop_gain="$2"
                shift 2
                ;;
            --output|-o)
                output_file="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                shift
                ;;
        esac
    done
    
    # Get recording directory
    local recording_dir
    if [[ "$recording_id" == "." ]]; then
        # Use current directory
        recording_dir="$(pwd)"
        recording_id="$(basename "$recording_dir")"
    else
        recording_dir="$ST_DIR/$recording_id"
        if [[ ! -d "$recording_dir" ]]; then
            echo "Recording not found: $recording_id"
            return 1
        fi
    fi
    
    # Set output file
    if [[ -z "$output_file" ]]; then
        output_file="$recording_dir/final.mp4"
    fi
    
    echo "🎬 Auto-Mixing Audio Tracks"
    echo "==========================="
    echo "Recording: $recording_id"
    echo "Voice Gain: ${voice_gain}x"
    echo "Desktop Gain: ${desktop_gain}x"
    echo "Output: $output_file"
    echo
    
    # Find required tracks
    local video_track="$recording_dir/recording_track1.mkv"  # Video only
    local voice_track="$recording_dir/recording_track3.mkv"  # Voice only
    local desktop_track="$recording_dir/recording_track4.mkv" # Desktop only
    
    # Verify tracks exist
    if [[ ! -f "$video_track" ]]; then
        echo "❌ Video track not found: $video_track"
        return 1
    fi
    
    if [[ ! -f "$voice_track" ]] && [[ ! -f "$desktop_track" ]]; then
        echo "❌ No audio tracks found"
        return 1
    fi
    
    # Build FFmpeg command
    local ffmpeg_cmd=(ffmpeg -y)
    local input_count=0
    local filter_complex=""
    
    # Add video input
    ffmpeg_cmd+=(-i "$video_track")
    ((input_count++))
    
    # Build audio mixing filter
    local audio_inputs=()
    local audio_filters=()
    
    # Add voice track if exists
    if [[ -f "$voice_track" ]]; then
        ffmpeg_cmd+=(-i "$voice_track")
        audio_inputs+=("${input_count}:a")
        audio_filters+=("[${input_count}:a]volume=${voice_gain}[voice]")
        ((input_count++))
    fi
    
    # Add desktop track if exists
    if [[ -f "$desktop_track" ]]; then
        ffmpeg_cmd+=(-i "$desktop_track")
        audio_inputs+=("${input_count}:a")
        audio_filters+=("[${input_count}:a]volume=${desktop_gain}[desktop]")
        ((input_count++))
    fi
    
    # Create mixing filter
    if [[ ${#audio_inputs[@]} -eq 2 ]]; then
        # Mix both voice and desktop
        filter_complex="${audio_filters[0]};${audio_filters[1]};[voice][desktop]amix=inputs=2:duration=longest[mixed]"
    elif [[ ${#audio_inputs[@]} -eq 1 ]]; then
        # Only one audio source
        filter_complex="${audio_filters[0]}"
    fi
    
    # Add filter complex and mapping if we have audio
    if [[ -n "$filter_complex" ]]; then
        ffmpeg_cmd+=(-filter_complex "$filter_complex")
        # Add the map arguments
        if [[ ${#audio_inputs[@]} -eq 2 ]]; then
            ffmpeg_cmd+=(-map 0:v -map "[mixed]")
        elif [[ ${#audio_inputs[@]} -eq 1 ]]; then
            if [[ -f "$voice_track" ]]; then
                ffmpeg_cmd+=(-map 0:v -map "[voice]")
            else
                ffmpeg_cmd+=(-map 0:v -map "[desktop]")
            fi
        fi
    else
        # No audio, just map video
        ffmpeg_cmd+=(-map 0:v)
    fi
    
    # Add encoding options
    ffmpeg_cmd+=(
        -c:v libx264
        -preset medium
        -crf 20
        -pix_fmt yuv420p
        -c:a aac
        -b:a 128k
        -ac 2
        -ar 48000
        -movflags +faststart
    )
    
    # Add output file
    ffmpeg_cmd+=("$output_file")
    
    echo "🔄 Mixing Command:"
    echo "${ffmpeg_cmd[*]}"
    echo
    
    # Execute mixing
    if "${ffmpeg_cmd[@]}"; then
        echo
        echo "✅ Audio mixing completed!"
        echo "Output: $output_file"
        
        # Show file size
        if [[ -f "$output_file" ]]; then
            local file_size
            file_size=$(stat -f "%z" "$output_file" 2>/dev/null | awk '{printf "%.1fMB", $1/1024/1024}')
            echo "Size: $file_size"
        fi
        
        echo
        echo "▶️  Play result: st play $recording_id"
        
    else
        echo "❌ Audio mixing failed"
        return 1
    fi
}

# Mix only voice track
voice_only_mix() {
    local recording_id="$1"
    local voice_gain="${2:-1.2}"  # Slightly boost voice by default
    
    echo "🎙️ Voice-Only Mix"
    echo "================="
    
    local recording_dir
    if [[ "$recording_id" == "." ]]; then
        recording_dir="$(pwd)"
    else
        recording_dir="$ST_DIR/$recording_id"
    fi
    local video_track="$recording_dir/recording_track1.mkv"
    local voice_track="$recording_dir/recording_track3.mkv"
    local output_file="$recording_dir/final_voice.mp4"
    
    if [[ ! -f "$voice_track" ]]; then
        echo "❌ Voice track not found: $voice_track"
        return 1
    fi
    
    ffmpeg -y \
        -i "$video_track" \
        -i "$voice_track" \
        -map 0:v -map 1:a \
        -filter:a "volume=${voice_gain}" \
        -c:v libx264 -preset medium -crf 20 \
        -c:a aac -b:a 128k \
        -movflags +faststart \
        "$output_file"
    
    echo "✅ Voice-only mix complete: $output_file"
}

# Mix only desktop audio
desktop_only_mix() {
    local recording_id="$1"
    local desktop_gain="${2:-0.8}"
    
    echo "🖥️ Desktop Audio-Only Mix"
    echo "========================="
    
    local recording_dir
    if [[ "$recording_id" == "." ]]; then
        recording_dir="$(pwd)"
    else
        recording_dir="$ST_DIR/$recording_id"
    fi
    local video_track="$recording_dir/recording_track1.mkv"
    local desktop_track="$recording_dir/recording_track4.mkv"
    local output_file="$recording_dir/final_desktop.mp4"
    
    if [[ ! -f "$desktop_track" ]]; then
        echo "❌ Desktop track not found: $desktop_track"
        return 1
    fi
    
    ffmpeg -y \
        -i "$video_track" \
        -i "$desktop_track" \
        -map 0:v -map 1:a \
        -filter:a "volume=${desktop_gain}" \
        -c:v libx264 -preset medium -crf 20 \
        -c:a aac -b:a 128k \
        -movflags +faststart \
        "$output_file"
    
    echo "✅ Desktop audio-only mix complete: $output_file"
}

# Use original mixed audio (track 2)
original_mix() {
    local recording_id="$1"
    
    echo "🎵 Original Mix (Track 1 + Track 2)"
    echo "==================================="
    
    local recording_dir
    if [[ "$recording_id" == "." ]]; then
        recording_dir="$(pwd)"
    else
        recording_dir="$ST_DIR/$recording_id"
    fi
    local video_track="$recording_dir/recording_track1.mkv"
    local original_track="$recording_dir/recording_track2.mkv"
    local output_file="$recording_dir/final_original.mp4"
    
    if [[ ! -f "$original_track" ]]; then
        echo "❌ Original mixed track not found: $original_track"
        return 1
    fi
    
    ffmpeg -y \
        -i "$video_track" \
        -i "$original_track" \
        -map 0:v -map 1:a \
        -c:v libx264 -preset medium -crf 20 \
        -c:a aac -b:a 128k \
        -movflags +faststart \
        "$output_file"
    
    echo "✅ Original mix complete: $output_file"
}

# Balanced mix with custom gains
balanced_mix() {
    local recording_id="$1"
    shift
    
    # Default balanced settings
    local voice_gain=1.0
    local desktop_gain=0.6
    local voice_filter=""
    local desktop_filter=""
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --voice-gain)
                voice_gain="$2"
                shift 2
                ;;
            --desktop-gain)
                desktop_gain="$2"
                shift 2
                ;;
            --voice-filter)
                voice_filter="$2"
                shift 2
                ;;
            --desktop-filter)
                desktop_filter="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    echo "⚖️ Balanced Audio Mix"
    echo "===================="
    echo "Voice Gain: ${voice_gain}x"
    echo "Desktop Gain: ${desktop_gain}x"
    
    auto_mix "$recording_id" --voice-gain "$voice_gain" --desktop-gain "$desktop_gain" --output "$ST_DIR/$recording_id/final_balanced.mp4"
}

# Main mix function
mix_main() {
    local command="${1:-help}"
    shift
    
    case "$command" in
        "help")
            show_mix_help
            ;;
        "analyze")
            analyze_tracks "$@"
            ;;
        "auto")
            auto_mix "$@"
            ;;
        "voice-only")
            voice_only_mix "$@"
            ;;
        "desktop-only")
            desktop_only_mix "$@"
            ;;
        "balanced")
            balanced_mix "$@"
            ;;
        "original")
            original_mix "$@"
            ;;
        *)
            echo "❌ Unknown command: $command"
            show_mix_help
            return 1
            ;;
    esac
}

# Run the main function with all arguments
mix_main "$@"
