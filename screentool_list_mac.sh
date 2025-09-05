#!/usr/bin/env bash
# screentool_list_mac.sh
# macOS-specific listing and summary functions

list_recordings_mac() {
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
        size=$(stat -f "%z" "$recording_file" 2>/dev/null)
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
  echo "Latest recording: st play latest (or: latest/recording.mov)"
}

summary_recordings_mac() {
  echo "Recording Summary"
  echo "================"
  echo
  
  local recordings=()
  local total_space=0
  
  # Find all recording directories
  while IFS= read -r -d '' recording_dir; do
    if [[ -d "$recording_dir" ]] && [[ $(basename "$recording_dir") =~ ^[0-9]+$ ]]; then
      recordings+=("$recording_dir")
    fi
  done < <(find "$ST_DIR" -maxdepth 1 -type d -print0 2>/dev/null | sort -z)
  
  if [[ ${#recordings[@]} -eq 0 ]]; then
    echo "No recordings found in $ST_DIR"
    return
  fi
  
  local index=1
  
  for recording_dir in "${recordings[@]}"; do
    local recording_id=$(basename "$recording_dir")
    local meta_file="$recording_dir/recording.meta"
    local name="$recording_id"
    local session_total=0
    
    # Get recording name from metadata
    if [[ -f "$meta_file" ]]; then
      local recording_name
      recording_name=$(grep "^RECORDING_NAME=" "$meta_file" | cut -d'"' -f2 2>/dev/null)
      if [[ -n "$recording_name" ]]; then
        name="$recording_name"
      fi
    fi
    
    # Calculate total space for this session
    local recording_size=0 edit_size=0 final_size=0
    
    # Check each file type
    local files=("recording.mov" "edit.mkv" "final.mp4")
    local file_info=()
    
    for file_type in "${files[@]}"; do
      local file_path="$recording_dir/$file_type"
      local size_bytes=0 duration="" width="" height=""
      
      if [[ -f "$file_path" ]]; then
        # Get file size in bytes
        size_bytes=$(stat -f "%z" "$file_path" 2>/dev/null || 0)
        session_total=$((session_total + size_bytes))
        
        # Get file info
        if command -v ffprobe >/dev/null; then
          local probe_output
          probe_output=$(ffprobe -v quiet -print_format json -show_format -show_streams "$file_path" 2>/dev/null)
          
          if [[ -n "$probe_output" ]] && command -v jq >/dev/null; then
            duration=$(echo "$probe_output" | jq -r '.format.duration // ""' | awk '{printf "%.1fs", $1}')
            width=$(echo "$probe_output" | jq -r '.streams[] | select(.codec_type=="video") | .width // 0' | head -1)
            height=$(echo "$probe_output" | jq -r '.streams[] | select(.codec_type=="video") | .height // 0' | head -1)
          fi
        fi
        
        # Format size for display
        local size_mb=$(echo "$size_bytes" | awk '{printf "%.1fMB", $1/1024/1024}')
        local geometry="${width}x${height}"
        
        file_info+=("   ✓ $file_type: $size_mb, $duration, $geometry")
      else
        file_info+=("   - $file_type: (not created)")
      fi
    done
    
    # Add to total space
    total_space=$((total_space + session_total))
    
    # Format session total
    local session_mb=$(echo "$session_total" | awk '{printf "%.1fMB", $1/1024/1024}')
    
    # Display session header
    printf "%d) %s (%s) - %s total\n" "$index" "$name" "$recording_id" "$session_mb"
    
    # Display indented file info
    for info in "${file_info[@]}"; do
      echo "$info"
    done
    echo
    
    ((index++))
  done
  
  # Show total space used
  local total_mb=$(echo "$total_space" | awk '{printf "%.1fMB", $1/1024/1024}')
  echo "📊 Total space used: $total_mb across ${#recordings[@]} recordings"
  echo
  echo "💡 Use 'st info <n>' for detailed analysis of a specific recording"
}
