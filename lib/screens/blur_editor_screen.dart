import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/blur_region.dart';
import '../models/detection_result.dart';
import '../services/blur_service.dart';
import '../widgets/blur_region_overlay.dart';
import 'export_screen.dart';

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
  late List<BlurRegion> _regions;
  int _regionCounter = 0;

  // [Req 2] 명확한 모드 분리: false=이동/확대, true=그리기
  bool _drawMode = false;
  bool _isExporting = false;
  String? _selectedId;

  final _tc = TransformationController();
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _buildInitialRegions();
    _tc.addListener(() {
      final zoomed = _tc.value.getMaxScaleOnAxis() > 1.01;
      if (zoomed != _isZoomed) setState(() => _isZoomed = zoomed);
    });
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  void _buildInitialRegions() {
    final regions = <BlurRegion>[];
    for (int i = 0; i < widget.detections.length; i++) {
      final d = widget.detections[i];
      regions.add(BlurRegion.fromDetection(d, id: 'auto_$i')
          .copyWith(isBlurred: widget.typeBlurEnabled[d.type] ?? true));
    }
    for (int i = 0; i < widget.ocrDetections.length; i++) {
      regions.add(BlurRegion.fromDetection(
        widget.ocrDetections[i],
        id: 'ocr_$i',
        defaultEffect: BlurEffect.blackBar,
      ).copyWith(
          isBlurred:
          widget.typeBlurEnabled[DetectionType.document] ?? true));
    }
    _regions = regions;
    _regionCounter = regions.length;
  }

  BlurRegion? get _selectedRegion {
    if (_selectedId == null) return null;
    try {
      return _regions.firstWhere((r) => r.id == _selectedId);
    } catch (_) {
      return null;
    }
  }

  void _onRegionUpdated(BlurRegion updated) {
    setState(() {
      final idx = _regions.indexWhere((r) => r.id == updated.id);
      if (idx != -1) _regions[idx] = updated;
      _selectedId = updated.id;
    });
  }

  void _onRegionAdded(Rect imageRect) {
    final id = 'manual_${++_regionCounter}';
    setState(() {
      _regions.add(BlurRegion.manual(id: id, rect: imageRect));
      _selectedId = id;
      _drawMode = false; // 박스 생성 후 이동 모드로 자동 전환
    });
  }

  void _onRegionDeleted(String id) {
    setState(() {
      _regions.removeWhere((r) => r.id == id);
      if (_selectedId == id) _selectedId = null;
    });
  }

  Future<void> _goToExport() async {
    setState(() => _isExporting = true);
    final active = _regions.where((r) => r.isBlurred).toList();
    try {
      final blurred = await widget.blurService.applyBlur(
        widget.imageFile, active,
        widget.imageSize.width, widget.imageSize.height,
      );
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ExportScreen(
            blurredImage: blurred, originalBytes: widget.originalBytes),
      ));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  // [Req 4] 8종 효과 기본 강도
  void _changeEffect(BlurEffect effect) {
    if (_selectedRegion == null) return;
    final intensity = switch (effect) {
      BlurEffect.gaussian      => 12.0,
      BlurEffect.mosaic        => 20.0,
      BlurEffect.blackBar      => 20.0,
      BlurEffect.frostedGlass  => 10.0,
      BlurEffect.whiteBar      => 20.0,
      BlurEffect.redBar        => 20.0,
      BlurEffect.heavyPixelate => 40.0,
      BlurEffect.grayscaleBlur => 15.0,
    };
    _onRegionUpdated(
        _selectedRegion!.copyWith(effect: effect, blurIntensity: intensity));
  }

  bool get _showSlider {
    final e = _selectedRegion?.effect;
    return e == BlurEffect.gaussian ||
        e == BlurEffect.mosaic ||
        e == BlurEffect.frostedGlass ||
        e == BlurEffect.heavyPixelate ||
        e == BlurEffect.grayscaleBlur;
  }

  String get _sliderLabel => switch (_selectedRegion?.effect) {
    BlurEffect.gaussian      => '흐림 강도',
    BlurEffect.mosaic        => '픽셀 크기',
    BlurEffect.frostedGlass  => '흐림 강도',
    BlurEffect.heavyPixelate => '픽셀 크기',
    BlurEffect.grayscaleBlur => '흐림 강도',
    _                        => '',
  };

  double get _sliderMax => switch (_selectedRegion?.effect) {
    BlurEffect.mosaic        => 80.0,
    BlurEffect.heavyPixelate => 80.0,
    _                        => 30.0,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: _buildAppBar(),
      body: LayoutBuilder(builder: (ctx, constraints) {
        // [Req 3] 이미지 영역 최대 47%, 나머지 하단 패널
        final imageH = constraints.maxHeight * 0.47;
        return Column(
          children: [
            SizedBox(height: imageH, child: _buildImageArea()),
            Expanded(
              child: SingleChildScrollView(child: _buildBottomPanel()),
            ),
          ],
        );
      }),
    );
  }

  AppBar _buildAppBar() => AppBar(
    backgroundColor: const Color(0xFF0F0F0F),
    foregroundColor: Colors.white,
    title: Row(
      children: [
        Text(
          _drawMode ? '✏️ 그리기 모드' : '편집',
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ],
    ),
    elevation: 0,
    actions: [
      IconButton(
        icon: const Icon(Icons.visibility_outlined),
        tooltip: '전체 블러 표시/숨김',
        onPressed: () {
          final allOn = _regions.every((r) => r.isBlurred);
          setState(() {
            _regions = _regions
                .map((r) => r.copyWith(isBlurred: !allOn))
                .toList();
          });
        },
      ),
    ],
  );

  Widget _buildImageArea() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: LayoutBuilder(builder: (ctx, constraints) {
          if (widget.imageSize == Size.zero) return const SizedBox.shrink();
          final dw = constraints.maxWidth;
          final dh =
              widget.imageSize.height * dw / widget.imageSize.width;
          final displaySize = Size(dw, dh);

          return SingleChildScrollView(
            physics: _isZoomed
                ? const NeverScrollableScrollPhysics()
                : const ClampingScrollPhysics(),
            child: InteractiveViewer(
              transformationController: _tc,
              // [Req 2] 이동 모드에서만 pan/scale 활성
              panEnabled: !_drawMode,
              scaleEnabled: !_drawMode,
              minScale: 1.0,
              maxScale: 6.0,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: dw,
                height: dh,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Image.memory(widget.originalBytes,
                          fit: BoxFit.fill),
                    ),
                    BlurRegionOverlay(
                      regions: _regions,
                      imageSize: widget.imageSize,
                      displaySize: displaySize,
                      drawMode: _drawMode,
                      transformationController: _tc,
                      onRegionUpdated: _onRegionUpdated,
                      onRegionAdded: _onRegionAdded,
                      onRegionDeleted: _onRegionDeleted,
                    ),
                    if (_isExporting)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black.withOpacity(0.55),
                          child: const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(
                                    color: Color(0xFF6C63FF)),
                                SizedBox(height: 12),
                                Text('이미지 처리 중...',
                                    style: TextStyle(
                                        color: Colors.white70)),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildBottomPanel() {
    final sel = _selectedRegion;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        border: Border(top: BorderSide(color: Color(0xFF2D2D2D))),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            // ── [Req 2] 모드 토글 (명확한 분리) ──────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0F0F),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    _buildModeBtn(
                      icon: Icons.pan_tool_outlined,
                      label: '🔍 이동/확대',
                      active: !_drawMode,
                      onTap: () => setState(() => _drawMode = false),
                      activeColor: const Color(0xFF6C63FF),
                    ),
                    _buildModeBtn(
                      icon: Icons.edit_outlined,
                      label: '✏️ 그리기',
                      active: _drawMode,
                      onTap: () => setState(() => _drawMode = true),
                      activeColor: const Color(0xFF00BCD4),
                    ),
                  ],
                ),
              ),
            ),

            // ── 선택된 박스 효과 패널 ──────────────────────────────
            if (sel != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: sel.color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: sel.color.withOpacity(0.5)),
                      ),
                      child: Text('${sel.label} 선택됨',
                          style: TextStyle(
                              color: sel.color,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ),
                    const Spacer(),
                    if (sel.isLocked)
                      const Text('🔒 잠금 상태',
                          style: TextStyle(
                              color: Color(0xFF888888), fontSize: 10)),
                  ],
                ),
              ),

              // [Req 4] 8종 효과 버튼 — 가로 스크롤
              SizedBox(
                height: 72,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                  children: [
                    _EffectChip(label: '흐림',    effect: BlurEffect.gaussian,      icon: Icons.blur_on,           accentColor: const Color(0xFF6C63FF), selected: sel.effect, onTap: _changeEffect),
                    const SizedBox(width: 6),
                    _EffectChip(label: '모자이크', effect: BlurEffect.mosaic,         icon: Icons.grid_4x4,          accentColor: const Color(0xFFFF6B6B), selected: sel.effect, onTap: _changeEffect),
                    const SizedBox(width: 6),
                    _EffectChip(label: '검정',    effect: BlurEffect.blackBar,       icon: Icons.rectangle_outlined, accentColor: Colors.grey,             selected: sel.effect, onTap: _changeEffect),
                    const SizedBox(width: 6),
                    _EffectChip(label: '반투명',   effect: BlurEffect.frostedGlass,  icon: Icons.opacity,           accentColor: Colors.lightBlue,        selected: sel.effect, onTap: _changeEffect),
                    const SizedBox(width: 6),
                    _EffectChip(label: '흰색',    effect: BlurEffect.whiteBar,       icon: Icons.crop_square,       accentColor: Colors.white70,          selected: sel.effect, onTap: _changeEffect),
                    const SizedBox(width: 6),
                    _EffectChip(label: '빨간색',  effect: BlurEffect.redBar,         icon: Icons.remove,            accentColor: Colors.redAccent,        selected: sel.effect, onTap: _changeEffect),
                    const SizedBox(width: 6),
                    _EffectChip(label: '굵은픽셀', effect: BlurEffect.heavyPixelate, icon: Icons.apps,              accentColor: Colors.orange,           selected: sel.effect, onTap: _changeEffect),
                    const SizedBox(width: 6),
                    _EffectChip(label: '흑백',    effect: BlurEffect.grayscaleBlur,  icon: Icons.filter_b_and_w,    accentColor: Colors.blueGrey,         selected: sel.effect, onTap: _changeEffect),
                  ],
                ),
              ),

              if (_showSlider)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text('$_sliderLabel: ${sel.blurIntensity.toInt()}',
                          style: const TextStyle(
                              color: Color(0xFF888888), fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: sel.blurIntensity,
                          min: 1.0,
                          max: _sliderMax,
                          activeColor: const Color(0xFF6C63FF),
                          onChanged: (v) => _onRegionUpdated(
                              sel.copyWith(blurIntensity: v)),
                        ),
                      ),
                    ],
                  ),
                ),
            ] else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 0, 4),
                child: Text(
                  _drawMode
                      ? '👆 드래그로 새 블러 박스 추가'
                      : '박스 탭 → ON/OFF  |  핸들 드래그 → 크기·회전',
                  style: const TextStyle(
                      color: Color(0xFF555555), fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ),
            ],

            // ── 완료 버튼 ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isExporting ? null : _goToExport,
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
                      Text('완료 · 내보내기',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
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
    );
  }

  Widget _buildModeBtn({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
    required Color activeColor,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14,
                  color: active ? Colors.white : const Color(0xFF666666)),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                    color: active ? Colors.white : const Color(0xFF666666),
                    fontSize: 12,
                    fontWeight:
                    active ? FontWeight.bold : FontWeight.normal,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── [Req 4] 8종 효과 선택 칩 ────────────────────────────────────────
class _EffectChip extends StatelessWidget {
  final String label;
  final BlurEffect effect;
  final IconData icon;
  final Color accentColor;
  final BlurEffect selected;
  final void Function(BlurEffect) onTap;

  const _EffectChip({
    required this.label,
    required this.effect,
    required this.icon,
    required this.accentColor,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = selected == effect;
    return GestureDetector(
      onTap: () => onTap(effect),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: isActive ? accentColor : const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(10),
          border: isActive
              ? null
              : Border.all(color: const Color(0xFF3D3D3D)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18,
                color: isActive ? Colors.white : const Color(0xFF888888)),
            const SizedBox(height: 4),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color:
                  isActive ? Colors.white : const Color(0xFF888888),
                  fontSize: 10,
                  fontWeight:
                  isActive ? FontWeight.bold : FontWeight.normal,
                )),
          ],
        ),
      ),
    );
  }
}