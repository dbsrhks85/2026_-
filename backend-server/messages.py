# ────────────────────────────────────────────────────────────
# messages.py
# 서버 전체에서 사용하는 메시지 상수 모음
# 메시지 수정이 필요할 때 이 파일만 수정하면 됩니다.
# ────────────────────────────────────────────────────────────


class SttMessages:
    """stt_engine.py 관련 메시지"""
    FILE_NOT_FOUND      = "파일을 찾을 수 없습니다."
    EMPTY_TRANSCRIPT    = "음성을 인식하지 못했습니다."
    PROCESSING_ERROR    = "STT 처리 중 오류 발생: {error}"


class NlpMessages:
    """nlp_engine.py 관련 메시지"""
    EMPTY_TEXT          = "분류할 텍스트가 비어있습니다."
    JSON_PARSE_ERROR    = "GPT 응답을 JSON으로 파싱할 수 없습니다."
    PROCESSING_ERROR    = "NLP 분류 중 오류 발생: {error}"
    DEFAULT_TITLE       = "내용 없음"
    FAILED_TITLE        = "분류 실패"


class ApiMessages:
    """main.py API 응답 메시지"""
    REPORT_NOT_FOUND    = "해당 ID의 민원을 찾을 수 없습니다."
    STT_FAILED          = "음성 인식에 실패했습니다. 다시 시도해주세요."
    NLP_FAILED          = "민원 분류에 실패했습니다. 텍스트는 정상 변환되었습니다."
    REPORT_SUCCESS      = "민원이 성공적으로 접수되었습니다."
    RESOLVE_SUCCESS     = "success"
