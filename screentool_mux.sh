#!/usr/bin/env bash
# screentool_mux.sh
# MKV Remuxing and Track Management for ScreenTool

# Source environment variables
source "$(dirname "$0")/env.sh"

# Display help information
show_mux_help() {
    echo "ScreenTool MUX (Multiplexing) Commands"
    echo "===================================="
    echo
    echo "TRACK INFORMATION:"
    echo "  st mux info <file>        Show detailed track information"
    echo "  st mux list-tracks <file> List all tracks in the file"
    echo
    echo "TRACK EXTRACTION:"
    echo "  st mux extract <file> <track_num>  Extract specific audio track"
    echo "  st mux extract-all <file>          Extract all tracks"
    echo
    echo "REMUXING OPTIONS:"
    echo "  st mux to-mp4 <file>                  Basic conversion"
    echo "  st mux to-mp4 -i file -o output.mp4  Specify input/output"
    echo "  st mux to-mp4 -vc libx265 -ac opus   Change codecs"
    echo "  st mux to-mp4 -crf 18                Adjust quality"
    echo "  st mux to-mp4 -t 1,2,3               Select specific tracks"
    echo "  st mux to-mp4 -f                     Force overwrite"
    echo
    echo "CODEC OPTIONS:"
    echo "  Video: libx264, libx265, etc."
    echo "  Audio: aac, opus, etc."
    echo "  CRF Range: 0-51 (lower = higher quality)"
    echo "  Presets: ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow"
    echo
    echo "ADVANCED OPERATIONS:"
    echo "  st mux merge <file1> <file2>  Merge multiple MKV files"
    echo "  st mux strip-metadata <file>  Remove metadata from file"
    echo
    echo "EXAMPLES:"
    echo "  st mux info recording.mkv"
    echo "  st mux extract recording.mkv 2"
    echo "  st mux to-mp4 recording.mkv"
}

# Get track information using ffprobe
mux_track_info() {
    local input_file="$1"
    
    # Verify file exists
    if [[ ! -f "$input_file" ]]; then
        echo "❌ File not found: $input_file"
        return 1
    fi
    
    echo "🎬 Track Information for: $input_file"
    echo "================================="
    
    # Detailed track information
    ffprobe -v quiet -print_format json -show_streams "$input_file"
}

# List tracks in a file
mux_list_tracks() {
    local input_file="$1"
    
    # Verify file exists
    if [[ ! -f "$input_file" ]]; then
        echo "❌ File not found: $input_file"
        return 1
    fi
    
    echo "🎧 Tracks in: $input_file"
    echo "====================="
    
    # Use ffprobe to list tracks
    ffprobe -v quiet -show_streams "$input_file" | grep -E 'index=|codec_type='
}

# Extract specific track
mux_extract_track() {
    local input_file="$1"
    local track_num="$2"
    local output_file
    
    # Verify file exists
    if [[ ! -f "$input_file" ]]; then
        echo "❌ File not found: $input_file"
        return 1
    fi
    
    # Generate output filename
    output_file="${input_file%.*}_track${track_num}.${input_file##*.}"
    
    echo "🎵 Extracting Track $track_num"
    echo "Input:  $input_file"
    echo "Output: $output_file"
    
    # Extract specific track
    ffmpeg -i "$input_file" -map 0:$((track_num-1)) -c copy "$output_file"
}

# Convert MKV to MP4
mux_to_mp4() {
    local input_file=""
    local output_file=""
    local video_codec="libx264"
    local audio_codec="aac"
    local crf=23  # Constant Rate Factor (lower = higher quality, 18-28 is typical range)
    local preset="medium"
    local selected_tracks=""
    local force_overwrite=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i|--input)
                input_file="$2"
                shift 2
                ;;
            -o|--output)
                output_file="$2"
                shift 2
                ;;
            -vc|--video-codec)
                video_codec="$2"
                shift 2
                ;;
            -ac|--audio-codec)
                audio_codec="$2"
                shift 2
                ;;
            -crf|--quality)
                crf="$2"
                shift 2
                ;;
            -p|--preset)
                preset="$2"
                shift 2
                ;;
            -t|--tracks)
                selected_tracks="$2"
                shift 2
                ;;
            -f|--force)
                force_overwrite=true
                shift
                ;;
            *)
                # If no flag, assume it's the input file
                if [[ -z "$input_file" ]]; then
                    input_file="$1"
                else
                    echo "❌ Unknown option: $1"
                    return 1
                fi
                shift
                ;;
        esac
    done
    
    # Validate input file
    if [[ -z "$input_file" ]]; then
        echo "❌ No input file specified"
        return 1
    fi
    
    # Verify file exists
    if [[ ! -f "$input_file" ]]; then
        echo "❌ File not found: $input_file"
        return 1
    fi
    
    # Generate output filename if not specified
    if [[ -z "$output_file" ]]; then
        output_file="${input_file%.*}.mp4"
    fi
    
    # Handle force overwrite
    local overwrite_flag=""
    if [[ "$force_overwrite" == true ]]; then
        overwrite_flag="-y"
    fi
    
    # Prepare track mapping
    local track_mapping=""
    if [[ -n "$selected_tracks" ]]; then
        # Convert comma-separated list to FFmpeg track mapping
        IFS=',' read -ra TRACKS <<< "$selected_tracks"
        for track in "${TRACKS[@]}"; do
            track_mapping+=" -map 0:$((track-1))"
        done
    else
        # Map all tracks by default
        track_mapping=" -map 0"
    fi
    
    echo "🔄 Converting to MP4"
    echo "Input:  $input_file"
    echo "Output: $output_file"
    echo "Video Codec: $video_codec"
    echo "Audio Codec: $audio_codec"
    echo "Quality (CRF): $crf"
    echo "Preset: $preset"
    
    # FFmpeg conversion command
    ffmpeg $overwrite_flag -i "$input_file" \
        $track_mapping \
        -c:v "$video_codec" -preset "$preset" -crf "$crf" \
        -c:a "$audio_codec" \
        "$output_file"
}

# Main mux function
mux_main() {
    local command="${1:-help}"
    shift
    
    case "$command" in
        "help")
            show_mux_help
            ;;
        "info")
            mux_track_info "$@"
            ;;
        "list-tracks")
            mux_list_tracks "$@"
            ;;
        "extract")
            mux_extract_track "$@"
            ;;
        "to-mp4")
            mux_to_mp4 "$@"
            ;;
        *)
            echo "❌ Unknown command: $command"
            show_mux_help
            return 1
            ;;
    esac
}

# Run the main function with all arguments
mux_main "$@"
