import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/detection_result.dart';
import '../models/manual_blur_box.dart';
import '../services/blur_service.dart';
import '../widgets/detection_overlay.dart';
import 'export_screen.dart';

enum EditorMode { view, edit }

class BlurEditorScreen extends StatefulWidget {
  final File imageFile;
  final Size imageSize;
  final Uint8List originalBytes;
  final List<DetectionResult> detections;
  final List<DetectionResult> ocrDetections;
  final Map<DetectionType, bool> typeBlurEnabled;
  final BlurService blurService;

  const BlurEditorScreen({
    super.key,
    required this.imageFile,
    required this.imageSize,
    required this.originalBytes,
    required this.detections,
    required this.ocrDetections,
    required this.typeBlurEnabled,
    required this.blurService,
  });

  @override
  State<BlurEditorScreen> createState() => _BlurEditorScreenState();
}

class _BlurEditorScreenState extends State<BlurEditorScreen> {
  // ── 탐지 결과 (로컬 복사본) ─────────────────────────────────────────
  late List<DetectionResult> _detections;
  late List<DetectionResult> _ocrDetections;
  late Map<DetectionType, bool> _typeBlurEnabled;

  // ── 자동 탐지 rect 오버라이드 ────────────────────────────────────────
  final Map<int, Rect> _detectionOverrides = {};

  // ── 수동 블러 박스 ───────────────────────────────────────────────────
  final List<ManualBlurBox> _manualBoxes = [];
  int _manualBoxCounter = 0;

  // ── 블러 이미지 ──────────────────────────────────────────────────────
  Uint8List? _blurredImage;

  // ── UI 상태 ──────────────────────────────────────────────────────────
  bool _isProcessing  = true;
  bool _blurEnabled   = true;

  // ── 블러 효과 ────────────────────────────────────────────────────────
  BlurEffect _selectedEffect = BlurEffect.mosaic;
  double     _blurIntensity  = 20.0;

  // ── 편집 모드 ─────────────────────────────────────────────────────────
  EditorMode _editorMode = EditorMode.view;

  // ── InteractiveViewer ────────────────────────────────────────────────
  final _transformationController = TransformationController();
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _detections      = List.from(widget.detections);
    _ocrDetections   = List.from(widget.ocrDetections);
    _typeBlurEnabled = Map.from(widget.typeBlurEnabled);

    _transformationController.addListener(() {
      final scale  = _transformationController.value.getMaxScaleOnAxis();
      final zoomed = scale > 1.01;
      if (zoomed != _isZoomed) setState(() => _isZoomed = zoomed);
    });

    _applyBlurWithCurrentSettings();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  // ── 활성 탐지 목록 ────────────────────────────────────────────────
  List<DetectionResult> get _activeDetections {
    final active = <DetectionResult>[];

    for (int i = 0; i < _detections.length; i++) {
      final d = _detections[i];
      if (!(_typeBlurEnabled[d.type] ?? true)) continue;
      final effectiveRect = _detectionOverrides[i] ?? d.boundingBox;
      active.add(d.withRect(effectiveRect));
    }

    if (_typeBlurEnabled[DetectionType.document] ?? true) {
      active.addAll(_ocrDetections);
    }

    if (_typeBlurEnabled[DetectionType.manual] ?? true) {
      for (final box in _manualBoxes) {
        if (box.enabled) {
          active.add(DetectionResult(
            type: DetectionType.manual,
            boundingBox: box.rect,
            confidence: 1.0,
          ));
        }
      }
    }

    return active;
  }

  // ── 블러 재적용 ────────────────────────────────────────────────────
  Future<void> _applyBlurWithCurrentSettings() async {
    setState(() => _isProcessing = true);
    final blurred = await widget.blurService.applyBlur(
      widget.imageFile,
      _activeDetections,
      widget.imageSize.width,
      widget.imageSize.height,
      effect:        _selectedEffect,
      blurIntensity: _blurIntensity,
    );
    setState(() {
      _blurredImage = blurred;
      _isProcessing = false;
    });
  }

  // ── DetectionOverlay 콜백 ────────────────────────────────────────
  void _onManualBoxAdded(Rect imageRect) {
    final id = 'manual_${++_manualBoxCounter}';
    setState(() => _manualBoxes.add(ManualBlurBox(id: id, rect: imageRect)));
    _applyBlurWithCurrentSettings();
  }

