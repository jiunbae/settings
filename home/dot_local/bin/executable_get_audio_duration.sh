#!/usr/bin/env bash
# usage: get_audio_duration.sh /path/to/dir
# Print "<file>,<seconds>" per .wav in a directory, then a TOTAL row.
set -uo pipefail

DIR="${1-}"

if [[ -z "$DIR" ]]; then
    echo "Usage: $(basename "$0") <directory>" >&2
    exit 2
fi

if [[ ! -d "$DIR" ]]; then
    echo "Error: not a directory: $DIR" >&2
    exit 2
fi

if ! command -v ffprobe > /dev/null 2>&1; then
    echo "Error: ffprobe not found (install ffmpeg)" >&2
    exit 2
fi

TOTAL=0
COUNT=0
FAILED=0

# nullglob keeps an unmatched pattern from being emitted as a literal data row,
# which downstream CSV consumers would ingest as a real file.
shopt -s nullglob

for f in "$DIR"/*.wav; do
    if ! DUR=$(ffprobe -v error -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 "$f"); then
        echo "Error: could not read duration: $f" >&2
        FAILED=$((FAILED + 1))
        continue
    fi

    DUR_FMT=$(awk -v d="$DUR" 'BEGIN{printf "%.3f", d}')
    echo "$f,$DUR_FMT"
    TOTAL=$(awk -v a="$TOTAL" -v b="$DUR_FMT" 'BEGIN{printf "%.3f", a+b}')
    COUNT=$((COUNT + 1))
done

shopt -u nullglob

if (( COUNT == 0 && FAILED == 0 )); then
    echo "No .wav files in $DIR" >&2
    exit 3
fi

echo "TOTAL,$TOTAL"

(( FAILED == 0 ))
