#!/bin/bash

# 자동화 스크립트
# 클로드 세션 동기화 및 Obsidian 인덱싱 자동화

# 경로 설정
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_SCRIPT="$CURRENT_DIR/sync_claude_to_obsidian.py"
INDEX_SCRIPT="$CURRENT_DIR/link-context-docs.ts"
CLEANUP_SCRIPT="$CURRENT_DIR/cleanup_sessions.py"
VAULT_ROOT="${HOME}/Documents/s-lastorder"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 세션 동기화
sync_sessions() {
    log_message "세션 동기화 시작"
    python3 "$SYNC_SCRIPT"
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        log_message "세션 동기화 완료"
    else
        log_message "세션 동기화 실패 (exit code: $exit_code)"
        return 1
    fi
}

# 빈 세션 정리
cleanup_empty_sessions() {
    log_message "빈 세션 정리 시작"
    
    python3 "$CLEANUP_SCRIPT"
    local exit_code=$?
    
    log_message "정리 완료 (exit code: $exit_code)"
}

# 인덱싱 업데이트
update_indexes() {
    log_message "인덱싱 업데이트 시작"
    cd "$CURRENT_DIR"
    
    if [ -f "node_modules/.bin/tsx" ]; then
        npx tsx link-context-docs.ts
        local exit_code=$?
        
        if [ $exit_code -eq 0 ]; then
            log_message "인덱싱 업데이트 완료"
        else
            log_message "인덱싱 업데이트 실패 (exit code: $exit_code)"
            return 1
        fi
    else
        log_message "오류: tsx를 찾을 수 없음"
        return 1
    fi
}

# 전체 자동화 실행
full_automation() {
    log_message "전체 자동화 시작"
    
    sync_sessions
    local sync_result=$?
    
    if [ $sync_result -ne 0 ]; then
        log_message "동기화 실패로 인덱싱 스킵"
        return 1
    fi
    
    cleanup_empty_sessions
    local cleanup_result=$?
    
    if [ $cleanup_result -ne 0 ]; then
        log_message "정리 실패로 인덱싱 스킵"
        return 1
    fi
    
    update_indexes
    local index_result=$?
    
    if [ $index_result -ne 0 ]; then
        log_message "인덱싱 실패"
        return 1
    fi
    
    log_message "전체 자동화 완료"
    echo "=================================================="
    echo "요약:"
    echo "1. 세션 동기화: 완료"
    echo "2. 빈 세션 정리: 완료"
    echo "3. 인덱싱 업데이트: 완료"
    echo "=================================================="
}

# 메인 로직
main() {
    case "${1:-}" in
        "sync")
            sync_sessions
            ;;
        "cleanup")
            cleanup_empty_sessions
            ;;
        "index")
            update_indexes
            ;;
        "full"|"all")
            full_automation
            ;;
        *)
            echo "사용법: $0 {sync|cleanup|index|full}"
            echo ""
            echo "  sync    - 세션 동기화만 실행"
            echo "  cleanup - 빈 세션 정리만 실행"
            echo "  index   - 인덱싱 업데이트만 실행"
            echo "  full    - 전체 자동화 실행"
            echo ""
            echo "예시: bash $0 full"
            exit 1
            ;;
    esac
}

main "$@"
