import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../models/detection_result.dart';
import '../models/manual_blur_box.dart';
import '../services/face_detector_service.dart';
import '../services/plate_detector_service.dart';
import '../services/card_detector_service.dart';
import '../services/shipping_label_detector_service.dart';
import '../services/privacy_detector_service.dart';
import '../services/blur_service.dart';
import 'blur_editor_screen.dart';

class DetectionSummaryScreen extends StatefulWidget {
  final File imageFile;

  const DetectionSummaryScreen({
    super.key,
    required this.imageFile,
  });

  @override
  State<DetectionSummaryScreen> createState() => _DetectionSummaryScreenState();
}

class _DetectionSummaryScreenState extends State<DetectionSummaryScreen> {
  // ── 서비스 ──────────────────────────────────────────────────────────
  final _faceService          = FaceDetectorService();
  final _plateService         = PlateDetectorService();
  final _cardService          = CardDetectorService();
  final _shippingLabelService = ShippingLabelDetectorService();
  final _privacyService       = PrivacyDetectorService();
  final _blurService          = BlurService();

  // ── 탐지 결과 ────────────────────────────────────────────────────────
  List<DetectionResult> _detections    = [];
  List<DetectionResult> _ocrDetections = [];

  // ── 이미지 정보 ──────────────────────────────────────────────────────
  Uint8List? _originalBytes;
  Size _imageSize = Size.zero;

  // ── UI 상태 ──────────────────────────────────────────────────────────
  bool   _isProcessing     = true;
  bool   _isApiProcessing  = false;
  bool   _apiDetectionDone = false;
  String _statusMessage    = '분석 중...';

  // ── InteractiveViewer ────────────────────────────────────────────────
  final _transformationController = TransformationController();

  // ── 탭 vs 드래그 구분 ────────────────────────────────────────────────
  Offset? _panStartPosition;
  static const double _kTapSlop = 10.0; // 이 픽셀 이내면 탭으로 간주

  // ── 개별 ON/OFF ──────────────────────────────────────────────────────
  final Map<int, bool> _detectionEnabled = {};
  final Map<int, bool> _ocrEnabled       = {};

