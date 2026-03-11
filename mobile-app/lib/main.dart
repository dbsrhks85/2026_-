import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:geolocator/geolocator.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:async'; // VAD 타이머 및 스트림 처리를 위해 추가
import 'services/audio_normalizer.dart';

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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
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

class _MainScreenState extends State<MainScreen> {
  String _locationMessage = "현재 위치를 불러오는 중...";
  bool _isRecording = false;
  
  late final AudioRecorder _audioRecorder;
  late final AudioPlayer _audioPlayer;
  bool _initialized = false;
  String? _filePath;
  String? _normalizedFilePath;
  bool _isNormalizing = false;

  // VAD(침묵 감지)를 위한 변수들
  StreamSubscription<Amplitude>? _amplitudeSub;
  int _silenceCounter = 0;
  final double _silenceThreshold = -35.0; // 조용한 상태를 판별할 데시벨 (필요시 조절)
  final int _maxSilenceFrames = 20; // 100ms * 20 = 2초간 침묵 시 자동 종료

  @override
  void initState() {
    super.initState();
    // UI가 먼저 렌더링된 뒤에 초기화 수행
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }

  /// 오디오 레코더/플레이어 초기화 + 위치 가져오기 (UI 렌더링 이후 실행)
  Future<void> _initializeApp() async {
    _audioRecorder = AudioRecorder();
    _audioPlayer = AudioPlayer();
    _initialized = true;
    await _determinePosition();
  }

  @override
  void dispose() {
    _amplitudeSub?.cancel(); // 메모리 누수 방지
    if (_initialized) {
      _audioRecorder.dispose();
      _audioPlayer.dispose();
    }
    super.dispose();
  }

  Future<void> _determinePosition() async {
    try {
      // 1. 위치 서비스 활성화 확인
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _locationMessage = "위치 서비스가 비활성화되어 있습니다.\n기기 설정에서 위치를 켜주세요.");
        return;
      }

