import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:geolocator/geolocator.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'services/audio_normalizer.dart';
import 'constants.dart';

// ────────────────────────────────────────────────
// 에뮬레이터에서 PC 호스트(localhost)를 가리키는 주소
// ────────────────────────────────────────────────
const String _kServerUrl = 'http://10.0.2.2:8000';

// ── Cloud Dancer 디자인 시스템 ──────────────────────
class AppColors {
  // Cloud Dancer (PANTONE 11-4201 TCX) 기반 팔레트
  static const Color cloudDancer = Color(0xFFECEAE4);   // 메인 배경
  static const Color cloudSoft   = Color(0xFFF5F4F0);   // 카드 배경
  static const Color cloudDeep   = Color(0xFFD8D4CB);   // 구분선/보더
  static const Color cloudWarm   = Color(0xFFC8C3B5);   // 비활성 아이콘

  // 포인트 컬러 (민원이 넥타이 & 배지의 스틸 블루)
  static const Color accentBlue  = Color(0xFF3A6EA5);   // 주 액션
  static const Color accentLight = Color(0xFF5B8FCC);   // 호버/강조
  static const Color accentDeep  = Color(0xFF254E82);   // 헤더

  // 상태 컬러
  static const Color recordRed   = Color(0xFFE05252);   // 녹음 중
  static const Color successGreen= Color(0xFF4A9E7F);   // 성공
  static const Color textDark    = Color(0xFF2C2C2C);   // 기본 텍스트
  static const Color textMid     = Color(0xFF6E6B62);   // 보조 텍스트
  static const Color textLight   = Color(0xFF9E9B93);   // 힌트 텍스트
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI 민원 시스템',
      theme: ThemeData(
        fontFamily: 'Pretendard',
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.accentBlue,
          background: AppColors.cloudDancer,
        ),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  String _locationMessage = AppMessages.locationLoading;
  bool _isRecording = false;

  late final AudioRecorder _audioRecorder;
  late final AudioPlayer _audioPlayer;
  bool _initialized = false;
  String? _filePath;
  String? _normalizedFilePath;
  bool _isNormalizing = false;

  // STT 전송 상태
  bool _isSendingSTT = false;
  String? _sttSavedDir;

  // VAD(침묵 감지)를 위한 변수들
  StreamSubscription<Amplitude>? _amplitudeSub;
  int _silenceCounter = 0;
  final double _silenceThreshold = -35.0;
  final int _maxSilenceFrames = 20;

  // 애니메이션 컨트롤러
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _waveAnimation;

  @override
  void initState() {
    super.initState();

    // 맥동 애니메이션 (녹음 버튼)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // 파형 애니메이션 (음파 이펙트)
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _waveAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _waveController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }

  Future<void> _initializeApp() async {
    _audioRecorder = AudioRecorder();
    _audioPlayer = AudioPlayer();
    _initialized = true;
    await _determinePosition();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    _amplitudeSub?.cancel();
    if (_initialized) {
      _audioRecorder.dispose();
      _audioPlayer.dispose();
    }
    super.dispose();
  }

