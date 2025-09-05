#!/usr/bin/env bash
# screentool_record_mac.sh
# macOS-specific recording using native screencapture command
#
# UI Cropping Configuration:
# - ST_CROP_UI_ELEMENTS: Set to "true" to exclude menu bar and dock
# - ST_MENU_BAR_HEIGHT: Height of menu bar in pixels (default: 28)
# - ST_DOCK_HEIGHT: Height of dock in pixels (default: 70)
#
# To adjust UI dimensions for your setup:
#   export ST_MENU_BAR_HEIGHT=24    # For smaller menu bar
#   export ST_DOCK_HEIGHT=60        # For smaller dock

# Function to detect monitor geometries and calculate crop coordinates
detect_monitor_geometries() {
  local target_monitor="${1:-0}"  # Which monitor to record (0=main, 1=external, etc.)
  local crop_ui="${2:-false}"    # Whether to crop out UI elements (menu bar, dock)
  
  # Get combined desktop bounds
  local desktop_bounds
  desktop_bounds=$(osascript -e 'tell application "Finder" to get bounds of window of desktop' 2>/dev/null)
  
  if [[ -z "$desktop_bounds" ]]; then
    echo "Error: Could not detect desktop bounds" >&2
    return 1
  fi
  
  # Parse desktop bounds: "0, 0, total_width, total_height"
  local total_width total_height
  total_width=$(echo "$desktop_bounds" | awk -F', ' '{print $3}')
  total_height=$(echo "$desktop_bounds" | awk -F', ' '{print $4}')
  
  echo "Combined desktop: ${total_width}x${total_height}" >&2
  
  # Get individual display information
  local displays_info
  displays_info=$(system_profiler SPDisplaysDataType 2>/dev/null)
  
  # Parse display resolutions and calculate positions
  local monitor_index=0
  local current_x=0
  local found_target=false
  
  # Get resolution lines and process them
  local resolution_lines
  resolution_lines=$(echo "$displays_info" | grep "Resolution:")
  
  while IFS= read -r line; do
    if [[ -n "$line" ]]; then
      # Use awk to extract width and height
      local width height
      width=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/ && $(i+1)=="x") print $i}')
      height=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if($i=="x" && $(i+1) ~ /^[0-9]+$/) print $(i+1)}')
      
      if [[ -n "$width" ]] && [[ -n "$height" ]]; then
        # Check if this is a Retina display (needs scaling calculation)
        local ui_width="$width"
        local ui_height="$height"
        
        # For Retina displays, we need to calculate the UI resolution
        if [[ "$line" =~ Retina ]]; then
          # For Retina displays, the UI resolution is typically half the native resolution
          ui_width=$((width / 2))
          ui_height=$((height / 2))
        fi
        
        # Look for "UI Looks like" line which gives us the actual UI resolution
        local ui_line
        ui_line=$(echo "$displays_info" | grep -A 10 "Resolution: $width x $height" | grep "UI Looks like:" | head -1)
        if [[ -n "$ui_line" ]]; then
          local ui_w ui_h
          ui_w=$(echo "$ui_line" | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/ && $(i+1)=="x") print $i}')
          ui_h=$(echo "$ui_line" | awk '{for(i=1;i<=NF;i++) if($i=="x" && $(i+1) ~ /^[0-9]+$/) print $(i+1)}')
          if [[ -n "$ui_w" ]] && [[ -n "$ui_h" ]]; then
            ui_width="$ui_w"
            ui_height="$ui_h"
          fi
        fi
        
        echo "Monitor $monitor_index: ${ui_width}x${ui_height} (native: ${width}x${height}) at position ${current_x},0" >&2
        
        # If this is our target monitor, calculate crop geometry
        if [[ "$monitor_index" -eq "$target_monitor" ]]; then
          local final_width="$ui_width"
          local final_height="$ui_height"
          local final_x="$current_x"
          local final_y=0
          
          # Apply UI element cropping if requested
          if [[ "$crop_ui" == "true" ]]; then
            # Typical macOS UI dimensions (can be configured)
            local menu_bar_height="${ST_MENU_BAR_HEIGHT:-28}"
            local dock_height="${ST_DOCK_HEIGHT:-70}"
            
            # Crop out menu bar from top
            final_y=$((final_y + menu_bar_height))
            final_height=$((final_height - menu_bar_height))
            
            # Crop out dock from bottom
            final_height=$((final_height - dock_height))
            
            echo "UI cropping applied: menu bar ${menu_bar_height}px, dock ${dock_height}px" >&2
          fi
          
          # For screencapture, we need to crop from the combined desktop
          # The crop geometry is: width:height:x_offset:y_offset
          echo "${final_width}x${final_height}+${final_x}+${final_y}"
          found_target=true
          break
        fi
        
        # Move to next monitor position (assuming horizontal arrangement)
        current_x=$((current_x + ui_width))
        ((monitor_index++))
      fi
    fi
  done <<< "$resolution_lines"
  
  if [[ "$found_target" != "true" ]]; then
    echo "Error: Monitor $target_monitor not found" >&2
    return 1
  fi
}