  void _onManualBoxUpdated(String id, Rect imageRect) {
    final idx = _manualBoxes.indexWhere((b) => b.id == id);
    if (idx == -1) return;
    setState(() => _manualBoxes[idx] = _manualBoxes[idx].copyWith(rect: imageRect));
    _applyBlurWithCurrentSettings();
  }

  void _onManualBoxDeleted(String id) {
    setState(() => _manualBoxes.removeWhere((b) => b.id == id));
    _applyBlurWithCurrentSettings();
  }

  void _onDetectionResized(int index, Rect imageRect) {
    setState(() => _detectionOverrides[index] = imageRect);
    _applyBlurWithCurrentSettings();
  }

  // ── 완료 → ExportScreen ──────────────────────────────────────────
  void _goToExport() {
    if (_blurredImage == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExportScreen(
          blurredImage:  _blurredImage!,
          originalBytes: widget.originalBytes,
        ),
      ),
    );
  }

  // ── 슬라이더 헬퍼 ────────────────────────────────────────────────
  bool get _showIntensitySlider =>
      _selectedEffect == BlurEffect.gaussian     ||
          _selectedEffect == BlurEffect.mosaic       ||
          _selectedEffect == BlurEffect.frostedGlass;

  String get _intensityLabel {
    switch (_selectedEffect) {
      case BlurEffect.gaussian:     return '흐림 강도';
      case BlurEffect.mosaic:       return '픽셀 크기';
      case BlurEffect.frostedGlass: return '흐림 강도';
      default:                      return '';
    }
  }

  double get _intensityMax =>
      _selectedEffect == BlurEffect.mosaic ? 100.0 : 30.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F0F),
        foregroundColor: Colors.white,
        title: const Text('편집', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        actions: [
          // 블러 미리보기 토글
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                Icon(
                  _blurEnabled ? Icons.blur_on : Icons.blur_off,
                  color: _blurEnabled
                      ? const Color(0xFF6C63FF)
                      : const Color(0xFF555555),
                  size: 20,
                ),
                Switch(
                  value:            _blurEnabled,
                  onChanged:        (val) => setState(() => _blurEnabled = val),
                  activeThumbColor: const Color(0xFF6C63FF),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── 이미지 영역 ──────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (widget.imageSize == Size.zero) {
                      return const SizedBox.shrink();
                    }
                    final displayWidth  = constraints.maxWidth;
                    final displayHeight =
                        widget.imageSize.height * displayWidth / widget.imageSize.width;
                    final displaySize = Size(displayWidth, displayHeight);

                    return SingleChildScrollView(
                      physics: (_isZoomed && _editorMode == EditorMode.view)
                          ? const NeverScrollableScrollPhysics()
                          : const ClampingScrollPhysics(),
                      child: InteractiveViewer(
                        transformationController: _transformationController,
                        panEnabled:   _editorMode == EditorMode.view,
                        scaleEnabled: _editorMode == EditorMode.view,
                        minScale:     1.0,
                        maxScale:     5.0,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width:  displayWidth,
                          height: displayHeight,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: (_blurEnabled && _blurredImage != null)
                                    ? Image.memory(_blurredImage!, fit: BoxFit.fill)
                                    : Image.memory(widget.originalBytes, fit: BoxFit.fill),
                              ),
                              if (_isProcessing)
                                Positioned.fill(
                                  child: Container(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    child: const Center(
                                      child: CircularProgressIndicator(
                                          color: Color(0xFF6C63FF)),
                                    ),
                                  ),
                                ),
                              DetectionOverlay(
                                editMode:              _editorMode == EditorMode.edit,
                                imageSize:             widget.imageSize,
                                displaySize:           displaySize,
                                detections:            _detections,
                                detectionOverrides:    _detectionOverrides,
                                typeBlurEnabled:       _typeBlurEnabled,
                                manualBoxes:           _manualBoxes,
                                privacyDetections:     _ocrDetections,
                                cardPrivacyDetections: const [],
                                useTextBlur:           true,
                                useCardTextBlur:       false,
                                onManualBoxAdded:      _onManualBoxAdded,
                                onManualBoxUpdated:    _onManualBoxUpdated,
                                onManualBoxDeleted:    _onManualBoxDeleted,
                                onDetectionResized:    _onDetectionResized,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          // ── 하단 컨트롤 패널 ──────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A1A),
              border: Border(top: BorderSide(color: Color(0xFF2D2D2D))),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [

                  // 뷰 / 편집 모드 전환
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F0F0F),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(child: _buildModeButton(
                            icon: Icons.search_rounded,
                            label: '뷰 모드',
                            subLabel: '확대 · 이동',
                            mode: EditorMode.view,
                          )),
                          const SizedBox(width: 4),
                          Expanded(child: _buildModeButton(
                            icon: Icons.touch_app_rounded,
                            label: '편집 모드',
                            subLabel: '박스 추가 · 조절',
                            mode: EditorMode.edit,
                          )),
                        ],
                      ),
                    ),
                  ),

                  // 블러 효과 선택
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: Row(
                      children: [
                        _buildEffectButton('흐림',    BlurEffect.gaussian,     Icons.blur_on),
                        const SizedBox(width: 8),
                        _buildEffectButton('모자이크', BlurEffect.mosaic,       Icons.grid_4x4),
                        const SizedBox(width: 8),
                        _buildEffectButton('블랙 바', BlurEffect.blackBar,     Icons.rectangle_outlined),
                        const SizedBox(width: 8),
                        _buildEffectButton('반투명',   BlurEffect.frostedGlass, Icons.opacity),
                      ],
                    ),
                  ),

                  // 강도 슬라이더
                  if (_showIntensitySlider)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Text('$_intensityLabel: ${_blurIntensity.toInt()}',
                              style: const TextStyle(
                                  color: Color(0xFF888888), fontSize: 12)),
                          Expanded(
                            child: Slider(
                              value:       _blurIntensity,
                              min:         1.0,
                              max:         _intensityMax,
                              divisions:   (_intensityMax - 1).toInt(),
                              activeColor: const Color(0xFF6C63FF),
                              onChanged:   (v) => setState(() => _blurIntensity = v),
                              onChangeEnd: (_) => _applyBlurWithCurrentSettings(),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // 힌트 텍스트
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      _editorMode == EditorMode.edit
                          ? '👆 드래그로 박스 추가, 모서리로 크기 조절'
                          : '핀치로 확대/축소 가능해요',
                      style: TextStyle(
                        color: _editorMode == EditorMode.edit
                            ? const Color(0xFF00BCD4)
                            : const Color(0xFF555555),
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  // 완료 버튼
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isProcessing ? null : _goToExport,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C63FF),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('완료', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward_rounded, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton({
    required IconData   icon,
    required String     label,
    required String     subLabel,
    required EditorMode mode,
  }) {
    final isActive    = _editorMode == mode;
    final activeColor = mode == EditorMode.edit
        ? const Color(0xFF00BCD4)
        : const Color(0xFF6C63FF);

    return GestureDetector(
      onTap: () => setState(() => _editorMode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: isActive ? activeColor.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? activeColor : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16,
                color: isActive ? activeColor : const Color(0xFF555555)),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: isActive ? Colors.white : const Color(0xFF555555),
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
                Text(subLabel,
                    style: TextStyle(
                        color: isActive
                            ? activeColor.withValues(alpha: 0.8)
                            : const Color(0xFF444444),
                        fontSize: 10)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEffectButton(String label, BlurEffect effect, IconData icon) {
    final isSelected = _selectedEffect == effect;
    return Expanded(
      child: GestureDetector(
        onTap: () async {
          setState(() {
            _selectedEffect = effect;
            _blurIntensity  = switch (effect) {
              BlurEffect.gaussian     => 12.0,
              BlurEffect.mosaic       => 20.0,
              BlurEffect.blackBar     => 20.0,
              BlurEffect.frostedGlass => 10.0,
            };
          });
          await _applyBlurWithCurrentSettings();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF6C63FF) : const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16,
                  color: isSelected ? Colors.white : const Color(0xFF888888)),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFF888888),
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
            ],
          ),
        ),
      ),
    );
  }
}