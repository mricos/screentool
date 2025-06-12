play_recording() {
  local file="${1:-latest.mp4}"
  if [[ ! "$file" = /* ]]; then
    file="$ST_DIR/$file"
  fi
  if [ ! -f "$file" ]; then
    echo "Error: File not found: $file"
    exit 1
  fi
  echo "Playing: $file"
  ffplay -autoexit -i "$file"
}