record_mac() {
  local prefix duration recording_id recording_dir recording_path
  prefix="${1:-screen}"
  duration="${2:-}"  # Optional duration parameter
  recording_id="$(date +%s)"
  recording_dir="$ST_DIR/$recording_id"
  recording_path="$recording_dir/recording.mov"
  
  # Create recording directory
  mkdir -p "$recording_dir"
  
  # Detect monitor geometry if we need to crop to a specific monitor
  local crop_geometry=""
  local target_monitor=""
  
  # Parse ST_AVFOUNDATION_VIDEO_DEVICE to determine target monitor
  if [[ -n "$ST_AVFOUNDATION_VIDEO_DEVICE" ]] && [[ "$ST_AVFOUNDATION_VIDEO_DEVICE" =~ ^[0-9]+$ ]]; then
    # Map AVFoundation device index to screen index
    # AVFoundation device 2 = screen 0, device 3 = screen 1, etc.
    if [[ "$ST_AVFOUNDATION_VIDEO_DEVICE" -ge 2 ]]; then
      target_monitor=$((ST_AVFOUNDATION_VIDEO_DEVICE - 2))
      echo "Detecting geometry for AVFoundation device $ST_AVFOUNDATION_VIDEO_DEVICE (screen $target_monitor)..."
      
      # Check if UI cropping is enabled
      local enable_ui_crop="${ST_CROP_UI_ELEMENTS:-false}"
      
      crop_geometry=$(detect_monitor_geometries "$target_monitor" "$enable_ui_crop")
      if [[ $? -eq 0 ]] && [[ -n "$crop_geometry" ]]; then
        if [[ "$enable_ui_crop" == "true" ]]; then
          echo "✓ Screen $target_monitor geometry (UI cropped): $crop_geometry"
        else
          echo "✓ Screen $target_monitor geometry: $crop_geometry"
        fi
      else
        echo "⚠️ Could not detect monitor geometry, recording full desktop"
        crop_geometry=""
      fi
    else
      echo "⚠️ AVFoundation device $ST_AVFOUNDATION_VIDEO_DEVICE is not a screen capture device"
    fi
  fi
  
  # Create recording metadata with comprehensive info
  cat > "$recording_dir/recording.meta" << EOF
RECORDING_NAME="$prefix"
RECORDING_ID="$recording_id"
RECORDING_PATH="$recording_path"
RECORDING_LOG="recording.log"
START_TIME="$(date)"
SCREEN_DEVICE="$ST_AVFOUNDATION_VIDEO_DEVICE"
AUDIO_DEVICE="$ST_AVFOUNDATION_AUDIO_DEVICE"
CROP_GEOMETRY="$crop_geometry"
SCREEN_GEOMETRY="$SCREEN_GEOMETRY"
MONITOR_CROP_GEOMETRY="$crop_geometry"
RECORDING_FORMAT="mov"
EDIT_FORMAT="mkv"
FINAL_FORMAT="mp4"
EOF
  
  echo "Recording ID: $recording_id"
  echo "Recording will be saved to: $recording_path"
  
  # Update latest symlink immediately (even if recording fails later)
  local latest_link="$ST_DIR/latest"
  rm -f "$latest_link"
  ln -sf "$recording_id" "$latest_link"
  echo "Updated latest -> $recording_id"
  
  echo "Press Ctrl+C to stop recording, or wait for timeout..."
  echo
  
  # Use macOS native screencapture with proper audio and screen selection
  echo "Starting macOS screen recording with screencapture..."
  
  # Simplified signal handling - let screencapture handle its own signals
  local recording_interrupted=false
  
  # Build screencapture command with audio support
  local screencapture_cmd=(screencapture)
  
  # Build screencapture command for interruptible recording
  screencapture_cmd+=(-v)  # Include video recording
  
  # Add audio capture - try different approaches
  screencapture_cmd+=(-g)  # Include default audio input
  echo "Including audio capture"
  
  # NO duration flag - let screencapture handle Ctrl+C properly
  echo "Recording with audio... Press Ctrl+C to stop"
  
  # Add output file (must be last)
  screencapture_cmd+=("$recording_path")

  echo "Command: ${screencapture_cmd[*]}"
  echo "🎬 Press Ctrl+C to stop recording at any time"
  echo "💡 Tip: Record for at least 1-2 seconds for best results"

  # Execute screencapture directly (foreground) - let it handle its own signals
  echo "🔧 Debug: About to execute: ${screencapture_cmd[*]}"
  echo "🔧 Debug: Output path: $recording_path"
  echo "🔧 Debug: Directory exists: $(test -d "$(dirname "$recording_path")" && echo "YES" || echo "NO")"
  echo "🔧 Debug: Directory writable: $(test -w "$(dirname "$recording_path")" && echo "YES" || echo "NO")"
  
  echo "🎬 Starting recording... Press Ctrl+C to stop"
  
  # Run screencapture in foreground - it handles Ctrl+C natively
  local exit_code=0
  if ! "${screencapture_cmd[@]}"; then
    exit_code=$?
  fi
  
  echo "Recording finished with exit code: $exit_code"
  
  if [[ -f "$recording_path" ]]; then
    # Check recording duration
    local duration_seconds
    duration_seconds=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$recording_path" 2>/dev/null)
    
    if [[ -n "$duration_seconds" ]]; then
      local duration_ms
      duration_ms=$(echo "$duration_seconds * 1000" | bc 2>/dev/null || echo "0")
      duration_ms=${duration_ms%.*}  # Remove decimal part
      
      if (( duration_ms < 500 )); then
        echo "⚠️  Very short recording detected: ${duration_ms}ms"
        echo "💡 Tip: Wait at least 1-2 seconds before stopping for better results"
      else
        echo "✓ Screen recording completed: $recording_path (${duration_ms}ms)"
      fi
    else
      echo "✓ Screen recording completed: $recording_path"
    fi

    # Apply monitor cropping if needed
    if [[ -n "$crop_geometry" ]]; then
      echo "Applying monitor crop: $crop_geometry"
      local cropped_path="$recording_dir/recording_cropped.mov"
      local temp_path="$recording_dir/recording_temp.mov"
      
      # Parse crop geometry: WxH+X+Y
      if [[ "$crop_geometry" =~ ^([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+)$ ]]; then
        local crop_w="${BASH_REMATCH[1]}"
        local crop_h="${BASH_REMATCH[2]}"
        local crop_x="${BASH_REMATCH[3]}"
        local crop_y="${BASH_REMATCH[4]}"
        
        # Get actual captured resolution to scale crop coordinates
        local actual_info
        actual_info=$(ffprobe -v quiet -print_format json -show_streams "$recording_path" | jq -r '.streams[0] | "\(.width)x\(.height)"')
        local actual_w actual_h
        actual_w=$(echo "$actual_info" | cut -d'x' -f1)
        actual_h=$(echo "$actual_info" | cut -d'x' -f2)
        
        echo "Original capture: ${actual_w}x${actual_h}"
        echo "Logical crop: ${crop_w}x${crop_h} at offset ${crop_x},${crop_y}"
        
        # Calculate scaling factor (actual vs logical resolution)
        local scale_x scale_y
        scale_x=$(echo "scale=4; $actual_w / 1600" | bc)
        scale_y=$(echo "scale=4; $actual_h / 1000" | bc)
        
        # Scale crop coordinates to match actual capture resolution
        local scaled_w scaled_h scaled_x scaled_y
        scaled_w=$(echo "scale=0; $crop_w * $scale_x / 1" | bc)
        scaled_h=$(echo "scale=0; $crop_h * $scale_y / 1" | bc)
        scaled_x=$(echo "scale=0; $crop_x * $scale_x / 1" | bc)
        scaled_y=$(echo "scale=0; $crop_y * $scale_y / 1" | bc)
        
        echo "Scaled crop: ${scaled_w}x${scaled_h} at offset ${scaled_x},${scaled_y}"
        
        # Update crop variables with scaled values
        crop_w="$scaled_w"
        crop_h="$scaled_h"
        crop_x="$scaled_x"
        crop_y="$scaled_y"
        
        # Backup original file
        local original_backup="$recording_dir/recording_original.mov"
        cp "$recording_path" "$original_backup"
        echo "Original saved as: recording_original.mov"
        
        # Use ffmpeg to crop, scale down, and resample audio
        local target_width="${RECORD_TARGET_WIDTH:-1600}"
        local target_height="${RECORD_TARGET_HEIGHT:-900}"
        echo "Running: ffmpeg -i \"$recording_path\" -vf \"crop=${crop_w}:${crop_h}:${crop_x}:${crop_y},scale=${target_width}:${target_height}\" -ar 48000 -ac $AUDIO_CHANNELS \"$temp_path\""
        if ffmpeg -i "$recording_path" \
                  -vf "crop=${crop_w}:${crop_h}:${crop_x}:${crop_y},scale=${target_width}:${target_height}" \
                  -ar 48000 \
                  -ac "$AUDIO_CHANNELS" \
                  "$temp_path" -y 2>&1; then
          
          # Replace original with cropped version
          mv "$temp_path" "$recording_path"
          echo "✓ Monitor cropping applied successfully"
          echo "✓ Audio resampled to 48kHz"
        else
          echo "⚠️ Monitor cropping failed, keeping original full desktop recording"
          echo "Check the ffmpeg output above for details"
          rm -f "$temp_path"
        fi
      else
        echo "⚠️ Invalid crop geometry format: $crop_geometry"
      fi
    fi

    # Post-process audio to ensure 48kHz, 32-bit float PCM
    local processed_audio="$recording_dir/processed_audio.wav"
    if ffmpeg -i "$recording_path" \
              -vn \
              -acodec pcm_f32le \
              -ar 48000 \
              -ac "$AUDIO_CHANNELS" \
              "$processed_audio" 2>/dev/null; then
      echo "✓ Audio processed to 48kHz, 32-bit float PCM"
    else
      echo "⚠️ Audio processing failed, using original"
    fi
  else
    if [[ $exit_code -eq 130 ]]; then
      # User pressed Ctrl+C - this is normal for manual stop
      echo "⚠️ Recording stopped by user (Ctrl+C)"
      echo "💡 No video file was created - this can happen if stopped too quickly"
    elif [[ $exit_code -eq 1 ]]; then
      echo "⚠️ Recording failed - screencapture error"
    else
      echo "✗ Recording failed (exit code: $exit_code)"
    fi
    
    echo "📝 Recording metadata saved to: $recording_dir/recording.meta"
    
    # Update metadata to reflect failure
    cat >> "$recording_dir/recording.meta" << EOF
END_TIME="$(date)"
RECORDING_COMPLETE="false"
FAILURE_REASON="No video file created (exit code: $exit_code)"
EOF
    
    return 1
  fi
  
  # Verify recording was created
  if [[ ! -f "$recording_path" ]]; then
    echo "✗ Recording file not created"
    return 1
  fi
  
  # Get file size for feedback
  local file_size
  file_size=$(stat -f "%z" "$recording_path" 2>/dev/null)
  if [[ -n "$file_size" ]]; then
    file_size=$(echo "$file_size" | awk '{printf "%.1fMB", $1/1024/1024}')
    echo "Recording size: $file_size"
  fi
  
  # Update recording metadata with end time and file info
  cat >> "$recording_dir/recording.meta" << EOF
END_TIME="$(date)"
FILE_SIZE="$file_size"
RECORDING_COMPLETE="true"
EOF
  
  # Latest symlink already updated at recording start
  
  # Show final status
  echo "🎬 Recording completed successfully"
  
  echo
  echo "✅ Recording complete!"
  echo "📁 Session: $recording_id"
  echo "🎬 File: $recording_path"
  echo "▶️  Play: st play latest"
  echo "✏️  Edit: st edit $recording_id"
}
