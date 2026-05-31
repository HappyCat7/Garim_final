import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../models/detection_result.dart';
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
  final _faceService = FaceDetectorService();
  final _plateService = PlateDetectorService();
  final _cardService = CardDetectorService();
  final _shippingLabelService = ShippingLabelDetectorService();
  final _privacyService = PrivacyDetectorService();
  final _blurService = BlurService();

  List<DetectionResult> _detections = [];
  List<DetectionResult> _ocrDetections = [];

  Uint8List? _originalBytes;
  Size _imageSize = Size.zero;

  bool _isProcessing = true;
  bool _isApiProcessing = false;
  bool _apiDetectionDone = false;
  String _statusMessage = '분석 중...';

  final _transformationController = TransformationController();

  Offset? _panStartPosition;
  static const double _kTapSlop = 10.0;

  final Map<int, bool> _detectionEnabled = {};
  final Map<int, bool> _ocrEnabled = {};

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

  Future<void> _analyze() async {
    try {
      _originalBytes = await widget.imageFile.readAsBytes();

      final decoded = await decodeImageFromList(_originalBytes!);

      _imageSize = Size(
        decoded.width.toDouble(),
        decoded.height.toDouble(),
      );

      setState(() => _statusMessage = '얼굴을 찾고 있어요...');

      final inputImage = InputImage.fromFile(widget.imageFile);
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

      final allDetections = [
        ...faceResults,
        ...plateResults,
      ];

      for (int i = 0; i < allDetections.length; i++) {
        _detectionEnabled[i] = true;
      }

      for (int i = 0; i < ocrResults.length; i++) {
        _ocrEnabled[i] = true;
      }

      setState(() {
        _detections = allDetections;
        _ocrDetections = ocrResults;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = '오류가 발생했습니다: $e';
      });
    }
  }

  bool _overlaps(Rect a, Rect b) {
    return a.left < b.right &&
        a.right > b.left &&
        a.top < b.bottom &&
        a.bottom > b.top;
  }

  Future<void> _runApiDetection() async {
    setState(() => _isApiProcessing = true);

    try {
      final cardResults = await _cardService.detect(widget.imageFile);
      final shippingResults =
      await _shippingLabelService.detect(widget.imageFile);

      final plateResults = _detections
          .where((d) => d.type == DetectionType.licensePlate)
          .toList();

      final filteredCards = cardResults.where((card) {
        return plateResults.every(
              (plate) => !_overlaps(card.boundingBox, plate.boundingBox),
        );
      }).toList();

      final newDetections = [
        ..._detections,
        ...filteredCards,
        ...shippingResults,
      ];

      for (int i = _detections.length; i < newDetections.length; i++) {
        _detectionEnabled[i] = true;
      }

      setState(() {
        _detections = newDetections;
        _apiDetectionDone = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '카드 ${filteredCards.length}개, 운송장 ${shippingResults.length}개 탐지 완료',
            ),
            backgroundColor: const Color(0xFFDCEFF8),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('API 탐지 오류: $e'),
            backgroundColor: Colors.red.shade900,
          ),
        );
      }
    } finally {
      setState(() => _isApiProcessing = false);
    }
  }

  void _onPanStart(DragStartDetails details) {
    _panStartPosition = details.localPosition;
  }

  void _onPanEnd(DragEndDetails details, Size displaySize) {
    if (_panStartPosition == null) return;
    _panStartPosition = null;
  }

  void _onTapUp(TapUpDetails details, Size displaySize) {
    final matrix = _transformationController.value;
    final inverted = Matrix4.inverted(matrix);
    final local = MatrixUtils.transformPoint(
      inverted,
      details.localPosition,
    );

    final sx = _imageSize.width / displaySize.width;
    final sy = _imageSize.height / displaySize.height;

    final imgPoint = Offset(
      local.dx * sx,
      local.dy * sy,
    );

    for (int i = 0; i < _detections.length; i++) {
      if (_detections[i].boundingBox.contains(imgPoint)) {
        setState(() {
          _detectionEnabled[i] = !(_detectionEnabled[i] ?? true);
        });
        return;
      }
    }

    for (int i = 0; i < _ocrDetections.length; i++) {
      final detection = _ocrDetections[i];

      if (_containsDetectionPoint(detection, imgPoint)) {
        setState(() {
          _ocrEnabled[i] = !(_ocrEnabled[i] ?? true);
        });
        return;
      }
    }
  }

  bool _containsDetectionPoint(
      DetectionResult detection,
      Offset point,
      ) {
    final polygon = detection.polygon;

    if (polygon != null && polygon.length >= 3) {
      return _isPointInPolygon(point, polygon);
    }

    return detection.boundingBox.contains(point);
  }

  bool _isPointInPolygon(
      Offset point,
      List<Offset> polygon,
      ) {
    bool inside = false;
    int j = polygon.length - 1;

    for (int i = 0; i < polygon.length; i++) {
      final xi = polygon[i].dx;
      final yi = polygon[i].dy;
      final xj = polygon[j].dx;
      final yj = polygon[j].dy;

      final intersect = ((yi > point.dy) != (yj > point.dy)) &&
          (point.dx <
              (xj - xi) *
                  (point.dy - yi) /
                  ((yj - yi) == 0 ? 0.000001 : (yj - yi)) +
                  xi);

      if (intersect) {
        inside = !inside;
      }

      j = i;
    }

    return inside;
  }

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
          imageFile: widget.imageFile,
          imageSize: _imageSize,
          originalBytes: _originalBytes!,
          detections: activeDetections,
          ocrDetections: activeOcr,
          typeBlurEnabled: {
            DetectionType.face: true,
            DetectionType.licensePlate: true,
            DetectionType.document: true,
            DetectionType.card: true,
            DetectionType.shippingLabel: true,
            DetectionType.manual: true,
          },
          blurService: _blurService,
        ),
      ),
    );
  }

  int get _enabledCount {
    return _detectionEnabled.values.where((v) => v).length +
        _ocrEnabled.values.where((v) => v).length;
  }

  int get _totalCount {
    return _detections.length + _ocrDetections.length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFFFF),
        foregroundColor: const Color(0xFF1F2937),
        title: const Text(
          '탐지 결과',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
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
          const CircularProgressIndicator(
            color: Color(0xFF6C63FF),
          ),
          const SizedBox(height: 24),
          Text(
            _statusMessage,
            style: const TextStyle(
              color: Color(0xFF1F2937),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildImagePreview(),

                const SizedBox(height: 6),

                const Center(
                  child: Text(
                    '박스를 탭하면 개별로 블러를 켜고 끌 수 있어요  |  핀치로 확대',
                    style: TextStyle(
                      color: Color(0xFF555555),
                      fontSize: 11,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                _buildSummaryBanner(),

                const SizedBox(height: 16),

                _buildApiButton(),

                const SizedBox(height: 16),

                if (_totalCount > 0) _buildDetectionList(),
              ],
            ),
          ),
        ),

        _buildBottomButton(),
      ],
    );
  }

  Widget _buildImagePreview() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final displayWidth = constraints.maxWidth;
          final displayHeight =
              _imageSize.height * displayWidth / _imageSize.width;

          final displaySize = Size(displayWidth, displayHeight);

          return SizedBox(
            width: displayWidth,
            height: displayHeight,
            child: GestureDetector(
              onPanStart: _onPanStart,
              onPanEnd: (details) => _onPanEnd(details, displaySize),
              onTapUp: (details) => _onTapUp(details, displaySize),
              child: InteractiveViewer(
                transformationController: _transformationController,
                minScale: 1.0,
                maxScale: 5.0,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: displayWidth,
                  height: displayHeight,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Image.memory(
                          _originalBytes!,
                          fit: BoxFit.fill,
                        ),
                      ),

                      ..._detections.asMap().entries.map((entry) {
                        final index = entry.key;
                        final detection = entry.value;
                        final enabled = _detectionEnabled[index] ?? true;

                        final sx = displayWidth / _imageSize.width;
                        final sy = displayHeight / _imageSize.height;

                        final rect = Rect.fromLTWH(
                          detection.boundingBox.left * sx,
                          detection.boundingBox.top * sy,
                          detection.boundingBox.width * sx,
                          detection.boundingBox.height * sy,
                        );

                        final scale = _currentScale;
                        final labelSize = (10.0 / scale).clamp(5.0, 10.0);
                        final padH = (5.0 / scale).clamp(2.0, 5.0);
                        final padV = (2.0 / scale).clamp(1.0, 2.0);
                        final topOffset = -(20.0 / scale).clamp(10.0, 20.0);

                        return Positioned(
                          left: rect.left,
                          top: rect.top,
                          width: rect.width,
                          height: rect.height,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: enabled
                                        ? detection.typeColor
                                        : detection.typeColor
                                        .withValues(alpha: 0.25),
                                    width: 2,
                                  ),
                                  color: enabled
                                      ? detection.typeColor
                                      .withValues(alpha: 0.15)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              Positioned(
                                top: topOffset,
                                left: 0,
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: padH,
                                    vertical: padV,
                                  ),
                                  decoration: BoxDecoration(
                                    color: enabled
                                        ? detection.typeColor
                                        : detection.typeColor
                                        .withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    enabled
                                        ? detection.typeLabel
                                        : '${detection.typeLabel} OFF',
                                    style: TextStyle(
                                      color: Color(0xFF1F2937),
                                      fontSize: labelSize,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),

                      Positioned.fill(
                        child: CustomPaint(
                          painter: _OcrPolygonPainter(
                            detections: _ocrDetections,
                            enabledMap: _ocrEnabled,
                            imageSize: _imageSize,
                            displaySize: displaySize,
                            currentScale: _currentScale,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 16,
      ),
      decoration: BoxDecoration(
        color: Color(0xFFF7FAFC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            _totalCount > 0
                ? Icons.warning_amber_rounded
                : Icons.check_circle_outline,
            color: _totalCount > 0
                ? const Color(0xFF8FC9F7)
                : const Color(0xFF7DD3C7),
            size: 32,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _totalCount > 0 ? '총 $_totalCount개 발견' : '개인정보가 발견되지 않았어요',
                  style: const TextStyle(
                    color: Color(0xFF1F2937),
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_totalCount > 0)
                  Text(
                    '$_enabledCount개 블러 처리 예정',
                    style: const TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 13,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApiButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isApiProcessing ? null : _runApiDetection,
        icon: _isApiProcessing
            ? const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            color: Color(0xFF1F2937),
            strokeWidth: 2,
          ),
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
          backgroundColor: const Color(0xFFDCEFF8),
          foregroundColor: const Color(0xFF1F2937),
          padding: const EdgeInsets.symmetric(
            vertical: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildDetectionList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '탐지 항목',
          style: TextStyle(
            color: Color(0xFF1F2937),
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),

        const SizedBox(height: 8),

        ..._detections.asMap().entries.map((entry) {
          final index = entry.key;
          final detection = entry.value;
          final enabled = _detectionEnabled[index] ?? true;

          return _buildItemTile(
            color: detection.typeColor,
            label: '${detection.typeLabel} #${index + 1}',
            sub: '신뢰도 ${(detection.confidence * 100).toStringAsFixed(0)}%',
            enabled: enabled,
            onToggle: (value) {
              setState(() => _detectionEnabled[index] = value);
            },
          );
        }),

        ..._ocrDetections.asMap().entries.map((entry) {
          final index = entry.key;
          final detection = entry.value;
          final enabled = _ocrEnabled[index] ?? true;

          return _buildItemTile(
            color: Color(0xFF8FC9F7),
            label: detection.privacyTexts.isNotEmpty
                ? _displayPrivacyText(detection.privacyTexts.first)
                : 'OCR #${index + 1}',
            sub: 'OCR 개인정보',
            enabled: enabled,
            onToggle: (value) {
              setState(() => _ocrEnabled[index] = value);
            },
          );
        }),
      ],
    );
  }

  String _displayPrivacyText(String text) {
    if (text.startsWith('운송장 이름:')) {
      return text.replaceFirst('운송장 이름:', '이름:');
    }

    return text;
  }

  Widget _buildBottomButton() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _goToEditor,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8FC9F7),
              foregroundColor: const Color(0xFF1F2937),
              padding: const EdgeInsets.symmetric(
                vertical: 16,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '편집하기',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItemTile({
    required Color color,
    required String label,
    required String sub,
    required bool enabled,
    required void Function(bool) onToggle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 8,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: Color(0xFFF7FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: enabled
                ? color.withValues(alpha: 0.4)
                : const Color(0xFFDCEFF8),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: enabled ? color : const Color(0xFFBFE4F5),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: enabled ? Colors.white : const Color(0xFF6B7280),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    sub,
                    style: const TextStyle(
                      color: Color(0xFF666666),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: enabled,
              onChanged: onToggle,
              activeThumbColor: color,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }
}

class _OcrPolygonPainter extends CustomPainter {
  final List<DetectionResult> detections;
  final Map<int, bool> enabledMap;
  final Size imageSize;
  final Size displaySize;
  final double currentScale;

  _OcrPolygonPainter({
    required this.detections,
    required this.enabledMap,
    required this.imageSize,
    required this.displaySize,
    required this.currentScale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.width <= 0 || imageSize.height <= 0) return;

    final sx = displaySize.width / imageSize.width;
    final sy = displaySize.height / imageSize.height;

    final strokeWidth = (1.5 / currentScale).clamp(0.8, 1.5);

    for (int i = 0; i < detections.length; i++) {
      final detection = detections[i];
      final enabled = enabledMap[i] ?? true;

      final color = enabled
          ? const Color(0xFF8FC9F7)
          : const Color(0xFF8FC9F7).withValues(alpha: 0.25);

      final fillColor = enabled
          ? const Color(0xFF8FC9F7).withValues(alpha: 0.15)
          : Colors.transparent;

      final boxPaint = Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke;

      final fillPaint = Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill;

      final polygon = detection.polygon;

      if (polygon != null && polygon.length >= 3) {
        final scaled = polygon.map((point) {
          return Offset(
            point.dx * sx,
            point.dy * sy,
          );
        }).toList();

        final path = Path()
          ..moveTo(
            scaled.first.dx,
            scaled.first.dy,
          );

        for (final point in scaled.skip(1)) {
          path.lineTo(
            point.dx,
            point.dy,
          );
        }

        path.close();

        canvas.drawPath(path, fillPaint);
        canvas.drawPath(path, boxPaint);
      } else {
        final rect = Rect.fromLTRB(
          detection.boundingBox.left * sx,
          detection.boundingBox.top * sy,
          detection.boundingBox.right * sx,
          detection.boundingBox.bottom * sy,
        );

        canvas.drawRect(rect, fillPaint);
        canvas.drawRect(rect, boxPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OcrPolygonPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.enabledMap != enabledMap ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.displaySize != displaySize ||
        oldDelegate.currentScale != currentScale;
  }
}