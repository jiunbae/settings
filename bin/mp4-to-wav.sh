#!/usr/bin/env bash
# mp4_to_wav16k.sh
# 주어진 디렉토리에서 .mp4 파일을 찾아 16kHz mono WAV로 변환

set -euo pipefail

usage() {
  cat <<'USAGE'
사용법: mp4_to_wav16k.sh [-y] <디렉토리>
  -y  기존 WAV가 있어도 덮어쓰기(ffmpeg -y). 기본은 덮어쓰지 않음(ffmpeg -n).
예:   mp4_to_wav16k.sh /path/to/folder
      mp4_to_wav16k.sh -y "./내 동영상들"
USAGE
}

# 옵션 파싱
OVERWRITE="-n"
while getopts ":yh" opt; do
  case "$opt" in
    y) OVERWRITE="-y" ;;
    h) usage; exit 0 ;;
    \?) echo "알 수 없는 옵션: -$OPTARG" >&2; usage; exit 1 ;;
  esac
done
shift $((OPTIND-1))

# 인자 확인
if [[ $# -ne 1 ]]; then
  usage; exit 1
fi

ROOT="$1"

# ffmpeg 존재 확인
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "에러: ffmpeg가 설치되어 있지 않습니다. 설치 후 다시 시도하세요." >&2
  exit 1
fi

# 경로 확인
if [[ ! -d "$ROOT" ]]; then
  echo "에러: 디렉토리를 찾을 수 없습니다: $ROOT" >&2
  exit 1
fi

# 변환 실행
# - 하위 디렉토리 포함
# - 널 종단으로 공백/특수문자 파일명 안전 처리
# - 비디오 스트림은 제거(-vn), 16kHz(-ar 16000), 모노(-ac 1), 16-bit PCM(-acodec pcm_s16le)
# - 출력은 입력과 같은 폴더에 같은 이름의 .wav로 생성
converted=0
skipped=0
errors=0

while IFS= read -r -d '' f; do
  out="${f%.*}.wav"
  if [[ "$OVERWRITE" == "-n" && -e "$out" ]]; then
    echo "건너뜀(이미 존재): $out"
    ((skipped++)) || true
    continue
  fi

  echo "변환: $f -> $out"
  if ffmpeg -hide_banner -loglevel error -nostdin $OVERWRITE \
    -i "$f" -vn -ac 1 -ar 16000 -acodec pcm_s16le "$out"; then
    ((converted++)) || true
  else
    echo "에러: 변환 실패 -> $f" >&2
    ((errors++)) || true
  fi
done < <(find "$ROOT" -type f -iname '*.mp4' -print0)

echo "완료: 변환 ${converted}개, 건너뜀 ${skipped}개, 에러 ${errors}개"

# 변환이 하나라도 실패하면 종료 코드로 알린다.
# 그렇지 않으면 `mp4-to-wav.sh dir && start-training` 이 WAV 없이 진행된다.
(( errors == 0 ))