#!/usr/bin/env bash
# screentool.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export ST_SRC=${ST_SRC:-"$HOME/src/screentool"}
export ST_DIR=${ST_DIR:-"$HOME/recordings"}

# Source the new unified environment configuration
source "$SCRIPT_DIR/env.sh"

source "$SCRIPT_DIR/screentool_audio.sh"
source "$SCRIPT_DIR/screentool_play.sh"
source "$SCRIPT_DIR/screentool_info.sh"
source "$SCRIPT_DIR/screentool_obs_helper.sh"  # OBS setup assistance
source "$SCRIPT_DIR/screentool_edit.sh"
source "$SCRIPT_DIR/screentool_final.sh"
source "$SCRIPT_DIR/screentool_list_mac.sh"
source "$SCRIPT_DIR/screentool_list_linux.sh"
source "$SCRIPT_DIR/screentool_probe.sh"

# Legacy files moved to legacy/ directory:
# - screentool_record_mac.sh (screencapture-based)
# - screentool_record_ffmpeg.sh (FFmpeg-based)  
# - screentool_video.sh (video settings - now handled by OBS)
# - screentool_macos_devices.sh (device detection - now handled by OBS)

# Remove load_env call as it's no longer needed
# load_env is now handled by sourcing env.sh

# Simple usage shown when no command or unknown command
usage() {
  usage_simple
  exit 1
}

check_dependencies() {
  case "$ST_OS_TYPE" in
    macos)
      # ffmpeg only needed for probing/analysis now
      if ! command -v ffmpeg >/dev/null; then
        echo "Note: ffmpeg not found - file analysis won't work (install with: brew install ffmpeg)"
      fi
      # cliclick only needed for area selection (optional)
      if ! command -v cliclick >/dev/null; then
        echo "Note: cliclick not found - area selection won't work (install with: brew install cliclick)"
      fi
      # Check OBS installation
      if [[ ! -f "/Applications/OBS.app/Contents/MacOS/obs" ]]; then
        echo "❌ OBS Studio not found. Please install from https://obsproject.com/"
        exit 1
      fi
      ;;
    linux)
      for dep in ffmpeg jq pactl xrandr; do
        command -v "$dep" >/dev/null || { echo "Missing $dep"; exit 1; }
      done
      ;;
  esac
}

# --- Helper Wrappers for Command-Line Mode ---
# These are needed so the main script can call the helper function.
_show_clip_info_wrapper_main() {
    show_clip_info "$1/session.meta"
}
_play_recording_wrapper_main() {
    play_recording "$1/session.meta"
}
_show_log_wrapper_main() {
    (
        source "$1/session.meta"
        local log_file="$1/$RECORDING_LOG"
        if [[ -f "$log_file" ]]; then
            cat "$log_file"
        else
            echo "Log file not found."
        fi
    )
}

# Legacy screen management functions moved to legacy/
# OBS now handles all device management through WebSocket API

# Legacy device management functions moved to legacy/screentool_macos_devices.sh
# OBS now handles all device selection through scenes and sources

clear_area() {
  unset ST_CROP_GEOMETRY
  save_env
  echo "Area selection cleared. Recording will use full screen."
}

# Missing function stubs - basic implementations
usage_simple() {
  echo "Usage: $0 {record|stop-recording|play|list|info|obs-config|help}"
  echo "Run '$0 help' for detailed help"
  echo "Note: Now uses OBS Studio binary with launch flags (simple & reliable)"
}

show_help() {
    echo "ScreenTool Recording Workflow"
    echo "============================"
    echo
    echo "OBS STUDIO INTEGRATION:"
    echo "  st obs launch       Open OBS with ScreenTool profile"
    echo "  st obs setup        Configure OBS for recording"
    echo "  st obs new-session  Create a new recording session"
    echo
    echo "RECORDING WORKFLOW:"
    echo "  1. Create Session: st obs new-session"
    echo "  2. Launch OBS:     st obs launch"
    echo "  3. Configure:      st obs setup"
    echo "  4. Record:         Use Cmd+Shift+R in OBS"
    echo
    echo "POST-RECORDING TOOLS:"
    echo "  st list            List all recordings"
    echo "  st play latest     Play most recent recording"
    echo "  st edit latest     Edit recording"
    echo "  st final latest    Export final video"
    echo
    echo "ADVANCED TOOLS:"
    echo "  st mux             Multiplex and track management"
    echo "  st obs tracks      Inspect recording tracks"
    echo
    echo "CONFIGURATION:"
    echo "  st screen          Manage screen capture settings"
    echo "  st audio           Manage audio device settings"
    echo "  st crop            Set screen capture area"
    echo
    echo "💡 Recommended Workflow:"
    echo "  1. st obs new-session"
    echo "  2. st obs launch"
    echo "  3. Start recording in OBS"
    echo "  4. st play latest"
    echo "  5. st edit latest"
    echo "  6. st final latest"
    echo
    echo "RECORDING LOCATION: $ST_DIR"
    echo
    echo "Version: $(cat "$ST_SRC/VERSION" 2>/dev/null || echo "unknown")"
}

# Stub functions for session-based features (not fully implemented)
with_sessions() {
  local action="$1"
  local session_id="$2"
  local callback="$3"
  echo "Session-based $action not yet implemented"
  return 1
}

get_session_by_number() {
  echo "Session management not yet implemented"
  return 1
}

show_clip_info() {
  local file="$1"
  if [[ -f "$file" ]]; then
    echo "File info for: $file"
    summary "$file"
  else
    echo "File not found: $file"
  fi
}

