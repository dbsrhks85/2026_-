// ────────────────────────────────────────────────────────────
// constants.dart
// 앱 전체에서 사용하는 메시지 상수 모음
// 메시지 수정이 필요할 때 이 파일만 수정하면 됩니다.
// ────────────────────────────────────────────────────────────

class AppMessages {
  AppMessages._(); // 인스턴스 생성 방지

  // ── GPS / 위치 관련 ─────────────────────────────────────
  static const String locationLoading      = '현재 위치를 불러오는 중...';
  static const String locationServiceOff   = '위치 서비스가 비활성화되어 있습니다.\n기기 설정에서 위치를 켜주세요.';
  static const String locationPermDenied   = '위치 권한이 거부되었습니다.';
  static const String locationPermForever  = '위치 권한이 영구 거부되었습니다.\n앱 설정에서 권한을 허용해주세요.';
  static const String locationFailed       = '위치 정보를 가져오지 못했습니다.';

  // ── 녹음 상태 메시지 (스낵바) ───────────────────────────
  static const String recordingAutoStop    = '말씀이 끝나서 자동으로 접수를 준비합니다.';
  static const String recordingManualStop  = '녹음이 완료되었습니다. 정규화 중...';
  static const String normalizeSuccess     = '음성 정규화 완료! STT 서버로 전송 중...';
  static const String normalizeFailed      = '정규화 실패 — 원본 파일로 STT 진행합니다.';

  // ── 캐릭터 상태 메시지 (화면 중앙) ─────────────────────
  static const String idleGuide            = '버튼을 눌러 민원을 말씀해 주세요';
  static const String idleSubGuide         = '음성을 인식하여 자동으로 처리해 드릴게요';
  static const String listeningMain        = '듣고 있어요...';
  static const String analyzingMain        = 'AI가 분석 중이에요...';
  static const String vadGuide             = '듣고 있습니다...\n(2초간 말씀이 없으시면 자동 전송됩니다)';

  // ── 하단 버튼 설명 ──────────────────────────────────────
  static const String hintTapToRecord     = '탭하여 민원 접수 시작';
  static const String hintTapToStop       = '탭하여 녹음 종료';
  static const String labelOriginal       = '원본';
  static const String labelNormalized     = '정규화';
  static const String labelProcessing     = '처리 중';

  // ── STT 결과 다이얼로그 ─────────────────────────────────
  static const String dialogTitle         = 'STT 결과';
  static const String dialogConfirm       = '확인';
  static const String dialogNormalizedFile = '📂 정규화 파일';
  static const String dialogOriginalFile  = '📂 원본 파일 (정규화 실패)';
  static const String dialogSavedPath     = '💾 JSON 저장 경로';

  // ── 헤더 UI ─────────────────────────────────────────────
  static const String brandName           = 'GOV.AI';
  static const String analyzingBadge      = '분석 중';
  static const String mascotName          = '민원이';
  static const String mascotSubtitle      = 'AI 민원 도우미';
}
