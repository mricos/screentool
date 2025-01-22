#!/bin/bash
# screentool_env.sh - Environment variable management for screentool

# Define default paths
ST_SRC=${ST_SRC:-"$HOME/src/screentool"}
ST_DIR=${ST_DIR:-"$HOME/recordings"}

# Define environment configuration files
SRC_ENV="$ST_SRC/screentool.env"
DIR_ENV="$ST_DIR/screentool.env"

# Load environment variables from files
load_env() {
    local found=0
    [ -n true ] && echo "ST_SRC=$ST_SRC"
    [ -n true ] && echo "ST_DIR=$ST_DIR"

    # First try source directory config
    if [ -f "$SRC_ENV" ]; then
        echo "SRC_ENV=$SRC_ENV"
        source "$SRC_ENV"
        found=1
    fi
    
    # Then try recordings directory config (will override if exists)
    if [ -f "$DIR_ENV" ]; then
        echo "DIR_ENV=$DIR_ENV"
        source "$DIR_ENV"
        found=1
    fi
    
    if [ $found -eq 0 ]; then
        echo "No environment configuration files found."
        echo "Looked in:"
        echo "  $SRC_ENV"
        echo "  $DIR_ENV"
    fi
}

save_env() {
    echo "Saving environment variables to $DIR_ENV..."
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$DIR_ENV")"
    {
        echo "export ST_SRC=\"$ST_SRC\""
        echo "export ST_DIR=\"$ST_DIR\""
        echo "export DISPLAY=\"$DISPLAY\""
        echo "export MARGIN=\"80 0 0 0\""
        echo "export SCREEN_GEOMETRY=\"$SCREEN_GEOMETRY\""
        echo "export AUDIO_DEVICE_IN=\"$AUDIO_DEVICE_IN\""
        echo "export AUDIO_DEVICE_OUT=\"$AUDIO_DEVICE_OUT\""
        echo "export VIDEO_CODEC=\"$VIDEO_CODEC\""
        echo "export PRESET=\"$PRESET\""
        echo "export CRF=\"$CRF\""
        echo "export COMPRESSION_TUNE=\"$COMPRESSION_TUNE\""
        echo "export COMPRESSION_GOP=\"$COMPRESSION_GOP\""
        echo "export FRAMERATE=\"$FRAMERATE\""
        echo "export SCREEN_SIZE=\"$SCREEN_SIZE\""
        echo "export RATE=\"$RATE\""
        echo "export BUFFER_SIZE=\"$BUFFER_SIZE\""
        echo "export PERIOD_SIZE=\"$PERIOD_SIZE\""
        echo "export AUDIO_CHANNELS=\"$AUDIO_CHANNELS\""
        echo "export AUDIO_CODEC=\"$AUDIO_CODEC\""
        echo "export AUDIO_BITRATE=\"$AUDIO_BITRATE\""
    } > "$DIR_ENV"
}

# Display environment variables
env_display() {
    echo "Current Environment Variables:"
    echo "-------------------------------"
    echo "ST_SRC=$ST_SRC"
    echo "ST_DIR=$ST_DIR"
    if [ -f "$SRC_ENV" ]; then
        echo "Source environment ($SRC_ENV):"
        cat "$SRC_ENV"
    fi
    if [ -f "$DIR_ENV" ]; then
        echo "Directory environment ($DIR_ENV):"
        cat "$DIR_ENV"
    fi
    echo "-------------------------------"
}