show_recording_info() {
  local target="$1"
  
  # Get recording by index
  local recording_file
  recording_file=$(get_recording_by_index "$target")
  if [[ $? -ne 0 ]]; then
    return 1
  fi
  
  local recording_dir=$(dirname "$recording_file")
  local recording_id=$(basename "$recording_dir")
  local meta_file="$recording_dir/recording.meta"
  
  echo "Recording Info: $recording_id"
  echo "=========================="
  echo
  
  # Add resolution explanation for macOS Retina displays
  echo "💡 Resolution Note:"
  echo "   macOS Retina displays capture at physical pixel resolution"
  echo "   Your logical screen: 2560x1664 (what you see)"
  echo "   Actual capture: ~3420x2144 (physical pixels - higher quality!)"
  echo
  
  # Show metadata if available
  if [[ -f "$meta_file" ]]; then
    local recording_name start_time end_time crop_geom screen_geom
    recording_name=$(grep "^RECORDING_NAME=" "$meta_file" | cut -d'"' -f2 2>/dev/null)
    start_time=$(grep "^START_TIME=" "$meta_file" | cut -d'"' -f2 2>/dev/null)
    end_time=$(grep "^END_TIME=" "$meta_file" | cut -d'"' -f2 2>/dev/null)
    crop_geom=$(grep "^CROP_GEOMETRY=" "$meta_file" | cut -d'"' -f2 2>/dev/null)
    screen_geom=$(grep "^SCREEN_GEOMETRY=" "$meta_file" | cut -d'"' -f2 2>/dev/null)
    
    echo "📋 Recording Details:"
    echo "   Name: ${recording_name:-$recording_id}"
    echo "   ID: $recording_id"
    echo "   Started: $start_time"
    echo "   Ended: ${end_time:-'(in progress)'}"
    if [[ -n "$crop_geom" ]]; then
      echo "   Crop: $crop_geom"
    fi
    if [[ -n "$screen_geom" ]]; then
      echo "   Screen: $screen_geom"
    fi
    echo
  fi
  
  # Check each file type and show stats
  local original_file="$recording_dir/recording.mov"
  local edit_file="$recording_dir/edit.mkv"
  local final_file="$recording_dir/final.mp4"
  
  echo "📁 Files in Recording:"
  echo
  
  # Original recording file
  if [[ -f "$original_file" ]]; then
    echo "🎬 ORIGINAL (recording.mov):"
    show_file_stats "$original_file"
    echo
    
    # Add detailed audio analysis for the original recording
    analyze_audio "$original_file"
    echo
  else
    echo "🎬 ORIGINAL: (not found)"
    echo
  fi
  
  # Edit file
  if [[ -f "$edit_file" ]]; then
    echo "✏️  EDIT (edit.mkv):"
    show_file_stats "$edit_file"
    
    # Show edit stats if available
    local edit_stats="$recording_dir/edit.stats"
    if [[ -f "$edit_stats" ]]; then
      echo "   Stats: $edit_stats"
      local conversion_info=$(grep -A 3 "Conversion Results" "$edit_stats" 2>/dev/null | tail -n +2)
      if [[ -n "$conversion_info" ]]; then
        echo "$conversion_info" | sed 's/^/   /'
      fi
    fi
    echo
  else
    echo "✏️  EDIT: (not created - run 'st edit $target')"
    echo
  fi
  
  # Final file  
  if [[ -f "$final_file" ]]; then
    echo "🎯 FINAL (final.mp4):"
    show_file_stats "$final_file"
    
    # Show final stats if available
    local final_stats="$recording_dir/final.stats"
    if [[ -f "$final_stats" ]]; then
      echo "   Stats: $final_stats"
      local export_info=$(grep -A 5 "Final Export Results" "$final_stats" 2>/dev/null | tail -n +2)
      if [[ -n "$export_info" ]]; then
        echo "$export_info" | sed 's/^/   /'
      fi
    fi
    echo
  else
    echo "🎯 FINAL: (not created - run 'st final $target')"
    echo
  fi
  
  # Show next steps
  echo "💡 Available Actions:"
  if [[ ! -f "$edit_file" ]]; then
    echo "   st edit $target     # Convert to editing format"
  fi
  if [[ ! -f "$final_file" ]]; then
    echo "   st final $target    # Export for distribution"
  fi
  echo "   st play $target     # Play recording"
  echo "   st delete $target   # Delete recording"
}

# Helper function to show file statistics
show_file_stats() {
  local file="$1"
  local file_size duration width height fps codec
  
  # Get file size
  file_size=$(stat -f "%z" "$file" 2>/dev/null || stat --printf="%s" "$file" 2>/dev/null)
  if [[ -n "$file_size" ]]; then
    file_size=$(echo "$file_size" | awk '{printf "%.1fMB", $1/1024/1024}')
  else
    file_size="unknown"
  fi
  
  # Get video info using ffprobe
  if command -v ffprobe >/dev/null; then
    local probe_output
    probe_output=$(ffprobe -v quiet -print_format json -show_format -show_streams "$file" 2>/dev/null)
    
    if [[ -n "$probe_output" ]] && command -v jq >/dev/null; then
      duration=$(echo "$probe_output" | jq -r '.format.duration // "unknown"')
      width=$(echo "$probe_output" | jq -r '.streams[] | select(.codec_type=="video") | .width // 0' | head -1)
      height=$(echo "$probe_output" | jq -r '.streams[] | select(.codec_type=="video") | .height // 0' | head -1)
      fps=$(echo "$probe_output" | jq -r '.streams[] | select(.codec_type=="video") | .r_frame_rate // "0/1"' | head -1 | awk -F'/' '{if($2>0) printf "%.1f", $1/$2; else print "0"}')
      codec=$(echo "$probe_output" | jq -r '.streams[] | select(.codec_type=="video") | .codec_name // "unknown"' | head -1)
      
      # Format duration
      if [[ "$duration" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        duration=$(printf "%.1fs" "$duration")
      fi
    fi
  fi
  
  echo "   Size: $file_size"
  if [[ -n "$duration" && "$duration" != "unknown" ]]; then
    echo "   Duration: $duration"
  fi
  if [[ -n "$width" && "$width" != "0" ]]; then
    echo "   Resolution: ${width}x${height}"
    
    # Add Retina scaling info for macOS
    if [[ "$ST_OS_TYPE" == "macos" ]] && [[ -n "$SCREEN_GEOMETRY" ]]; then
      local logical_width logical_height
      logical_width=$(echo "$SCREEN_GEOMETRY" | sed 's/\([0-9]*\)x\([0-9]*\)+.*/\1/')
      logical_height=$(echo "$SCREEN_GEOMETRY" | sed 's/\([0-9]*\)x\([0-9]*\)+.*/\2/')
      
      if [[ "$width" != "$logical_width" ]] || [[ "$height" != "$logical_height" ]]; then
        local scale_x scale_y
        scale_x=$(echo "$width $logical_width" | awk '{printf "%.2f", $1/$2}')
        scale_y=$(echo "$height $logical_height" | awk '{printf "%.2f", $1/$2}')
        echo "   Logical: ${logical_width}x${logical_height} (${scale_x}x Retina scaling)"
      fi
    fi
  fi
  if [[ -n "$fps" && "$fps" != "0" ]]; then
    echo "   FPS: $fps"
  fi
  if [[ -n "$codec" && "$codec" != "unknown" ]]; then
    echo "   Codec: $codec"
  fi
  echo "   Path: $(basename "$file")"
}

# Platform-specific listing functions
list_recordings() {
  local format="$1"
  case "$ST_OS_TYPE" in
    macos)
      list_recordings_mac "$format"
      ;;
    linux)
      list_recordings_linux "$format"
      ;;
    *)
      echo "Unsupported OS: $ST_OS_TYPE"
      ;;
  esac
}

