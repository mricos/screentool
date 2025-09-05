#!/usr/bin/env bash
# st.sh - ScreenTool CLI

# Determine the script's directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source environment variables
source "$SCRIPT_DIR/env.sh"

# Main command dispatcher
case "$1" in
    "mux")
        shift
        "$SCRIPT_DIR/screentool_mux.sh" "$@"
        ;;
    "mix")
        shift
        "$SCRIPT_DIR/screentool_mix_audio.sh" "$@"
        ;;
    *)
        # Execute the main screentool script with all arguments
        "$ST_SRC/screentool.sh" "$@"
        ;;
esac

