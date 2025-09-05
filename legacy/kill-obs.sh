#!/usr/bin/env bash
# Emergency OBS cleanup script
# Use this when Ctrl+C doesn't work and processes are stuck

echo "🚨 EMERGENCY OBS CLEANUP"
echo "========================"

echo "Killing all OBS processes..."
if pgrep -f "OBS.app" >/dev/null 2>&1; then
    pkill -f "OBS.app" 2>/dev/null
    echo "✅ OBS killed"
else
    echo "ℹ️  No OBS processes found"
fi

echo "Killing all ffplay processes..."
if pgrep -f "ffplay" >/dev/null 2>&1; then
    pkill -f "ffplay" 2>/dev/null
    echo "✅ ffplay killed"
else
    echo "ℹ️  No ffplay processes found"
fi

echo "Killing any screentool processes (except this one)..."
if pgrep -f "screentool" >/dev/null 2>&1; then
    pkill -f "st record" 2>/dev/null || true
    echo "✅ screentool recording killed"
else
    echo "ℹ️  No screentool processes found"
fi

echo ""
echo "✅ Emergency cleanup complete!"
echo "You should now be able to use Ctrl+C normally."
echo ""
echo "To restart recording:"
echo "  st record demo 10"
