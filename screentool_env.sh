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
    echo "Saving environment variables..."
    
    # Create directories if they don't exist
    mkdir -p "$(dirname "$SRC_ENV")"
    mkdir -p "$(dirname "$DIR_ENV")"
    
    # Remove old env files
    rm -f "$SRC_ENV"
    rm -f "$DIR_ENV"
    
    # Create new env file with current settings
    {
        # Base paths
        echo "export ST_SRC=\"$ST_SRC\""
        echo "export ST_DIR=\"$ST_DIR\""
        
        # Display settings
        echo "export DISPLAY=\"$DISPLAY\""
        echo "export SCREEN_GEOMETRY=\"$SCREEN_GEOMETRY\""
        
        # Audio settings
        echo "export ST_AUDIO_BACKEND=\"${ST_AUDIO_BACKEND:-pulse}\""
        echo "export ST_AUDIO_OUT_BACKEND=\"${ST_AUDIO_OUT_BACKEND:-pulse}\""
        echo "export ST_PULSE_IN_DEVICE=\"${ST_PULSE_IN_DEVICE}\""
        echo "export ST_PULSE_OUT_DEVICE=\"${ST_PULSE_OUT_DEVICE}\""
        echo "export ST_BUFFER_SIZE=\"${ST_BUFFER_SIZE:-1024}\""
        
        # Video settings
        echo "export VIDEO_CODEC=\"${VIDEO_CODEC:-libx264}\""
        echo "export PRESET=\"${PRESET:-veryfast}\""
        echo "export CRF=\"${CRF:-23}\""
        echo "export COMPRESSION_TUNE=\"${COMPRESSION_TUNE:-zerolatency}\""
        echo "export COMPRESSION_GOP=\"${COMPRESSION_GOP:-60}\""
        echo "export FRAMERATE=\"${FRAMERATE:-30}\""
        
        # Audio encoding settings
        echo "export AUDIO_CHANNELS=\"${AUDIO_CHANNELS:-2}\""
        echo "export AUDIO_CODEC=\"${AUDIO_CODEC:-aac}\""
        echo "export AUDIO_BITRATE=\"${AUDIO_BITRATE:-192k}\""
    } | tee "$SRC_ENV" > "$DIR_ENV"
    
    echo "Environment saved to:"
    echo "  $SRC_ENV"
    echo "  $DIR_ENV"
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