  // ── 현재 스케일 ───────────────────────────────────────────────────────
  double get _currentScale =>
      _transformationController.value.getMaxScaleOnAxis();

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(() {
      setState(() {});
    });
    _analyze();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _faceService.close();
    _plateService.close();
    _cardService.close();
    _privacyService.close();
    _shippingLabelService.close();
    super.dispose();
  }

  // ── 기본 분석 ──────────────────────────────────────────────────────
  Future<void> _analyze() async {
    try {
      _originalBytes = await widget.imageFile.readAsBytes();
      final decoded  = await decodeImageFromList(_originalBytes!);
      _imageSize     = Size(decoded.width.toDouble(), decoded.height.toDouble());

      setState(() => _statusMessage = '얼굴을 찾고 있어요...');
      final inputImage  = InputImage.fromFile(widget.imageFile);
      final faceResults = await _faceService.detect(inputImage);

      setState(() => _statusMessage = '번호판을 확인하고 있어요...');
      final plateResults = await _plateService.detect(widget.imageFile);

      setState(() => _statusMessage = 'OCR 개인정보를 분석하고 있어요...');
      final ocrResults = await _privacyService.detectFromRegion(
        widget.imageFile,
        Rect.fromLTWH(0, 0, _imageSize.width, _imageSize.height),
        _imageSize.width,
        _imageSize.height,
      );

      final allDetections = [...faceResults, ...plateResults];
      for (int i = 0; i < allDetections.length; i++) _detectionEnabled[i] = true;
      for (int i = 0; i < ocrResults.length; i++) _ocrEnabled[i] = true;

      setState(() {
        _detections    = allDetections;
        _ocrDetections = ocrResults;
        _isProcessing  = false;
      });
    } catch (e) {
      setState(() {
        _isProcessing  = false;
        _statusMessage = '오류가 발생했습니다: $e';
      });
    }
  }

  // ── API 탐지 ──────────────────────────────────────────────────────
  bool _overlaps(Rect a, Rect b) =>
      a.left < b.right  && a.right  > b.left &&
          a.top  < b.bottom && a.bottom > b.top;

  Future<void> _runApiDetection() async {
    setState(() => _isApiProcessing = true);
    try {
      final cardResults     = await _cardService.detect(widget.imageFile);
      final shippingResults = await _shippingLabelService.detect(widget.imageFile);

      final plateResults = _detections
          .where((d) => d.type == DetectionType.licensePlate)
          .toList();

      final filteredCards = cardResults
          .where((c) => plateResults
          .every((p) => !_overlaps(c.boundingBox, p.boundingBox)))
          .toList();

      final newDetections = [..._detections, ...filteredCards, ...shippingResults];
      for (int i = _detections.length; i < newDetections.length; i++) {
        _detectionEnabled[i] = true;
      }

      setState(() {
        _detections       = newDetections;
        _apiDetectionDone = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('카드 ${filteredCards.length}개, 운송장 ${shippingResults.length}개 탐지 완료'),
            backgroundColor: const Color(0xFF2D2D2D),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('API 탐지 오류: $e'), backgroundColor: Colors.red.shade900),
        );
      }
    } finally {
      setState(() => _isApiProcessing = false);
    }
  }

  // ── 탭 처리: 드래그 거리 짧으면 탭으로 간주 ──────────────────────────
  void _onPanStart(DragStartDetails d) {
    _panStartPosition = d.localPosition;
  }

  void _onPanEnd(DragEndDetails d, Size displaySize) {
    if (_panStartPosition == null) return;
    // 손가락을 뗀 위치를 알 수 없으므로 panStart 기준으로만 처리
    // → onTapUp으로 대체 처리 (아래 _onTapUp 사용)
    _panStartPosition = null;
  }

  void _onTapUp(TapUpDetails d, Size displaySize) {
    // InteractiveViewer 변환 역행렬로 실제 이미지 좌표 계산
    final matrix   = _transformationController.value;
    final inverted = Matrix4.inverted(matrix);
    final local    = MatrixUtils.transformPoint(inverted, d.localPosition);

    final sx    = _imageSize.width  / displaySize.width;
    final sy    = _imageSize.height / displaySize.height;
    final imgPt = Offset(local.dx * sx, local.dy * sy);

    // 자동 탐지 박스 탭 확인
    for (int i = 0; i < _detections.length; i++) {
      if (_detections[i].boundingBox.contains(imgPt)) {
        setState(() => _detectionEnabled[i] = !(_detectionEnabled[i] ?? true));
        return;
      }
    }
    // OCR 박스 탭 확인
    for (int i = 0; i < _ocrDetections.length; i++) {
      if (_ocrDetections[i].boundingBox.contains(imgPt)) {
        setState(() => _ocrEnabled[i] = !(_ocrEnabled[i] ?? true));
        return;
      }
    }
  }

  // ── 편집 화면으로 이동 ─────────────────────────────────────────────
  void _goToEditor() {
    final activeDetections = [
      for (int i = 0; i < _detections.length; i++)
        if (_detectionEnabled[i] ?? true) _detections[i],
    ];
    final activeOcr = [
      for (int i = 0; i < _ocrDetections.length; i++)
        if (_ocrEnabled[i] ?? true) _ocrDetections[i],
    ];

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BlurEditorScreen(
          imageFile:       widget.imageFile,
          imageSize:       _imageSize,
          originalBytes:   _originalBytes!,
          detections:      activeDetections,
          ocrDetections:   activeOcr,
          typeBlurEnabled: {
            DetectionType.face:          true,
            DetectionType.licensePlate:  true,
            DetectionType.document:      true,
            DetectionType.card:          true,
            DetectionType.shippingLabel: true,
            DetectionType.manual:        true,
          },
          blurService: _blurService,
        ),
      ),
    );
  }

  // ── 카운트 ───────────────────────────────────────────────────────
  int get _enabledCount =>
      _detectionEnabled.values.where((v) => v).length +
          _ocrEnabled.values.where((v) => v).length;
  int get _totalCount => _detections.length + _ocrDetections.length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F0F),
        foregroundColor: Colors.white,
        title: const Text('탐지 결과', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: _isProcessing ? _buildLoading() : _buildContent(),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Color(0xFF6C63FF)),
          const SizedBox(height: 24),
          Text(_statusMessage,
              style: const TextStyle(color: Colors.white, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            // 확대 중에도 스크롤 허용 (이미지 내부는 InteractiveViewer가 처리)
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── 이미지 미리보기 ──────────────────────────────────
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final displayWidth  = constraints.maxWidth;
                      final displayHeight =
                          _imageSize.height * displayWidth / _imageSize.width;
                      final displaySize = Size(displayWidth, displayHeight);

                      return SizedBox(
                        width:  displayWidth,
                        height: displayHeight,
                        child: GestureDetector(
                          // 탭은 onTapUp으로만 처리 → 드래그와 명확히 분리
                          onTapUp: (d) => _onTapUp(d, displaySize),
                          child: InteractiveViewer(
                            transformationController: _transformationController,
                            minScale:     1.0,
                            maxScale:     5.0,
                            clipBehavior: Clip.hardEdge,
                            // InteractiveViewer가 pan/scale 제스처 담당
                            // GestureDetector의 onTapUp은 짧은 탭만 받음
                            child: SizedBox(
                              width:  displayWidth,
                              height: displayHeight,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: Image.memory(
                                        _originalBytes!, fit: BoxFit.fill),
                                  ),

                                  // 자동 탐지 박스
                                  ..._detections.asMap().entries.map((e) {
                                    final i       = e.key;
                                    final d       = e.value;
                                    final enabled = _detectionEnabled[i] ?? true;
                                    final sx = displayWidth  / _imageSize.width;
                                    final sy = displayHeight / _imageSize.height;
                                    final dr = Rect.fromLTWH(
                                      d.boundingBox.left   * sx,
                                      d.boundingBox.top    * sy,
                                      d.boundingBox.width  * sx,
                                      d.boundingBox.height * sy,
                                    );

                                    final scale     = _currentScale;
                                    final labelSize = (10.0 / scale).clamp(5.0, 10.0);
                                    final padH      = (5.0  / scale).clamp(2.0, 5.0);
                                    final padV      = (2.0  / scale).clamp(1.0, 2.0);
                                    final topOffset = -(20.0 / scale).clamp(10.0, 20.0);

                                    return Positioned(
                                      left: dr.left, top: dr.top,
                                      width: dr.width, height: dr.height,
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Container(
                                            decoration: BoxDecoration(
                                              border: Border.all(
                                                color: enabled
                                                    ? d.typeColor
                                                    : d.typeColor.withValues(alpha: 0.25),
                                                width: 2,
                                              ),
                                              color: enabled
                                                  ? d.typeColor.withValues(alpha: 0.15)
                                                  : Colors.transparent,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                          ),
                                          Positioned(
                                            top: topOffset, left: 0,
                                            child: Container(
                                              padding: EdgeInsets.symmetric(
                                                  horizontal: padH,
                                                  vertical: padV),
                                              decoration: BoxDecoration(
                                                color: enabled
                                                    ? d.typeColor
                                                    : d.typeColor.withValues(alpha: 0.25),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                enabled
                                                    ? d.typeLabel
                                                    : '${d.typeLabel} OFF',
                                                style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: labelSize,
                                                    fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),

                                  // OCR 박스
                                  ..._ocrDetections.asMap().entries.map((e) {
                                    final i       = e.key;
                                    final d       = e.value;
                                    final enabled = _ocrEnabled[i] ?? true;
                                    final sx = displayWidth  / _imageSize.width;
                                    final sy = displayHeight / _imageSize.height;
                                    final dr = Rect.fromLTWH(
                                      d.boundingBox.left   * sx,
                                      d.boundingBox.top    * sy,
                                      d.boundingBox.width  * sx,
                                      d.boundingBox.height * sy,
                                    );
                                    return Positioned(
                                      left: dr.left, top: dr.top,
                                      width: dr.width, height: dr.height,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: enabled
                                                ? const Color(0xFFFF6B6B)
                                                : const Color(0xFFFF6B6B)
                                                .withValues(alpha: 0.25),
                                            width: 1.5,
                                          ),
                                          color: enabled
                                              ? const Color(0xFFFF6B6B)
                                              .withValues(alpha: 0.15)
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(3),
                                        ),
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 6),
                const Center(
                  child: Text(
                    '박스를 탭하면 개별로 블러를 켜고 끌 수 있어요  |  핀치로 확대',
                    style: TextStyle(color: Color(0xFF555555), fontSize: 11),
                  ),
                ),

                const SizedBox(height: 16),

                // ── 요약 배너 ────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _totalCount > 0
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle_outline,
                        color: _totalCount > 0
                            ? const Color(0xFFFF6B6B)
                            : const Color(0xFF43E97B),
                        size: 32,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _totalCount > 0
                                  ? '총 $_totalCount개 발견'
                                  : '개인정보가 발견되지 않았어요',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold),
                            ),
                            if (_totalCount > 0)
                              Text(
                                '$_enabledCount개 블러 처리 예정',
                                style: const TextStyle(
                                    color: Color(0xFF888888), fontSize: 13),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── API 탐지 버튼 ────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isApiProcessing ? null : _runApiDetection,
                    icon: _isApiProcessing
                        ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                        : const Icon(Icons.search),
                    label: Text(
                      _isApiProcessing
                          ? 'API 탐지 중...'
                          : _apiDetectionDone
                          ? 'API 재탐지 (카드 · 운송장)'
                          : 'API 탐지 시작 (카드 · 운송장)',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2D2D2D),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── 개별 항목 리스트 ─────────────────────────────────
                if (_totalCount > 0) ...[
                  const Text('탐지 항목',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                  const SizedBox(height: 8),

                  ..._detections.asMap().entries.map((e) {
                    final i       = e.key;
                    final d       = e.value;
                    final enabled = _detectionEnabled[i] ?? true;
                    return _buildItemTile(
                      color:    d.typeColor,
                      label:    '${d.typeLabel} #${i + 1}',
                      sub:      '신뢰도 ${(d.confidence * 100).toStringAsFixed(0)}%',
                      enabled:  enabled,
                      onToggle: (val) =>
                          setState(() => _detectionEnabled[i] = val),
                    );
                  }),

                  ..._ocrDetections.asMap().entries.map((e) {
                    final i       = e.key;
                    final d       = e.value;
                    final enabled = _ocrEnabled[i] ?? true;
                    return _buildItemTile(
                      color:    const Color(0xFFFF6B6B),
                      label:    d.privacyTexts.isNotEmpty
                          ? d.privacyTexts.first
                          : 'OCR #${i + 1}',
                      sub:      'OCR 개인정보',
                      enabled:  enabled,
                      onToggle: (val) =>
                          setState(() => _ocrEnabled[i] = val),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),

        // ── 하단 버튼 ────────────────────────────────────────────────
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _goToEditor,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('편집하기',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildItemTile({
    required Color   color,
    required String  label,
    required String  sub,
    required bool    enabled,
    required void Function(bool) onToggle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: enabled
                ? color.withValues(alpha: 0.4)
                : const Color(0xFF2D2D2D),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 10, height: 10,
              decoration: BoxDecoration(
                color: enabled ? color : const Color(0xFF444444),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: enabled
                              ? Colors.white
                              : const Color(0xFF555555),
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  Text(sub,
                      style: const TextStyle(
                          color: Color(0xFF666666), fontSize: 11)),
                ],
              ),
            ),
            Switch(
              value:            enabled,
              onChanged:        onToggle,
              activeThumbColor: color,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }
}