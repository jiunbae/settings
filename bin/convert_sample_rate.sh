#!/bin/bash

INPUT_PATH="$1"
OUTPUT_PATH="$2"
TARGET_SAMPLE_RATE="$3"

if [ -d "$INPUT_PATH" ]; then
    # 입력이 디렉토리일 경우: 출력도 디렉토리여야 함
    mkdir -p "$OUTPUT_PATH"

    for file in "$INPUT_PATH"/*.wav; do
        [ -e "$file" ] || continue  # wav 파일이 없으면 건너뜀
        filename=$(basename "$file" .wav)
        ffmpeg -y -i "$file" -ar "$TARGET_SAMPLE_RATE" -ac 1 "$OUTPUT_PATH/${filename}.wav"
    done

elif [ -f "$INPUT_PATH" ]; then
    # 입력이 단일 파일일 경우: 출력은 파일 경로
    output_dir=$(dirname "$OUTPUT_PATH")
    mkdir -p "$output_dir"

    ffmpeg -y -i "$INPUT_PATH" -ar "$TARGET_SAMPLE_RATE" -ac 1 "$OUTPUT_PATH"

else
    echo "Error: 입력 경로가 존재하지 않습니다: $INPUT_PATH"
    exit 1
fi