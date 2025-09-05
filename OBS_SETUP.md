# OBS Studio Setup for ScreenTool

ScreenTool now uses OBS Studio exclusively for recording, using the OBS binary with launch flags for simple, reliable control.

## Prerequisites

1. **OBS Studio** - Download from https://obsproject.com/
2. **No additional dependencies** - Uses OBS binary directly!

## OBS Configuration

### 1. Create Scene Collection and Profile

1. Open OBS Studio
2. Create a **Scene Collection** called `ScreenTool`
3. Create a **Profile** called `ScreenTool`
4. Create a **Scene** called `ScreenTool`

### 2. Scene Setup (Manual)

Set up your recording scene:
- **Scene Name**: `ScreenTool` (configurable via `OBS_SCENE_NAME`)
- **Display Capture Source**: Add for screen recording

### 3. Recording Settings

Configure OBS recording settings:
1. Go to **Settings** → **Output**
2. Set **Recording Format**: MKV (recommended) or MP4
3. Set **Recording Path**: `~/Movies` (or your preferred location)
4. Configure **Video Encoder**: Hardware encoder if available (H.264)
5. Set **Audio Encoder**: AAC

### 4. Video Settings

1. Go to **Settings** → **Video**
2. Set **Base (Canvas) Resolution**: Your screen resolution
3. Set **Output (Scaled) Resolution**: 1920x1080 (or desired)
4. Set **Common FPS Values**: 30 or 60 fps

## ScreenTool Configuration

### Environment Variables

Add to your `screentool.env` or set in shell:

```bash
# OBS binary configuration - EVERYTHING under ST_DIR!
export OBS_COLLECTION_NAME="ScreenTool"
export OBS_PROFILE_NAME="ScreenTool"
export OBS_SCENE_NAME="ScreenTool"
export OBS_OUTPUT_DIR="$ST_DIR"  # NEVER ~/Movies!

# Recording area (below status bar, above dock)
export ST_CROP_UI_ELEMENTS="true"
export ST_MENU_BAR_HEIGHT="28"
export ST_DOCK_HEIGHT="70"
```

### Recording Area Configuration

ScreenTool translates your universal settings to OBS:

- **Full Screen**: No crop geometry set
- **Custom Area**: Set via `ST_CROP_GEOMETRY="1920x1080+0+0"`
- **UI Cropping**: Excludes menu bar and dock automatically

## Usage

### Basic Recording

```bash
# Start recording
./screentool.sh record demo

# Record for specific duration
./screentool.sh record demo 30

# Stop recording
./screentool.sh stop-recording
```

### OBS Management

```bash
# Check OBS status
./screentool.sh obs-status

# Configure OBS (interactive)
./screentool.sh obs-config

# Show help
./screentool.sh help
```

### Complete Workflow

```bash
# 1. Record with OBS
./screentool.sh record my_demo 10

# 2. Edit to standard format
./screentool.sh edit 1

# 3. Export final version
./screentool.sh final 1

# 4. Play result
./screentool.sh play 1
```

## Troubleshooting

### Connection Issues

```bash
# Check if OBS is running
ps aux | grep OBS

# Test WebSocket connection
websocat ws://127.0.0.1:4455

# Check OBS WebSocket settings
# Tools → WebSocket Server Settings
```

### Recording Issues

1. **No recording file created**:
   - Check OBS recording path settings
   - Verify disk space
   - Check OBS logs

2. **Authentication failed**:
   - Verify WebSocket password matches
   - Check `OBS_WEBSOCKET_PASSWORD` environment variable

3. **Scene not found**:
   - Run `./screentool.sh obs-config` to set up scenes
   - Manually create scene in OBS if needed

### Legacy Fallback

If you need to use the old recording methods:

```bash
# Legacy files are in the legacy/ directory
# Copy back if needed (not recommended)
```

## Advanced Configuration

### Custom Recording Area

```bash
# Set specific area (width x height + x_offset + y_offset)
export ST_CROP_GEOMETRY="1600x900+160+90"

# Enable UI cropping for clean recordings
export ST_CROP_UI_ELEMENTS="true"
```

### OBS Scene Customization

1. Create custom scenes in OBS
2. Set scene name: `export OBS_SCENE_NAME="MyCustomScene"`
3. Add Display Capture source with desired settings
4. ScreenTool will use your custom scene

## Benefits of OBS Integration

- **Better Quality**: Hardware encoding, advanced filters
- **More Control**: Scene composition, multiple sources
- **Flexibility**: Custom layouts, overlays, transitions  
- **Professional Features**: Streaming, virtual camera, plugins
- **Reliability**: Mature, well-tested recording engine