summary_recordings() {
  case "$ST_OS_TYPE" in
    macos)
      summary_recordings_mac
      ;;
    linux)
      summary_recordings_linux
      ;;
    *)
      echo "Unsupported OS: $ST_OS_TYPE"
      ;;
  esac
}

# Legacy function for compatibility
list_recordings_legacy() {
  local format="$1"
  echo "Available recordings:"
  echo "===================="
  
  local recordings=()
  local index=1
  
  # Find all recording directories (numeric IDs)
  while IFS= read -r -d '' recording_dir; do
    if [[ -d "$recording_dir" ]] && [[ $(basename "$recording_dir") =~ ^[0-9]+$ ]]; then
      recordings+=("$recording_dir")
    fi
  done < <(find "$ST_DIR" -maxdepth 1 -type d -print0 2>/dev/null | sort -z)
  
  if [[ ${#recordings[@]} -eq 0 ]]; then
    echo "No recordings found in $ST_DIR"
    return
  fi
  
  # List with index numbers
  for recording_dir in "${recordings[@]}"; do
    local recording_id=$(basename "$recording_dir")
    local recording_file="$recording_dir/recording.mov"
    local meta_file="$recording_dir/recording.meta"
    local name="$recording_id"
    local size=""
    local duration=""
    local latest_marker=""
    
    # Check if this is the latest recording
    if [[ -L "$ST_DIR/latest" ]]; then
      local latest_target=$(readlink "$ST_DIR/latest")
      if [[ "$latest_target" == "$recording_id" ]]; then
        latest_marker=" ← latest"
      fi
    fi
    
    # Get recording name from metadata
    if [[ -f "$meta_file" ]]; then
      local recording_name
      recording_name=$(grep "^RECORDING_NAME=" "$meta_file" | cut -d'"' -f2 2>/dev/null)
      if [[ -n "$recording_name" ]]; then
        name="$recording_name ($recording_id)"
      fi
    fi
    
    # Get file info if recording exists
    if [[ -f "$recording_file" ]]; then
      # Get file size
      if command -v stat >/dev/null; then
        size=$(stat -f "%z" "$recording_file" 2>/dev/null || stat --printf="%s" "$recording_file" 2>/dev/null)
        if [[ -n "$size" ]]; then
          size=$(echo "$size" | awk '{printf "%.1fMB", $1/1024/1024}')
        fi
      fi
      
      # Get duration if possible
      if command -v ffprobe >/dev/null; then
        duration=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$recording_file" 2>/dev/null)
        if [[ -n "$duration" ]] && [[ "$duration" =~ ^[0-9]+\.?[0-9]*$ ]]; then
          duration=$(printf "%.1fs" "$duration")
        else
          duration=""
        fi
      fi
    else
      size="(no file)"
      duration=""
    fi
    
    # Format output
    if [[ "$format" == "detailed" ]]; then
      printf "%2d) %-35s %8s %8s%s\n" "$index" "$name" "$size" "$duration" "$latest_marker"
    else
      printf "%2d) %s%s\n" "$index" "$name" "$latest_marker"
    fi
    
    ((index++))
  done
  
  echo
  echo "Use: st play <number> or st delete <number>"
  echo "Latest recording: st play latest (or: latest/recording.mkv)"
}

# Get recording by index number
get_recording_by_index() {
  local target_index="$1"
  local file_type="${2:-auto}"  # auto, recording, edit, finaldelete the
  echo "DEBUG: get_recording_by_index called with index: $target_index, type: $file_type"
  local recordings=()
  local index=1
  
  echo "DEBUG: Finding recording directories in $ST_DIR"
  # Find all recording directories (same logic as list_recordings)
  while IFS= read -r -d '' recording_dir; do
    echo "DEBUG: Found directory: $recording_dir"
    if [[ -d "$recording_dir" ]] && [[ $(basename "$recording_dir") =~ ^[0-9]+$ ]]; then
      recordings+=("$recording_dir")
      echo "DEBUG: Added to recordings array: $recording_dir"
    fi
  done < <(find "$ST_DIR" -maxdepth 1 -type d -print0 2>/dev/null | sort -z)
  
  echo "DEBUG: Found ${#recordings[@]} recordings"
  
  if [[ ${#recordings[@]} -eq 0 ]]; then
    echo "No recordings found"
    return 1
  fi
  
  if [[ "$target_index" -lt 1 ]] || [[ "$target_index" -gt ${#recordings[@]} ]]; then
    echo "Invalid index: $target_index (valid range: 1-${#recordings[@]})"
    return 1
  fi
  
  # Get the recording directory
  local recording_dir="${recordings[$((target_index - 1))]}"
  
  # Determine which file to return
  case "$file_type" in
    recording)
      # Look for recording files in order of preference
      if [[ -f "$recording_dir/recording.mov" ]]; then
        echo "$recording_dir/recording.mov"
      elif [[ -f "$recording_dir/recording.mkv" ]]; then
        echo "$recording_dir/recording.mkv"
      else
        # Look for timestamped files (OBS format)
        local mkv_file
        mkv_file=$(find "$recording_dir" -name "*.mkv" -type f | head -1)
        if [[ -n "$mkv_file" ]]; then
          echo "$mkv_file"
        else
          echo "No recording file found in $recording_dir"
          return 1
        fi
      fi
      ;;
    edit)
      echo "$recording_dir/edit.mkv"
      ;;
    final)
      echo "$recording_dir/final.mp4"
      ;;
    auto|*)
      # Auto-select best available file (final > edit > recording)
      if [[ -f "$recording_dir/final.mp4" ]]; then
        echo "$recording_dir/final.mp4"
      elif [[ -f "$recording_dir/edit.mkv" ]]; then
        echo "$recording_dir/edit.mkv"
      elif [[ -f "$recording_dir/recording.mov" ]]; then
        echo "$recording_dir/recording.mov"
      elif [[ -f "$recording_dir/recording.mkv" ]]; then
        echo "$recording_dir/recording.mkv"
      else
        # Look for any video file in the recording directory
        local video_file
        video_file=$(find "$recording_dir" \( -name "*.mkv" -o -name "*.mov" -o -name "*.mp4" \) | head -1)
        
        if [[ -n "$video_file" ]]; then
          echo "$video_file"
          return 0
        fi
      fi
      ;;
  esac
  return 0
}

play_audio() {
  echo "Audio playback not yet implemented"
}

show_recording_status() {
  echo "Recording Status"
  echo "================"
  echo "Current configuration:"
  env_display
}

delete_session() {
  echo "Legacy session deletion not yet implemented"
}

delete_recording() {
  local target="$1"
  
  # Handle range syntax (e.g., "1-5" or "2-4")
  if [[ "$target" =~ ^([0-9]+)-([0-9]+)$ ]]; then
    local start="${BASH_REMATCH[1]}"
    local end="${BASH_REMATCH[2]}"
    
    if [[ $start -gt $end ]]; then
      echo "Invalid range: $target (start must be <= end)"
      return 1
    fi
    
    echo "Delete recordings $start through $end:"
    
    # Get list of recordings to delete
    local recordings_to_delete=()
    local recordings_info=()
    
    # Get all recordings first
    local all_recordings=()
    while IFS= read -r -d '' recording_dir; do
      if [[ -d "$recording_dir" ]] && [[ $(basename "$recording_dir") =~ ^[0-9]+$ ]]; then
        all_recordings+=("$recording_dir")
      fi
    done < <(find "$ST_DIR" -maxdepth 1 -type d -print0 2>/dev/null | sort -z)
    
    for (( i=start; i<=end; i++ )); do
      if [[ $i -le ${#all_recordings[@]} ]]; then
        local recording_dir="${all_recordings[$((i - 1))]}"
        recordings_to_delete+=("$recording_dir")
        local recording_id=$(basename "$recording_dir")
        local name="$recording_id"
        
        # Get recording name from metadata if available
        local meta_file="$recording_dir/recording.meta"
        if [[ -f "$meta_file" ]]; then
          local recording_name
          recording_name=$(grep "^RECORDING_NAME=" "$meta_file" | cut -d'"' -f2 2>/dev/null)
          if [[ -n "$recording_name" ]]; then
            name="$recording_name ($recording_id)"
          fi
        fi
        
        recordings_info+=("$i) $name")
      else
        echo "Warning: Recording $i not found, skipping"
      fi
    done
    
    if [[ ${#recordings_to_delete[@]} -eq 0 ]]; then
      echo "No recordings found in range $target"
      return 1
    fi
    
    echo
    echo "Recordings to delete:"
    for info in "${recordings_info[@]}"; do
      echo "  $info"
    done
    echo
    read -rp "Delete ${#recordings_to_delete[@]} recordings? (y/N): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      local deleted_count=0
      local failed_count=0
      
      for recording_dir in "${recordings_to_delete[@]}"; do
        local recording_id=$(basename "$recording_dir")
        
        if rm -rf "$recording_dir" 2>/dev/null; then
          echo "✓ Deleted recording: $recording_id"
          ((deleted_count++))
        else
          echo "✗ Failed to delete: $recording_id"
          ((failed_count++))
        fi
      done
      
      echo
      echo "Deletion summary: $deleted_count deleted, $failed_count failed"
      
      # Update latest symlink if needed
      update_latest_symlink
      
    else
      echo "Delete cancelled"
    fi
    
    return 0
  fi
  
  # Single recording deletion (existing logic)
  local file
  
  if [[ "$target" =~ ^[0-9]+$ ]]; then
    # Get recordings list directly
    local recordings=()
    while IFS= read -r -d '' recording_dir; do
      if [[ -d "$recording_dir" ]] && [[ $(basename "$recording_dir") =~ ^[0-9]+$ ]]; then
        recordings+=("$recording_dir")
      fi
    done < <(find "$ST_DIR" -maxdepth 1 -type d -print0 2>/dev/null | sort -z)
    
    if [[ ${#recordings[@]} -eq 0 ]]; then
      echo "No recordings found"
      return 1
    fi
    
    if [[ "$target" -lt 1 ]] || [[ "$target" -gt ${#recordings[@]} ]]; then
      echo "Invalid index: $target (valid range: 1-${#recordings[@]})"
      return 1
    fi
    
    # Just delete the directory - that's it!
    local recording_dir="${recordings[$((target - 1))]}"
    local recording_id=$(basename "$recording_dir")
    
    # Get name from metadata if available
    local name="$recording_id"
    local meta_file="$recording_dir/recording.meta"
    if [[ -f "$meta_file" ]]; then
      local recording_name
      recording_name=$(grep "^RECORDING_NAME=" "$meta_file" | cut -d'"' -f2 2>/dev/null)
      if [[ -n "$recording_name" ]]; then
        name="$recording_name ($recording_id)"
      fi
    fi
    
    echo "Delete recording: $name"
    read -rp "Are you sure? (y/N): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      if rm -rf "$recording_dir" 2>/dev/null; then
        echo "✓ Deleted recording: $name"
        update_latest_symlink
        return 0
      else
        echo "✗ Failed to delete: $name"
        return 1
      fi
    else
      echo "Delete cancelled"
      return 0
    fi
  else
    echo "Invalid target: $target"
    echo "Use a number (e.g., '5') or range (e.g., '1-10')"
    return 1
  fi
}

# Helper function to update latest symlink after deletions
update_latest_symlink() {
  local latest_link="$ST_DIR/latest"
  
  # Check if current latest still exists
  if [[ -L "$latest_link" ]]; then
    local current_latest=$(readlink "$latest_link")
    if [[ ! -d "$ST_DIR/$current_latest" ]]; then
      # Current latest was deleted, find new latest
      local newest_recording
      newest_recording=$(find "$ST_DIR" -maxdepth 1 -type d -name "[0-9]*" 2>/dev/null | sort -n | tail -1)
      
      if [[ -n "$newest_recording" ]]; then
        local newest_id=$(basename "$newest_recording")
        rm -f "$latest_link"
        ln -sf "$newest_id" "$latest_link"
        echo "Updated latest → $newest_id"
      else
        rm -f "$latest_link"
        echo "No recordings left - removed latest symlink"
      fi
    fi
  fi
}

repl() {
  echo "Interactive REPL mode not yet implemented"
  echo "For now, use individual commands like:"
  echo "  ./screentool.sh record demo.mp4"
  echo "  ./screentool.sh play latest.mp4"
  echo "  ./screentool.sh info"
}

setup_crop_interactive() {
  echo "Interactive Crop Setup"
  echo "====================="
  echo
  
  # Show current screen info
  if [[ -n "$SCREEN_GEOMETRY" ]]; then
    local screen_w screen_h
    screen_w=$(echo "$SCREEN_GEOMETRY" | sed 's/\([0-9]*\)x\([0-9]*\)+.*/\1/')
    screen_h=$(echo "$SCREEN_GEOMETRY" | sed 's/\([0-9]*\)x\([0-9]*\)+.*/\2/')
    echo "Current screen: ${screen_w}x${screen_h}"
  else
    echo "Screen geometry not detected - run 'st screen <number>' first"
    return 1
  fi
  
  # Show current crop if set
  if [[ -n "$ST_CROP_GEOMETRY" ]]; then
    echo "Current crop: $ST_CROP_GEOMETRY"
    echo
  fi
  
  echo "Choose crop setup method:"
  echo "1) Common presets (1080p, 720p, etc.)"
  echo "2) Enter custom dimensions"
  echo "3) Keep current settings"
  echo "4) Clear crop (full screen)"
  echo
  read -rp "Choose option (1-4): " choice
  
  case "$choice" in
    1)
      setup_crop_presets
      ;;
    2)
      setup_crop_custom
      ;;
    3)
      echo "Keeping current crop settings"
      ;;
    4)
      clear_area
      ;;
    *)
      echo "Invalid choice"
      ;;
  esac
}

setup_crop_presets() {
  echo
  echo "Common Recording Presets:"
  echo "1) 1920x1080 (1080p Full HD)"
  echo "2) 1280x720  (720p HD)"
  echo "3) 1600x900  (16:9 Medium)"
  echo "4) 1024x768  (4:3 Standard)"
  echo "5) 800x600   (4:3 Small)"
  echo
  read -rp "Choose preset (1-5): " preset
  
  local width height x y
  case "$preset" in
    1) width=1920; height=1080 ;;
    2) width=1280; height=720 ;;
    3) width=1600; height=900 ;;
    4) width=1024; height=768 ;;
    5) width=800; height=600 ;;
    *) echo "Invalid preset"; return 1 ;;
  esac
  
  echo
  echo "Position the ${width}x${height} recording area:"
  read -rp "X offset (0 for left edge): " x
  read -rp "Y offset (0 for top edge): " y
  
  # Default to 0 if empty
  x=${x:-0}
  y=${y:-0}
  
  # Validate inputs
  if [[ ! "$x" =~ ^[0-9]+$ ]] || [[ ! "$y" =~ ^[0-9]+$ ]]; then
    echo "Invalid coordinates"
    return 1
  fi
  
  local crop_geom="${width}x${height}+${x}+${y}"
  export ST_CROP_GEOMETRY="$crop_geom"
  save_env
  echo "✓ Crop set to: $crop_geom"
}

setup_crop_custom() {
  echo
  echo "Enter custom crop dimensions:"
  read -rp "Width: " width
  read -rp "Height: " height
  read -rp "X offset (default 0): " x
  read -rp "Y offset (default 0): " y
  
  # Default to 0 if empty for offsets
  x=${x:-0}
  y=${y:-0}
  
  # Validate inputs
  if [[ ! "$width" =~ ^[0-9]+$ ]] || [[ ! "$height" =~ ^[0-9]+$ ]] || 
     [[ ! "$x" =~ ^[0-9]+$ ]] || [[ ! "$y" =~ ^[0-9]+$ ]]; then
    echo "Invalid dimensions - must be numbers"
    return 1
  fi
  
  local crop_geom="${width}x${height}+${x}+${y}"
  export ST_CROP_GEOMETRY="$crop_geom"
  save_env
  echo "✓ Crop set to: $crop_geom"
}

main() {
  local cmd
  cmd="${1:-}"
  [[ -n "$cmd" ]] && shift

  case "$cmd" in
    "")
      # No command provided
      usage
      ;;
    record|rec)
      echo "🎬 Recording with OBS Studio"
      echo "============================"
      echo
      echo "❌ Automated recording has been moved to legacy"
      echo "💡 Use OBS Studio directly for recording:"
      echo
      echo "1. Launch OBS: st obs launch"
      echo "2. Configure your profile: st obs setup"
      echo "3. Start recording in OBS (Cmd+Shift+R)"
      echo "4. Files will be saved to: $ST_DIR"
      echo
      echo "For setup help: st obs setup"
      ;;
    record-legacy)
      # Legacy recording methods (for fallback/testing)
      echo "Legacy recording methods available in legacy/ directory"
      echo "Use 'record' for OBS-based recording (recommended)"
      ;;
    obs|obs-help)
      # OBS helper commands
      obs_help "${1:-}"
      ;;
    obs-status)
      # Show OBS status
      obs_help "status"
      ;;
    obs-config|obs-setup)
      # Show OBS setup guide
      obs_help "setup"
      ;;
    obs-launch)
      # Launch OBS
      obs_help "launch"
      ;;
    edit)
      edit_mov "${1:-}"
      ;;
    edit-720p)
      # Edit with 720p target
      EDIT_TARGET_WIDTH=1280 EDIT_TARGET_HEIGHT=720 edit_mov "${1:-}"
      ;;
    edit-1080p)
      # Edit with 1080p target  
      EDIT_TARGET_WIDTH=1920 EDIT_TARGET_HEIGHT=1080 edit_mov "${1:-}"
      ;;
    edit-4k)
      # Edit with 4K target (no downscaling)
      EDIT_TARGET_WIDTH=3840 EDIT_TARGET_HEIGHT=2160 edit_mov "${1:-}"
      ;;
    final)
      final_export "${1:-}"
      ;;
    summary)
      summary_recordings
      ;;
    probe)
      if [[ -n "${1:-}" ]]; then
        screentool_probe "${1:-}" "${2:-summary}"
      else
        echo "Usage: st probe <file> [summary|json|raw]"
        echo "Examples:"
        echo "  st probe recording.mov       # Clean summary"
        echo "  st probe edit.mkv json       # JSON output"
        echo "  st probe final.mp4 raw       # Raw ffprobe"
      fi
      ;;
    screen-resolution)
      echo "Current Screen Resolution Detection"
      echo "=================================="
      echo
      echo "🖥️  System Profiler (native resolutions):"
      system_profiler SPDisplaysDataType | grep -A 1 -B 1 "Resolution:"
      echo
      echo "📐 Desktop Bounds (actual current):"
      local bounds
      bounds=$(osascript -e 'tell application "Finder" to get bounds of window of desktop' 2>/dev/null)
      if [[ -n "$bounds" ]]; then
        local width height
        width=$(echo "$bounds" | awk -F', ' '{print $3}')
        height=$(echo "$bounds" | awk -F', ' '{print $4}')
        echo "   Current resolution: ${width}x${height}"
        echo "   (This is what you actually see and should use)"
      else
        echo "   Could not detect current resolution"
      fi
      echo
      echo "⚙️  Configured:"
      echo "   SCREEN_GEOMETRY: ${SCREEN_GEOMETRY:-not set}"
      echo "   ST_CROP_GEOMETRY: ${ST_CROP_GEOMETRY:-not set}"
      ;;
    audio-check)
      check_audio_recording_setup
      ;;
    audio-analyze)
      if [[ -n "$1" ]]; then
        analyze_audio "$1"
      else
        echo "Usage: st audio-analyze <file>"
      fi
      ;;
    audio-voice-detect)
      audio_voice_detect "$1"
      ;;
    audio-silence-detect)
      audio_silence_detect "$1"
      ;;
    audio-normalize)
      audio_normalize "$1"
      ;;
    audio-denoise)
      audio_denoise "$1"
      ;;
    audio-extract)
      audio_extract "$1"
      ;;
    audio-mix)
      audio_mix "$1" "$2"
      ;;
    test-audio)
      echo "🧪 Testing screencapture audio recording..."
      echo "This will record for 3 seconds to test audio capture"
      echo "Press Enter to start, or Ctrl+C to cancel"
      read -r
      
      local test_file="/tmp/screentool_test_$(date +%s).mov"
      echo "Recording 3-second test to: $test_file"
      
      if screencapture -V 3 -v "$test_file"; then
        echo "✅ Recording completed. Analyzing..."
        ./screentool.sh probe "$test_file"
        echo
        echo "🎬 Test file created: $test_file"
        echo "🧹 Clean up: rm '$test_file'"
      else
        echo "❌ Recording failed"
      fi
      ;;
    play)
      if [[ -n "$1" ]]; then
        # Check if argument is "latest", a number (index), or filename
        if [[ "$1" == "latest" ]]; then
          # Play latest recording
          local latest_link="$ST_DIR/latest"
          if [[ -L "$latest_link" ]]; then
            local latest_recording=$(readlink "$latest_link")

            local recording_dir="$ST_DIR/$latest_recording"
            local latest_file
            
            # Look for recording files in order of preference
            if [[ -f "$recording_dir/recording.mkv" ]]; then
              latest_file="$recording_dir/recording.mkv"
            elif [[ -f "$recording_dir/recording.mov" ]]; then
              latest_file="$recording_dir/recording.mov"
            else
              # Look for any video file (OBS timestamped files)
              latest_file=$(find "$recording_dir" -name "*.mkv" -o -name "*.mov" -o -name "*.mp4" | head -1)
            fi
            
            if [[ -f "$latest_file" ]]; then
              echo "Playing latest recording: $latest_recording"
              echo "File: $(basename "$latest_file")"
              if command -v ffplay >/dev/null; then
                ffplay "$latest_file"
              elif command -v open >/dev/null; then
                open "$latest_file"
              else
                echo "No media player found. Install ffplay or use system default."
              fi
            else
              echo "Latest recording file not found: $latest_file"
            fi
          else
            echo "No latest recording found"
            echo "Run 'st list' to see available recordings"
          fi
        elif [[ "$1" =~ ^[0-9]+$ ]]; then
          # Play by index number (auto-select best file)
          local file
          file=$(get_recording_by_index "$1" "auto")
          if [[ $? -eq 0 ]] && [[ -f "$file" ]]; then
            echo "Playing: $(basename "$(dirname "$file")")/$(basename "$file")"
            if command -v ffplay >/dev/null; then
              ffplay "$file"
            elif command -v open >/dev/null; then
              open "$file"
            else
              echo "No media player found. Install ffplay or use system default."
            fi
          else
            echo "Recording $1 not found or no playable files available"
          fi
        else
          # Play by filename/path
          local file="$1"
          if [[ ! "$file" = /* ]]; then
            file="$ST_DIR/$file"
          fi
          if [[ -f "$file" ]]; then
            echo "Playing: $(basename "$file")"
            if command -v ffplay >/dev/null; then
              ffplay "$file"
            elif command -v open >/dev/null; then
              open "$file"
            else
              echo "No media player found. Install ffplay or use system default."
            fi
          else
            echo "File not found: $file"
            echo "Run 'st list' to see available recordings"
          fi
        fi
      else
        # No argument - play latest recording
        local latest_link="$ST_DIR/latest"
        if [[ -L "$latest_link" ]]; then
          local latest_recording=$(readlink "$latest_link")
          local latest_file="$ST_DIR/$latest_recording/recording.mkv"
          if [[ -f "$latest_file" ]]; then
            echo "Playing latest recording: $latest_recording"
            if command -v ffplay >/dev/null; then
              ffplay "$latest_file"
            elif command -v open >/dev/null; then
              open "$latest_file"
            else
              echo "No media player found. Install ffplay or use system default."
            fi
          else
            echo "Latest recording file not found: $latest_file"
          fi
        else
          echo "No latest recording found"
          echo "Run 'st list' to see available recordings"
        fi
      fi
      ;;
    play-recording)
      # Force play original recording.mov
      if [[ -n "$1" ]] && [[ "$1" =~ ^[0-9]+$ ]]; then
        local file
        file=$(get_recording_by_index "$1" "recording")
        if [[ $? -eq 0 ]] && [[ -f "$file" ]]; then
          echo "Playing original recording: $(basename "$(dirname "$file")")/$(basename "$file")"
          if command -v ffplay >/dev/null; then
            ffplay "$file"
          elif command -v open >/dev/null; then
            open "$file"
          fi
        else
          echo "Recording $1 not found"
        fi
      else
        echo "Usage: st play-recording <number>"
      fi
      ;;
    play-edit)
      # Force play edit.mkv
      if [[ -n "$1" ]] && [[ "$1" =~ ^[0-9]+$ ]]; then
        local file
        file=$(get_recording_by_index "$1" "edit")
        if [[ $? -eq 0 ]] && [[ -f "$file" ]]; then
          echo "Playing edit version: $(basename "$(dirname "$file")")/$(basename "$file")"
          if command -v ffplay >/dev/null; then
            ffplay "$file"
          elif command -v open >/dev/null; then
            open "$file"
          fi
        else
          echo "Edit file for recording $1 not found"
        fi
      else
        echo "Usage: st play-edit <number>"
      fi
      ;;
    play-final)
      # Force play final.mp4
      if [[ -n "$1" ]] && [[ "$1" =~ ^[0-9]+$ ]]; then
        local file
        file=$(get_recording_by_index "$1" "final")
        if [[ $? -eq 0 ]] && [[ -f "$file" ]]; then
          echo "Playing final version: $(basename "$(dirname "$file")")/$(basename "$file")"
          if command -v ffplay >/dev/null; then
            ffplay "$file"
          elif command -v open >/dev/null; then
            open "$file"
          fi
        else
          echo "Final file for recording $1 not found"
        fi
      else
        echo "Usage: st play-final <number>"
      fi
      ;;
    play-audio)
      play_audio "${@:2}"
      ;;
    repl)
      repl
      ;;
    delete|rm)
      if [[ -n "$1" ]]; then
        delete_recording "$1"
      else
        echo "Usage: st delete <number|range|filename>"
        echo "Examples:"
        echo "  st delete 2          # Delete recording 2"
        echo "  st delete 1-5        # Delete recordings 1 through 5"
        echo "  st delete demo.mov   # Delete by filename"
        echo "Run 'st list' to see available recordings"
      fi
        ;;
    list)
      local list_type="${1:-recordings}"
      case "$list_type" in
        recordings|dirs|directories)
          list_recordings "table"
          ;;
        detailed)
          list_recordings "detailed"
          ;;
        audio|audio-inputs)
          echo "Audio device management now handled by OBS"
          echo "Configure audio sources directly in OBS Studio"
          echo "Run 'st obs-config' for setup guidance"
          ;;
        screens)
          echo "Screen management now handled by OBS"
          echo "Configure display capture directly in OBS Studio"
          echo "Run 'st obs-config' for setup guidance"
          ;;
        *)
          # Default to recordings
          list_recordings "table"
          ;;
      esac
      ;;
    ls)
      if [[ "$1" == "-l" ]]; then
        list_recordings "detailed"
      else
        list_recordings "table"
      fi
      ;;
    info)
      if [[ "${1:-}" =~ ^[0-9]+$ ]]; then
        # Show recording info by index number
        show_recording_info "${1:-}"
        exit 0
      fi
      # If no arguments, show current configuration
      if [[ -z "${1:-}" ]]; then
        echo "Current Configuration:"
        echo "====================="
        echo
        echo "Screen Settings:"
        echo "  Current screen: ${ST_AVFOUNDATION_VIDEO_DEVICE:-0}"
        echo "  Screen geometry: ${SCREEN_GEOMETRY:-not detected}"
        echo
        echo "Audio Settings:"
        echo "  Current microphone: ${ST_AVFOUNDATION_AUDIO_DEVICE:-0}"
        echo "  Audio codec: ${AUDIO_CODEC:-pcm_s16le}"
        echo "  Sample rate: ${AUDIO_SAMPLERATE:-48000} Hz"
        echo "  Channels: ${AUDIO_CHANNELS:-1} (1=mono, 2=stereo)"
        echo
        echo "Video Settings:"
        echo "  Video codec: ${VIDEO_CODEC:-libx264}"
        echo "  Framerate: ${FRAMERATE:-30} fps"
        echo "  CRF quality: ${CRF:-23}"
        echo "  Preset: ${PRESET:-ultrafast}"
        echo
        echo "Recording Area:"
        if [[ -n "$ST_CROP_GEOMETRY" ]]; then
          echo "  Crop geometry: $ST_CROP_GEOMETRY (area recording enabled)"
          width=$(echo "$ST_CROP_GEOMETRY" | sed 's/\([0-9]*\)x\([0-9]*\)+.*/\1/')
          height=$(echo "$ST_CROP_GEOMETRY" | sed 's/\([0-9]*\)x\([0-9]*\)+.*/\2/')
          echo "  Recording size: ${width}x${height}"
        else
          echo "  Recording full screen"
          if [[ -n "$SCREEN_GEOMETRY" ]]; then
            width=$(echo "$SCREEN_GEOMETRY" | sed 's/\([0-9]*\)x\([0-9]*\)+.*/\1/')
            height=$(echo "$SCREEN_GEOMETRY" | sed 's/\([0-9]*\)x\([0-9]*\)+.*/\2/')
            echo "  Recording size: ${width}x${height}"
          fi
        fi
        echo
        echo "Storage:"
        echo "  Recordings directory: $ST_DIR"
        echo "  Source directory: $ST_SRC"
        exit 0
      fi
      # This part handles legacy `info <meta_file>` calls, can be kept for now
      local subcategory="$1"
      case "$subcategory" in
        audio|video|stitch|meta)
          local meta_file="$2"
          if [[ -z "$meta_file" ]]; then
            echo "Usage: st info $subcategory <meta_file>"
            exit 1
          fi
          "info_$subcategory" "$meta_file"
          ;;
        *)
          # Default info behavior - show comprehensive information
          show_clip_info "${@}"
          ;;
      esac
      ;;
    review)
      local session_number="$1"
      if [[ -z "$session_number" ]]; then
        echo "Usage: st review <session_number>"
        echo "Example: st review 3"
        exit 1
      fi
      review_session "$session_number"
      ;;
    summary)
      show_clip_info "${@}"
      ;;
    geometry)
      ascii_geometry
      ;;
    help)
      # Use the new layered help system
      show_help "${1:-}"
      ;;
    screen|screens)
      echo "Screen management now handled by OBS Studio"
      echo "Configure display capture directly in OBS Studio"
      echo "Use 'st obs-config' for guided setup"
      ;;
    audio)
      echo "Audio device management now handled by OBS Studio"
      echo "Configure audio sources directly in OBS Studio"
      echo "Use 'st obs-config' for guided setup"
      ;;
    clear-area)
      clear_area
      ;;
    crop)
      if [[ -n "$1" ]]; then
        # Set crop geometry directly
        export ST_CROP_GEOMETRY="$1"
        save_env
        echo "✓ Crop geometry set to: $1"
        echo "💡 Note: OBS will use this for scene configuration"
      else
        # Interactive crop setup
        setup_crop_interactive
      fi
      ;;
    setup-crop)
      setup_crop_interactive
      ;;
    size)
      if [[ -n "$ST_CROP_GEOMETRY" ]]; then
        # Parse crop geometry to get dimensions
        width=$(echo "$ST_CROP_GEOMETRY" | sed 's/\([0-9]*\)x\([0-9]*\)+.*/\1/')
        height=$(echo "$ST_CROP_GEOMETRY" | sed 's/\([0-9]*\)x\([0-9]*\)+.*/\2/')
        echo "Recording dimensions: ${width}x${height} (cropped area)"
        echo "Crop geometry: $ST_CROP_GEOMETRY"
        echo "💡 OBS will use this for display capture configuration"
      elif [[ -n "$SCREEN_GEOMETRY" ]]; then
        # Parse screen geometry to get dimensions
        width=$(echo "$SCREEN_GEOMETRY" | sed 's/\([0-9]*\)x\([0-9]*\)+.*/\1/')
        height=$(echo "$SCREEN_GEOMETRY" | sed 's/\([0-9]*\)x\([0-9]*\)+.*/\2/')
        echo "Recording dimensions: ${width}x${height} (full screen)"
        echo "Screen geometry: $SCREEN_GEOMETRY"
      else
        echo "No screen geometry detected"
        echo "OBS will use default display capture settings"
      fi
      ;;
    save)
      save_env
      ;;
    load)
      load_env
      ;;
    env)
      env_display
      ;;
    status)
      show_recording_status
      ;;
    debug-screen)
      echo "Screen Resolution Debug"
      echo "======================="
      echo
      echo "🖥️  System Profiler Display Info:"
      system_profiler SPDisplaysDataType | grep -A 10 -B 2 "Resolution:"
      echo
      echo "📺 AVFoundation Video Devices:"
      ffmpeg -f avfoundation -list_devices true -i "" 2>&1 | grep -A 10 "video devices"
      echo
      echo "⚙️  Current Configuration:"
      echo "   ST_AVFOUNDATION_VIDEO_DEVICE: $ST_AVFOUNDATION_VIDEO_DEVICE"
      echo "   SCREEN_GEOMETRY: $SCREEN_GEOMETRY"
      echo "   ST_CROP_GEOMETRY: $ST_CROP_GEOMETRY"
      echo
      echo "🔍 Test what screencapture actually captures:"
      echo "   Try: screencapture -V 1 test-capture.mov"
      echo "   Then: ffprobe test-capture.mov"
      ;;
    cleanup)
      if [[ -n "$1" ]]; then
        # Check if it's a session number (directory-based) or session name (file-based)
        if [[ "$1" =~ ^[0-9]+$ ]]; then
          # Directory-based cleanup
          local session_dir
          session_dir=$(get_session_by_number "$1")
          if [[ $? -eq 0 ]]; then
            cleanup_session "$session_dir" "${2:-true}"
          else
            echo "$session_dir"  # Error message
          fi
        else
          # Legacy file-based cleanup
          cleanup_session_files "$1" "$2" "$3"
        fi
      else
        show_cleanup_help
      fi
      ;;
    cleanup-all)
      if [[ "$1" == "--yes" ]]; then
        cleanup_all_intermediate_files "yes"
      else
        cleanup_all_intermediate_files "prompt"
      fi
      ;;
    *)
      usage
      ;;
  esac
}

main "$@"
