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
    
    # First, remove the old env file if it exists
    rm -f "$DIR_ENV"
    
    {
        # Base paths
        echo "export ST_SRC=\"$ST_SRC\""
        echo "export ST_DIR=\"$ST_DIR\""
        
        # Display settings
        echo "export DISPLAY=\"$DISPLAY\""
        echo "export SCREEN_GEOMETRY=\"$SCREEN_GEOMETRY\""
        
        # Audio backends
        echo "export ST_AUDIO_BACKEND=\"${ST_AUDIO_BACKEND:-pulse}\""
        echo "export ST_AUDIO_OUT_BACKEND=\"${ST_AUDIO_OUT_BACKEND:-pulse}\""
        
        # PulseAudio settings
        echo "export ST_PULSE_IN_DEVICE=\"${ST_PULSE_IN_DEVICE:-@DEFAULT_SOURCE@}\""
        echo "export ST_PULSE_OUT_DEVICE=\"${ST_PULSE_OUT_DEVICE:-@DEFAULT_SINK@}\""
        echo "export ST_BUFFER_SIZE=\"${ST_BUFFER_SIZE:-1024}\""
        
        # ALSA settings
        echo "export ST_ALSA_IN_DEVICE=\"${ST_ALSA_IN_DEVICE:-default}\""
        echo "export ST_ALSA_OUT_DEVICE=\"${ST_ALSA_OUT_DEVICE:-default}\""
        
        # Video settings
        echo "export VIDEO_CODEC=\"${VIDEO_CODEC:-libx264}\""
        echo "export PRESET=\"${PRESET:-veryfast}\""
        echo "export CRF=\"${CRF:-23}\""
        echo "export COMPRESSION_TUNE=\"${COMPRESSION_TUNE:-zerolatency}\""
        echo "export COMPRESSION_GOP=\"${COMPRESSION_GOP:-60}\""
        echo "export FRAMERATE=\"${FRAMERATE:-30}\""
        
        # Audio settings
        echo "export AUDIO_CHANNELS=\"${AUDIO_CHANNELS:-2}\""
        echo "export AUDIO_CODEC=\"${AUDIO_CODEC:-aac}\""
        echo "export AUDIO_BITRATE=\"${AUDIO_BITRATE:-192k}\""
    } > "$DIR_ENV"
    
    echo "Environment saved to $DIR_ENV"
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