      // 2. 위치 권한 확인 및 요청
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _locationMessage = "위치 권한이 거부되었습니다.");
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() => _locationMessage = "위치 권한이 영구 거부되었습니다.\n앱 설정에서 권한을 허용해주세요.");
        return;
      }

      // 3. 위치 가져오기
      setState(() => _locationMessage = "현재 위치를 불러오는 중...");

      // Android에서는 LocationSettings를 명시적으로 지정
      late LocationSettings locationSettings;
      if (defaultTargetPlatform == TargetPlatform.android) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
          forceLocationManager: true, // FusedLocationProvider 대신 LocationManager 사용
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
        _locationMessage = "위도: ${position.latitude}\n경도: ${position.longitude}";
      });
    } catch (e) {
      setState(() => _locationMessage = "위치 정보를 가져오지 못했습니다.\n($e)");
    }
  }

  // 녹음 시작/중단 통합 컨트롤러
  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording(isAutoStopped: false);
    } else {
      await _startRecording();
    }
  }

  // 🎙️ 1. 녹음 시작 및 VAD 적용
  Future<void> _startRecording() async {
    if (await _audioRecorder.hasPermission()) {
      final directory = await getApplicationDocumentsDirectory();
      final path = '${directory.path}/report_${DateTime.now().millisecondsSinceEpoch}.m4a';
      
      // 16kHz, Mono 고정 (Whisper AI 최적화 및 노이즈 방지)
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
        _locationMessage = "듣고 있습니다...\n(2초간 말씀이 없으시면 자동 전송됩니다)";
      });

      // VAD(침묵 감지) 모니터링 시작 (0.1초마다 볼륨 체크)
      _silenceCounter = 0;
      _amplitudeSub = _audioRecorder.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((amp) {
        if (amp.current < _silenceThreshold) {
          _silenceCounter++;
          if (_silenceCounter >= _maxSilenceFrames) {
            _stopRecording(isAutoStopped: true); // 2초 연속 침묵 시 강제 종료
          }
        } else {
          _silenceCounter = 0; // 소리가 들리면 카운터 초기화
        }
      });
    }
  }

  // ⏹️ 2. 녹음 종료 + 정규화 실행
  Future<void> _stopRecording({required bool isAutoStopped}) async {
    _amplitudeSub?.cancel(); // 볼륨 감지 중단
    final path = await _audioRecorder.stop();

    setState(() {
      _isRecording = false;
      _filePath = path;
      _normalizedFilePath = null;
      _isNormalizing = true;
      _determinePosition(); // 화면을 다시 원래 GPS 좌표로 복구
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(isAutoStopped ? "말씀이 끝나서 자동으로 접수를 준비합니다." : "녹음이 완료되었습니다. 정규화 중...")),
    );

    // 녹음 완료 후 음성 정규화 실행
    if (path != null) {
      final normalizedPath = await AudioNormalizer.normalizeAudio(path);
      setState(() {
        _normalizedFilePath = normalizedPath;
        _isNormalizing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(normalizedPath != null
                ? '음성 정규화 완료! 원본/정규화 재생을 비교해보세요.'
                : '정규화 실패 — 원본 파일로 진행합니다.'),
          ),
        );
      }
    } else {
      setState(() => _isNormalizing = false);
    }

    // 녹음이 완료되면 FastAPI로 스트리밍 전송 시작
    _streamToFastAPI(path);
  }

  // 🚀 3. FastAPI 스트리밍 전송 로직 (뼈대)
  void _streamToFastAPI(String? path) {
    if (path == null) return;
    
    final file = File(path);
    final stream = file.openRead(); // 파일을 한 번에 읽지 않고 스트림으로 조각내서 읽음

    print("FastAPI로 전송을 시작합니다: $path");
    
    stream.listen(
      (List<int> chunk) {
        // TODO: 여기서 WebSocket이나 HTTP Chunked 방식으로 서버에 데이터를 쏩니다.
        // 예: webSocket.add(chunk);
        print("전송 중... 청크 크기: ${chunk.length} bytes");
      },
      onDone: () {
        print("FastAPI 전송이 완료되었습니다.");
      },
      onError: (e) {
        print("스트리밍 전송 에러: $e");
      }
    );
  }

  // 🔊 원본 녹음 재생
  Future<void> _playRecording() async {
    if (_filePath != null) {
      try {
        await _audioPlayer.stop(); 
        await _audioPlayer.setSource(DeviceFileSource(_filePath!)); 
        await _audioPlayer.resume(); 
      } catch (e) {
        print("재생 에러: $e");
      }
    }
  }

  // 🔊 정규화된 녹음 재생
  Future<void> _playNormalizedRecording() async {
    if (_normalizedFilePath != null) {
      try {
        await _audioPlayer.stop();
        await _audioPlayer.setSource(DeviceFileSource(_normalizedFilePath!));
        await _audioPlayer.resume();
      } catch (e) {
        print("정규화 재생 에러: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blueAccent,
        title: const Text('AI 음성 민원 접수', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: Colors.grey[200],
              width: double.infinity,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_isRecording ? Icons.mic : Icons.location_on, size: 60, color: _isRecording ? Colors.red : Colors.blueAccent),
                  const SizedBox(height: 16),
                  Text(_locationMessage, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: _toggleRecording,
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: _isRecording ? Colors.red : Colors.blue,
                    child: Icon(_isRecording ? Icons.stop : Icons.mic, color: Colors.white, size: 40),
                  ),
                ),
                if (!_isRecording && _filePath != null) ...[
                  const SizedBox(width: 20),
                  // 원본 재생 버튼 (초록)
                  GestureDetector(
                    onTap: _playRecording,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircleAvatar(
                          radius: 30,
                          backgroundColor: Colors.green,
                          child: Icon(Icons.play_arrow, color: Colors.white),
                        ),
                        const SizedBox(height: 4),
                        Text('원본', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 정규화 재생 버튼 (보라) 또는 로딩 인디케이터
                  if (_isNormalizing)
                    const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: Colors.grey,
                          child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)),
                        ),
                        SizedBox(height: 4),
                        Text('처리 중...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    )
                  else if (_normalizedFilePath != null)
                    GestureDetector(
                      onTap: _playNormalizedRecording,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircleAvatar(
                            radius: 30,
                            backgroundColor: Colors.deepPurple,
                            child: Icon(Icons.play_arrow, color: Colors.white),
                          ),
                          const SizedBox(height: 4),
                          Text('정규화', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          )
        ],
      ),
    );
  }
}