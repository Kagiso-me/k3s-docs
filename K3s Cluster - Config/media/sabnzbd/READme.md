# Jellyfin Post-Processing with SABnzbd

## 1. What We Are Doing
We are implementing a **post-processing script in SABnzbd** that automatically converts downloaded videos into a format that is **fully compatible with Jellyfin**. The script ensures all videos are in **H.264 video codec and AAC audio codec in MP4 container**, which eliminates the need for on-the-fly transcoding when streaming.

Additionally, the script logs metrics suitable for Prometheus Node Exporter, allowing us to track conversion activity over time in **Grafana**.

## 2. Why
- **Reduce CPU load:** Avoids transcoding in Jellyfin by pre-converting incompatible files.
- **Improve playback compatibility:** Ensures all devices can play the files directly.
- **Monitoring:** Metrics for total processed, converted, skipped, and failed files help track system activity and identify issues.

## 3. The Script

```bash
#!/bin/bash
# SABnzbd Post-Processing Script: Convert videos to Jellyfin-friendly format with logging for Grafana

JOB_NAME="$1"
CATEGORY="$2"
OUTPUT_DIR="$3"
NZB_FILE="$4"
SAB_OUTPUT="$5"

TARGET_EXT="mp4"
LOG_DIR="/var/log/sabnzbd_jellyfin"
mkdir -p "$LOG_DIR"

TEXTFILE_METRICS="$LOG_DIR/conversion_metrics.prom"

TOTAL=0
CONVERTED=0
SKIPPED=0
FAILED=0

echo "# HELP sabnzbd_jellyfin_total Total number of videos processed" > "$TEXTFILE_METRICS"
echo "# TYPE sabnzbd_jellyfin_total counter" >> "$TEXTFILE_METRICS"
echo "# HELP sabnzbd_jellyfin_converted Total number of videos converted" >> "$TEXTFILE_METRICS"
echo "# TYPE sabnzbd_jellyfin_converted counter" >> "$TEXTFILE_METRICS"
echo "# HELP sabnzbd_jellyfin_skipped Total number of compatible videos skipped" >> "$TEXTFILE_METRICS"
echo "# TYPE sabnzbd_jellyfin_skipped counter" >> "$TEXTFILE_METRICS"
echo "# HELP sabnzbd_jellyfin_failed Total number of videos failed to convert" >> "$TEXTFILE_METRICS"
echo "# TYPE sabnzbd_jellyfin_failed counter" >> "$TEXTFILE_METRICS"

is_compatible() {
    ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$1" | grep -q "h264" &&
    ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$1" | grep -q "aac"
}

find "$SAB_OUTPUT" -type f \\( -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.mp4" \\) | while read -r FILE; do
    TOTAL=$((TOTAL+1))
    BASENAME=$(basename "$FILE")
    OUTPUT_FILE="$SAB_OUTPUT/${BASENAME%.*}.$TARGET_EXT"

    if is_compatible "$FILE"; then
        SKIPPED=$((SKIPPED+1))
        echo "$(date +'%Y-%m-%d %H:%M:%S') SKIPPED: $FILE is already compatible" >> "$LOG_DIR/postprocess.log"
    else
        echo "$(date +'%Y-%m-%d %H:%M:%S') CONVERTING: $FILE -> $OUTPUT_FILE" >> "$LOG_DIR/postprocess.log"
        ffmpeg -i "$FILE" -c:v libx264 -preset fast -crf 22 -c:a aac -b:a 160k -movflags +faststart "$OUTPUT_FILE"
        if [ $? -eq 0 ]; then
            CONVERTED=$((CONVERTED+1))
            echo "$(date +'%Y-%m-%d %H:%M:%S') SUCCESS: $OUTPUT_FILE" >> "$LOG_DIR/postprocess.log"
        else
            FAILED=$((FAILED+1))
            echo "$(date +'%Y-%m-%d %H:%M:%S') FAILED: $FILE" >> "$LOG_DIR/postprocess.log"
        fi
    fi
done

echo "sabnzbd_jellyfin_total $TOTAL" >> "$TEXTFILE_METRICS"
echo "sabnzbd_jellyfin_converted $CONVERTED" >> "$TEXTFILE_METRICS"
echo "sabnzbd_jellyfin_skipped $SKIPPED" >> "$TEXTFILE_METRICS"
echo "sabnzbd_jellyfin_failed $FAILED" >> "$TEXTFILE_METRICS"

echo "$(date +'%Y-%m-%d %H:%M:%S') Jellyfin post-processing metrics updated" >> "$LOG_DIR/postprocess.log"
exit 0
