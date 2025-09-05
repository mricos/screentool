#!/usr/bin/env bash
# screentool_list_linux.sh
# Linux-specific listing and summary functions (Ubuntu/FFmpeg)

list_recordings_linux() {
  local format="$1"
  echo "Available recordings (Linux):"
  echo "============================="
  
  # TODO: Implement Linux-specific listing
  # Similar to Mac version but adapted for Linux file paths and tools
  
  echo "Linux listing not yet implemented"
  echo "Use basic file listing for now:"
  ls -la "$ST_DIR"
}

summary_recordings_linux() {
  echo "Recording Summary (Linux)"
  echo "========================"
  echo
  
  # TODO: Implement Linux-specific summary
  # Similar to Mac version but using Linux tools (stat, etc.)
  
  echo "Linux summary not yet implemented"
  echo "Use 'ls -la $ST_DIR' for basic directory listing"
}
