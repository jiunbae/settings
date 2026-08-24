#!/usr/bin/env bash
# usage: get_audio_duration.sh /path/to/dir

DIR="$1"

TOTAL=0
for f in "$DIR"/*.wav; do
  DUR=$(ffprobe -v error -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 "$f")

  DUR_FMT=$(awk -v d="$DUR" 'BEGIN{printf "%.3f", d}')
  echo "$f,$DUR_FMT"
  TOTAL=$(awk -v a="$TOTAL" -v b="$DUR_FMT" 'BEGIN{printf "%.3f", a+b}')
done

echo "TOTAL,$TOTAL"