  Future<void> _determinePosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _locationMessage = AppMessages.locationServiceOff);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _locationMessage = AppMessages.locationPermDenied);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() => _locationMessage = AppMessages.locationPermForever);
        return;
      }

      setState(() => _locationMessage = AppMessages.locationLoading);

      late LocationSettings locationSettings;
      if (defaultTargetPlatform == TargetPlatform.android) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
          forceLocationManager: true,
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        );
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: locationSettings,
      );
      setState(() {
        _locationMessage = "위도: ${position.latitude.toStringAsFixed(5)}\n경도: ${position.longitude.toStringAsFixed(5)}";
      });
    } catch (e) {
      setState(() => _locationMessage = '${AppMessages.locationFailed}\n($e)');
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording(isAutoStopped: false);
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (await _audioRecorder.hasPermission()) {
      final directory = await getApplicationDocumentsDirectory();
      final path = '${directory.path}/report_${DateTime.now().millisecondsSinceEpoch}.m4a';

      const config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 44100,
        numChannels: 1,
        bitRate: 32000,
      );

      await _audioPlayer.stop();
      await _audioRecorder.start(config, path: path);

      setState(() {
        _isRecording = true;
        _filePath = null;
        _normalizedFilePath = null;
        _locationMessage = AppMessages.vadGuide;
      });

      _silenceCounter = 0;
      _amplitudeSub = _audioRecorder.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((amp) {
        if (amp.current < _silenceThreshold) {
          _silenceCounter++;
          if (_silenceCounter >= _maxSilenceFrames) {
            _stopRecording(isAutoStopped: true);
          }
        } else {
          _silenceCounter = 0;
        }
      });
    }
  }

  Future<void> _stopRecording({required bool isAutoStopped}) async {
    _amplitudeSub?.cancel();
    final path = await _audioRecorder.stop();

    setState(() {
      _isRecording = false;
      _filePath = path;
      _normalizedFilePath = null;
      _isNormalizing = true;
      _determinePosition();
    });

    _showSnack(isAutoStopped ? AppMessages.recordingAutoStop : AppMessages.recordingManualStop);

    if (path != null) {
      final normalizedPath = await AudioNormalizer.normalizeAudio(path);
      setState(() {
        _normalizedFilePath = normalizedPath;
        _isNormalizing = false;
      });

      if (mounted) {
        _showSnack(normalizedPath != null
            ? AppMessages.normalizeSuccess
            : AppMessages.normalizeFailed);
      }
    } else {
      setState(() => _isNormalizing = false);
    }

    _runSttTests(originalPath: path, normalizedPath: _normalizedFilePath);
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: AppColors.accentBlue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    );
  }

  Future<void> _runSttTests({
    required String? originalPath,
    required String? normalizedPath,
  }) async {
    if (originalPath == null) return;

    setState(() => _isSendingSTT = true);

    final directory = await getApplicationDocumentsDirectory();
    _sttSavedDir = directory.path;

    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .substring(0, 19);

    final filePath = normalizedPath ?? originalPath;
    final label = normalizedPath != null ? 'normalized' : 'original';

    final result = await _sendAudioToSTT(filePath: filePath, label: label);
    await _saveResultJson(
      result: result,
      label: label,
      filePath: filePath,
      timestamp: timestamp,
      saveDir: directory.path,
    );

    setState(() => _isSendingSTT = false);

    if (mounted) {
      _showSttResultDialog(
        result: result,
        label: label,
        savedDir: directory.path,
        timestamp: timestamp,
      );
    }
  }

  Future<Map<String, dynamic>> _sendAudioToSTT({
    required String filePath,
    required String label,
  }) async {
    try {
      final dio = Dio();
      final fileName = filePath.split('/').last;

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
        'lat': '37.0',
        'lng': '127.0',
      });

      final response = await dio.post(
        '$_kServerUrl/upload-audio',
        data: formData,
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );

      return Map<String, dynamic>.from(response.data as Map);
    } catch (e) {
      return {'success': false, 'stt_text': '', 'error': e.toString()};
    }
  }

  Future<void> _saveResultJson({
    required Map<String, dynamic> result,
    required String label,
    required String filePath,
    required String timestamp,
    required String saveDir,
  }) async {
    final payload = {
      'label': label,
      'file': filePath.split('/').last,
      'timestamp': timestamp,
      'success': result['success'],
      'stt_text': result['stt_text'] ?? '',
      'category': result['report']?['category'],
      'department': result['report']?['department'],
      'error': result['error'],
    };

    final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
    final savePath = '$saveDir/stt_result_${label}_$timestamp.json';
    await File(savePath).writeAsString(jsonStr, flush: true);
  }

  void _showSttResultDialog({
    required Map<String, dynamic>? result,
    required String label,
    required String savedDir,
    required String timestamp,
  }) {
    final text = result?['stt_text'] ?? '(없음)';
    final ok = result?['success'] == true;
    final category = result?['report']?['category'] ?? result?['category'] ?? '-';
    final department = result?['report']?['department'] ?? result?['department'] ?? '-';

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.cloudSoft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 헤더
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: ok ? AppColors.accentBlue.withOpacity(0.12) : AppColors.recordRed.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      ok ? Icons.check_circle_outline : Icons.error_outline,
                      color: ok ? AppColors.accentBlue : AppColors.recordRed,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'STT 결과',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // STT 텍스트 영역
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.cloudDancer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.cloudDeep),
                ),
                child: Text(
                  ok ? text : '오류: ${result?["error"]}',
                  style: TextStyle(
                    fontSize: 14,
                    color: ok ? AppColors.textDark : AppColors.recordRed,
                    height: 1.5,
                  ),
                ),
              ),

              if (ok) ...[
                const SizedBox(height: 14),
                // 분류 결과 칩
                Row(
                  children: [
                    _infoChip(Icons.category_outlined, '분류', category, AppColors.accentBlue),
                    const SizedBox(width: 8),
                    _infoChip(Icons.business_outlined, '부서', department, AppColors.successGreen),
                  ],
                ),
              ],

              const SizedBox(height: 20),
              // 저장 경로
              Text(
                '💾 $savedDir/stt_result_${label}_$timestamp.json',
                style: const TextStyle(fontSize: 9, color: AppColors.textLight),
              ),

              const SizedBox(height: 20),
              // 확인 버튼
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                  ),
                  child: const Text('확인', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w600)),
                  Text(value, style: TextStyle(fontSize: 12, color: AppColors.textDark, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _playRecording() async {
    if (_filePath != null) {
      try {
        await _audioPlayer.stop();
        await _audioPlayer.setSource(DeviceFileSource(_filePath!));
        await _audioPlayer.resume();
      } catch (e) {
        debugPrint("재생 에러: $e");
      }
    }
  }

  Future<void> _playNormalizedRecording() async {
    if (_normalizedFilePath != null) {
      try {
        await _audioPlayer.stop();
        await _audioPlayer.setSource(DeviceFileSource(_normalizedFilePath!));
        await _audioPlayer.resume();
      } catch (e) {
        debugPrint("정규화 재생 에러: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cloudDancer,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Layer 1: 민원이 캐릭터 (배경색 위, UI 아래) ────────
            Positioned.fill(
              child: Align(
                alignment: const Alignment(0, -0.45), // 화면 위쪽으로 더 올림
                child: AnimatedBuilder(
                  animation: _isRecording ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
                  builder: (context, child) => Transform.scale(
                    scale: _isRecording ? _pulseAnimation.value : 1.0,
                    child: child,
                  ),
                  child: Builder(
                    builder: (context) {
                      // 화면 너비의 190%를 최대값으로 제한 (2배 크기)
                      final size = (MediaQuery.of(context).size.width * 1.9).clamp(0.0, 1120.0);
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          // 녹음 중 파동 이펙트
                          if (_isRecording)
                            AnimatedBuilder(
                              animation: _waveAnimation,
                              builder: (context, _) => Container(
                                width: size + 60 + (_waveAnimation.value * 48),
                                height: size + 60 + (_waveAnimation.value * 48),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.recordRed.withOpacity(
                                      0.07 - _waveAnimation.value * 0.05),
                                ),
                              ),
                            ),
                          // 민원이 이미지 (화면 너비 기준 4배 크기)
                          Image.asset(
                            'assets/images/minwoni_clouddancer_sizeup.png',
                            width: size,
                            height: size,
                            fit: BoxFit.contain,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),

            // ── Layer 2: UI 레이아웃 (헤더, 카드, 버튼) ──────────
            Column(
              children: [
                _buildHeader(),
                Expanded(child: _buildCenterContent()),
                _buildLocationCard(),
                _buildBottomPanel(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── 헤더 ──────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          // 앱 로고/이름
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.accentBlue,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.smart_toy_outlined, color: Colors.white, size: 14),
                SizedBox(width: 5),
                Text(AppMessages.brandName, style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              ],
            ),
          ),
          const Spacer(),
          // STT 전송 중 인디케이터
          if (_isSendingSTT)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.accentBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.accentBlue.withOpacity(0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accentBlue,
                    ),
                  ),
                  SizedBox(width: 6),
                  Text(AppMessages.analyzingBadge, style: TextStyle(fontSize: 11, color: AppColors.accentBlue, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── 캐릭터 배지 + 상태 메시지 (캐릭터는 Stack 레이어에서 별도 렌더링) ─
  Widget _buildCenterContent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end, // 하단 정렬 → 캐릭터 발 아래에 위치
      children: [
        // 캐릭터 이름 배지
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.accentBlue,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.accentBlue.withOpacity(0.25),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified_outlined, size: 12, color: Colors.white70),
              SizedBox(width: 5),
              Text(AppMessages.mascotName,
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
              SizedBox(width: 5),
              Text(AppMessages.mascotSubtitle,
                  style: TextStyle(color: Colors.white70, fontSize: 10)),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 상태 메시지 카드
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.cloudSoft.withOpacity(0.92), // 살짝 투명 → 캐릭터가 은은하게 비침
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.cloudDeep),
          ),
          child: Column(
            children: [
              if (_isRecording) ...[
                // 파형 애니메이션 바
                AnimatedBuilder(
                  animation: _waveAnimation,
                  builder: (context, _) => _buildWaveBars(),
                ),
                const SizedBox(height: 10),
              ],
              Text(
                _isRecording ? AppMessages.listeningMain : (_isSendingSTT ? AppMessages.analyzingMain : AppMessages.idleGuide),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _isRecording ? AppColors.recordRed : AppColors.textDark,
                ),
              ),
              if (!_isRecording && !_isSendingSTT)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    AppMessages.idleSubGuide,
                    style: TextStyle(fontSize: 11, color: AppColors.textLight),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // 파형 바 시각화
  Widget _buildWaveBars() {
    final heights = [0.4, 0.7, 1.0, 0.6, 0.9, 0.5, 0.8, 0.4, 0.7, 1.0, 0.6, 0.5];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(heights.length, (i) {
        final phase = (_waveAnimation.value + i * 0.15) % 1.0;
        final h = (heights[i] * 0.5 + phase * 0.5).clamp(0.2, 1.0);
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: 4,
          height: 24 * h,
          decoration: BoxDecoration(
            color: AppColors.recordRed.withOpacity(0.6 + h * 0.4),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  // ── GPS 카드 ──────────────────────────────────────────────
  Widget _buildLocationCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cloudSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cloudDeep),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.accentBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.location_on_outlined, color: AppColors.accentBlue, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _locationMessage,
              style: const TextStyle(fontSize: 12, color: AppColors.textMid, height: 1.4),
            ),
          ),
          GestureDetector(
            onTap: _determinePosition,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.cloudDeep.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.refresh, size: 14, color: AppColors.textMid),
            ),
          ),
        ],
      ),
    );
  }

  // ── 하단 버튼 패널 ─────────────────────────────────────────
  Widget _buildBottomPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      decoration: BoxDecoration(
        color: AppColors.cloudSoft,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppColors.cloudDeep, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 드래그 핸들
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: AppColors.cloudDeep,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // 버튼 행
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 원본 재생 버튼
              if (!_isRecording && _filePath != null)
                _buildPlayButton(
                  onTap: _playRecording,
                  label: '원본',
                  icon: Icons.volume_up_outlined,
                  color: AppColors.successGreen,
                  size: 52,
                ),

              if (!_isRecording && _filePath != null)
                const SizedBox(width: 16),

              // 메인 녹음 버튼
              _buildMainRecordButton(),

              if (!_isRecording && _filePath != null)
                const SizedBox(width: 16),

              // 정규화 재생 버튼
              if (!_isRecording && _filePath != null)
                _isNormalizing
                    ? _buildLoadingButton(size: 52)
                    : (_normalizedFilePath != null
                        ? _buildPlayButton(
                            onTap: _playNormalizedRecording,
                            label: '정규화',
                            icon: Icons.tune_outlined,
                            color: AppColors.accentBlue,
                            size: 52,
                          )
                        : const SizedBox(width: 52)),
            ],
          ),

          const SizedBox(height: 12),

          // 버튼 설명 레이블
          Text(
            _isRecording ? AppMessages.hintTapToStop : AppMessages.hintTapToRecord,
            style: const TextStyle(fontSize: 11, color: AppColors.textLight),
          ),
        ],
      ),
    );
  }

  // 메인 녹음/정지 버튼
  Widget _buildMainRecordButton() {
    return GestureDetector(
      onTap: _toggleRecording,
      child: AnimatedBuilder(
        animation: _isRecording ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
        builder: (context, child) {
          return Transform.scale(
            scale: _isRecording ? _pulseAnimation.value : 1.0,
            child: child,
          );
        },
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _isRecording
                  ? [AppColors.recordRed, Color(0xFFC03030)]
                  : [AppColors.accentLight, AppColors.accentBlue],
            ),
            boxShadow: [
              BoxShadow(
                color: (_isRecording ? AppColors.recordRed : AppColors.accentBlue).withOpacity(0.35),
                blurRadius: 16,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
            color: Colors.white,
            size: 34,
          ),
        ),
      ),
    );
  }

  // 재생 버튼 (원본 / 정규화)
  Widget _buildPlayButton({
    required VoidCallback onTap,
    required String label,
    required IconData icon,
    required Color color,
    required double size,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.1),
              border: Border.all(color: color.withOpacity(0.4), width: 1.5),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 5),
          Text(label, style: TextStyle(fontSize: 10, color: AppColors.textMid, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // 로딩 버튼 (정규화 처리 중)
  Widget _buildLoadingButton({required double size}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.cloudDeep.withOpacity(0.3),
            border: Border.all(color: AppColors.cloudDeep, width: 1.5),
          ),
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentBlue),
            ),
          ),
        ),
        const SizedBox(height: 5),
        const Text(AppMessages.labelProcessing, style: TextStyle(fontSize: 10, color: AppColors.textLight)),
      ],
    );
  }
}