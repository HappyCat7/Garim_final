import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  String? _selectedId;
  bool _drawMode = false;
  bool _isExporting = false;

  // 🌟 새 기능: 꾹 누르면 원본 보기 기능 활성화
  bool _showOriginal = false;

  final List<List<BlurRegion>> _history = [];
  int _historyIndex = -1;
  bool get _canUndo => _historyIndex > 0;
  bool get _canRedo => _historyIndex < _history.length - 1;
  bool get _hasEdits => _historyIndex > 0;

  final _tc = TransformationController();
  double _zoomLevel = 1.0;
  bool _showZoomBadge = false;
  Timer? _zoomTimer;

  @override
  void initState() {
    super.initState();
    _buildInitialRegions();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pushHistory());

    _tc.addListener(() {
      final scale = _tc.value.getMaxScaleOnAxis();
      if ((scale - _zoomLevel).abs() > 0.08) {
        setState(() { _zoomLevel = scale; _showZoomBadge = true; });
        _zoomTimer?.cancel();
        _zoomTimer = Timer(const Duration(milliseconds: 1500), () {
          if (mounted) setState(() => _showZoomBadge = false);
        });
      }
    });
  }

  @override
  void dispose() {
    _zoomTimer?.cancel();
    _tc.dispose();
    super.dispose();
  }

  void _buildInitialRegions() {
    final list = <BlurRegion>[];
    for (int i = 0; i < widget.detections.length; i++) {
      final d = widget.detections[i];
      list.add(BlurRegion.fromDetection(d, id: 'auto_$i')
          .copyWith(isBlurred: widget.typeBlurEnabled[d.type] ?? true));
    }
    for (int i = 0; i < widget.ocrDetections.length; i++) {
      list.add(BlurRegion.fromDetection(
        widget.ocrDetections[i],
        id: 'ocr_$i',
        defaultEffect: BlurEffect.gaussian,
      ).copyWith(
          isBlurred: widget.typeBlurEnabled[DetectionType.document] ?? true));
    }
    _regions = list;
    _regionCounter = list.length;
  }

  void _pushHistory() {
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    _history.add(List<BlurRegion>.from(_regions));
    _historyIndex = _history.length - 1;
    if (_history.length > 30) {
      _history.removeAt(0);
      _historyIndex = _history.length - 1;
    }
    if (mounted) setState(() {});
  }

  void _undo() {
    if (!_canUndo) return;
    HapticFeedback.lightImpact();
    setState(() {
      _historyIndex--;
      _regions = List<BlurRegion>.from(_history[_historyIndex]);
      _selectedId = null;
    });
  }

  void _redo() {
    if (!_canRedo) return;
    HapticFeedback.lightImpact();
    setState(() {
      _historyIndex++;
      _regions = List<BlurRegion>.from(_history[_historyIndex]);
      _selectedId = null;
    });
  }

  Future<void> _handleBackPress() async {
    if (!_hasEdits) { if (mounted) Navigator.of(context).pop(); return; }
    HapticFeedback.mediumImpact();
    final leave = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFF7FAFC),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 22),
          SizedBox(width: 8),
          Text('편집 내용이 있어요', style: TextStyle(color: Color(0xFF1F2937), fontSize: 16)),
        ]),
        content: const Text('지금까지 편집한 블러 설정이 사라져요.\n정말 나가시겠어요?',
            style: TextStyle(color: Color(0xFF888888), fontSize: 14, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('계속 편집', style: TextStyle(color: Color(0xFF6C63FF))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('나가기', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  BlurRegion? get _selectedRegion {
    if (_selectedId == null) return null;
    try { return _regions.firstWhere((r) => r.id == _selectedId); }
    catch (_) { return null; }
  }

  void _onRegionUpdated(BlurRegion updated) {
    setState(() {
      final idx = _regions.indexWhere((r) => r.id == updated.id);
      if (idx != -1) _regions[idx] = updated;
    });
  }

  void _onEditCommit() => _pushHistory();

  void _onSelectionChanged(String? id) {
    if (_selectedId != id) setState(() => _selectedId = id);
  }

  void _onRegionAdded(Rect imageRect) {
    HapticFeedback.mediumImpact();
    final id = 'manual_${++_regionCounter}';
    setState(() {
      _regions.add(BlurRegion.manual(id: id, rect: imageRect));
      _selectedId = id;
      _drawMode = false;
    });
    _pushHistory();
  }

  void _onRegionDeleted(String id) {
    final deleted = _regions.firstWhere((r) => r.id == id,
        orElse: () => BlurRegion.manual(id: id, rect: Rect.zero));
    HapticFeedback.mediumImpact();
    setState(() {
      _regions.removeWhere((r) => r.id == id);
      if (_selectedId == id) _selectedId = null;
    });
    _pushHistory();
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${deleted.label} 블러 박스 삭제됨'),
      backgroundColor: const Color(0xFFDCEFF8),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      duration: const Duration(seconds: 3),
      action: SnackBarAction(
          label: '되돌리기', textColor: const Color(0xFF8FC9F7), onPressed: _undo),
    ));
  }

  Future<void> _goToExport() async {
    setState(() => _isExporting = true);
    try {
      final blurred = await widget.blurService.applyBlur(
        widget.imageFile,
        _regions.where((r) => r.isBlurred).toList(),
        widget.imageSize.width,
        widget.imageSize.height,
      );
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ExportScreen(
            blurredImage: blurred, originalBytes: widget.originalBytes),
      ));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _changeEffect(BlurEffect effect) {
    if (_selectedRegion == null) return;
    HapticFeedback.selectionClick();

    final intensity = switch (effect) {
      BlurEffect.gaussian     => 15.0,
      BlurEffect.frostedGlass => 15.0,
      BlurEffect.pixelate     => 20.0,
      BlurEffect.fog          => 20.0,
      BlurEffect.point        => 25.0, // 포인트 효과 기본값
    };

    _onRegionUpdated(_selectedRegion!.copyWith(effect: effect, blurIntensity: intensity));
    _pushHistory();
  }

  bool get _showSlider => _selectedRegion != null;

  String get _sliderLabel {
    return switch (_selectedRegion?.effect) {
      BlurEffect.gaussian     => '흐림 강도',
      BlurEffect.frostedGlass => '유리 강도',
      BlurEffect.pixelate     => '픽셀 크기',
      BlurEffect.fog          => '안개 두께',
      BlurEffect.point        => '도트 크기',
      null                    => '',
    };
  }

  double get _sliderMax {
    return switch (_selectedRegion?.effect) {
      BlurEffect.pixelate => 80.0,
      BlurEffect.point    => 80.0,
      BlurEffect.fog      => 50.0,
      _                   => 30.0,
    };
  }

  int get _activeCount => _regions.where((r) => r.isBlurred).length;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasEdits,
      onPopInvoked: (didPop) { if (!didPop) _handleBackPress(); },
      child: Scaffold(
        backgroundColor: const Color(0xFFFFFFFF),
        appBar: _buildAppBar(),
        body: Column(
          children: [
            Expanded(child: _buildImageArea()),
            _buildUndoRedoBar(),
            _buildBottomPanel(),
          ],
        ),
      ),
    );
  }

  AppBar _buildAppBar() => AppBar(
    backgroundColor: const Color(0xFFFFFFFF),
    foregroundColor: const Color(0xFF1F2937),
    leading: IconButton(
      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
      onPressed: _handleBackPress,
    ),
    title: Row(children: [
      Text(_drawMode ? '✏️ 그리기' : '편집',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      if (_activeCount > 0) ...[
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: Color(0xFF8FC9F7).withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Color(0xFF8FC9F7).withOpacity(0.4)),
          ),
          child: Text('$_activeCount',
              style: const TextStyle(color: Color(0xFF6C63FF), fontSize: 11, fontWeight: FontWeight.bold)),
        ),
      ],
    ]),
    elevation: 0,
    actions: [
      // 🌟 새 기능: 꾹 누르면 원본 보기 로직으로 완전히 교체됨!
      GestureDetector(
        onTapDown: (_) {
          HapticFeedback.lightImpact();
          setState(() => _showOriginal = true); // 누를 때 원본 보기 켬
        },
        onTapUp: (_) {
          setState(() => _showOriginal = false); // 손 떼면 원상복구
        },
        onTapCancel: () {
          setState(() => _showOriginal = false); // 드래그 시 원상복구
        },
        child: Container(
          color: Colors.transparent, // 터치 영역을 넓게 확보
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Icon(
            _showOriginal ? Icons.visibility : Icons.visibility_outlined,
            size: 24,
            color: _showOriginal ? const Color(0xFF8FC9F7) : Colors.white,
          ),
        ),
      ),
    ],
  );

  Widget _buildImageArea() {
    return LayoutBuilder(builder: (ctx, constraints) {
      if (widget.imageSize == Size.zero) return const SizedBox.shrink();
      final availW = constraints.maxWidth;
      final availH = constraints.maxHeight;
      final imgAspect = widget.imageSize.width / widget.imageSize.height;
      final availAspect = availW / availH;

      final double dw, dh;
      if (imgAspect >= availAspect) {
        dw = availW;
        dh = availW / imgAspect;
      } else {
        dh = availH;
        dw = availH * imgAspect;
      }
      final displaySize = Size(dw, dh);

      return Container(
        color: Color(0xFFF7FAFC),
        child: Center(
          child: Stack(
            children: [
              ClipRect(
                child: InteractiveViewer(
                  transformationController: _tc,
                  panEnabled: !_drawMode,
                  scaleEnabled: !_drawMode,
                  minScale: 1.0,
                  maxScale: 6.0,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: dw, height: dh,
                    child: Stack(
                      children: [
                        Image.memory(widget.originalBytes,
                            fit: BoxFit.fill, width: dw, height: dh),
                        // 🌟 원본보기(_showOriginal)가 아닐 때만 블러 위젯들을 렌더링함!
                        if (!_showOriginal)
                          BlurRegionOverlay(
                            regions: _regions,
                            imageSize: widget.imageSize,
                            displaySize: displaySize,
                            drawMode: _drawMode,
                            transformationController: _tc,
                            selectedId: _selectedId,
                            onRegionUpdated: _onRegionUpdated,
                            onRegionAdded: _onRegionAdded,
                            onRegionDeleted: _onRegionDeleted,
                            onEditCommit: _onEditCommit,
                            onSelectionChanged: _onSelectionChanged,
                          ),
                        if (_isExporting)
                          Positioned.fill(
                            child: Container(
                              color: Colors.black.withOpacity(0.55),
                              child: const Center(child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(color: Color(0xFF6C63FF)),
                                  SizedBox(height: 12),
                                  Text('이미지 처리 중...', style: TextStyle(color: Colors.white70)),
                                ],
                              )),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_showZoomBadge)
                Positioned(
                  top: 8, right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('${_zoomLevel.toStringAsFixed(1)}×',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildUndoRedoBar() {
    return Container(
      height: 38,
      color: Color(0xFFF7FAFC),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Text('편집 기록',
              style: TextStyle(color: Color(0xFF555555), fontSize: 11)),
          const Spacer(),
          _UndoRedoBtn(
            icon: Icons.undo_rounded,
            enabled: _canUndo,
            onTap: _undo,
            tooltip: '실행 취소',
          ),
          const SizedBox(width: 4),
          _UndoRedoBtn(
            icon: Icons.redo_rounded,
            enabled: _canRedo,
            onTap: _redo,
            tooltip: '다시 실행',
          ),
        ],
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
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(top: 8, bottom: 2),
              decoration: BoxDecoration(
                color: Color(0xFFBFE4F5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Color(0xFFFFFFFF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    _buildModeBtn(Icons.pan_tool_outlined, '이동/확대',
                        !_drawMode, const Color(0xFF8FC9F7), () {
                          HapticFeedback.selectionClick();
                          setState(() => _drawMode = false);
                        }),
                    _buildModeBtn(Icons.edit_outlined, '박스 그리기',
                        _drawMode, const Color(0xFF00BCD4), () {
                          HapticFeedback.selectionClick();
                          setState(() => _drawMode = true);
                        }),
                  ],
                ),
              ),
            ),
            if (sel != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: sel.color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: sel.color.withOpacity(0.4)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(width: 7, height: 7,
                            decoration: BoxDecoration(color: sel.color, shape: BoxShape.circle)),
                        const SizedBox(width: 4),
                        Text('${sel.label} 선택됨',
                            style: TextStyle(color: sel.color, fontSize: 11, fontWeight: FontWeight.bold)),
                      ]),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _onRegionUpdated(sel.copyWith(isBlurred: !sel.isBlurred));
                        _pushHistory();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: sel.isBlurred
                              ? const Color(0xFF8FC9F7)
                              : const Color(0xFFBFE4F5),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: sel.isBlurred
                              ? [BoxShadow(color: Color(0xFF8FC9F7).withOpacity(0.4),
                              blurRadius: 8, offset: const Offset(0, 2))]
                              : null,
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(
                            sel.isBlurred ? Icons.visibility : Icons.visibility_off,
                            color: Colors.white, size: 15,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            sel.isBlurred ? 'ON' : 'OFF',
                            style: const TextStyle(color: Colors.white,
                                fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(
                height: 76,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  children: [
                    _EffectChip(label: '기본 흐림',   effect: BlurEffect.gaussian,     icon: Icons.blur_on,    accentColor: const Color(0xFF8FC9F7), selected: sel.effect, onTap: _changeEffect),
                    const SizedBox(width: 6),
                    _EffectChip(label: '유리 산란',   effect: BlurEffect.frostedGlass, icon: Icons.water_drop, accentColor: Colors.lightBlue,        selected: sel.effect, onTap: _changeEffect),
                    const SizedBox(width: 6),
                    _EffectChip(label: '모자이크', effect: BlurEffect.pixelate,     icon: Icons.apps,       accentColor: Colors.orange,           selected: sel.effect, onTap: _changeEffect),
                    const SizedBox(width: 6),
                    _EffectChip(label: '뿌연 안개',   effect: BlurEffect.fog,          icon: Icons.cloud,      accentColor: Colors.teal,             selected: sel.effect, onTap: _changeEffect),
                    const SizedBox(width: 6),
                    // 🌟 포인트 효과 칩 추가
                    _EffectChip(label: '포인트(점)',   effect: BlurEffect.point,        icon: Icons.bubble_chart, accentColor: Colors.pinkAccent,       selected: sel.effect, onTap: _changeEffect),
                  ],
                ),
              ),

              if (_showSlider)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                  child: Row(
                    children: [
                      Text('$_sliderLabel: ${sel.blurIntensity.toInt()}',
                          style: const TextStyle(color: Color(0xFF888888), fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: sel.blurIntensity,
                          min: 1.0, max: _sliderMax,
                          activeColor: const Color(0xFF8FC9F7),
                          inactiveColor: const Color(0xFFDCEFF8),
                          onChanged: (v) => _onRegionUpdated(sel.copyWith(blurIntensity: v)),
                          onChangeEnd: (_) => _pushHistory(),
                        ),
                      ),
                    ],
                  ),
                ),
            ] else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: Text(
                  _drawMode
                      ? '👆 드래그해서 새 블러 박스를 그려주세요'
                      : '블러 박스를 탭하면 선택하고 편집할 수 있어요',
                  style: const TextStyle(color: Color(0xFF555555), fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ],

            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isExporting ? null : _goToExport,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8FC9F7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _isExporting
                      ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(color: Color(0xFF1F2937), strokeWidth: 2))
                      : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Text('저장하기',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('$_activeCount개 블러',
                          style: const TextStyle(fontSize: 11)),
                    ),
                  ]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeBtn(IconData icon, String label, bool active,
      Color activeColor, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 14,
                color: active ? Colors.white : const Color(0xFF6B7280)),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(
              color: active ? Colors.white : const Color(0xFF6B7280),
              fontSize: 12,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            )),
          ]),
        ),
      ),
    );
  }
}

class _UndoRedoBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final String tooltip;

  const _UndoRedoBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 36, height: 28,
        decoration: BoxDecoration(
          color: enabled
              ? const Color(0xFFDCEFF8)
              : const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 18,
            color: enabled ? Colors.white : const Color(0xFFBFE4F5)),
      ),
    ),
  );
}

class _EffectChip extends StatelessWidget {
  final String label;
  final BlurEffect effect;
  final IconData icon;
  final Color accentColor;
  final BlurEffect selected;
  final void Function(BlurEffect) onTap;

  const _EffectChip({
    required this.label, required this.effect, required this.icon,
    required this.accentColor, required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = selected == effect;
    return GestureDetector(
      onTap: () => onTap(effect),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 74,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: isActive ? accentColor : const Color(0xFF252525),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? accentColor : const Color(0xFF363636),
            width: isActive ? 0 : 1,
          ),
          boxShadow: isActive
              ? [BoxShadow(color: accentColor.withOpacity(0.5),
              blurRadius: 12, offset: const Offset(0, 3))]
              : null,
        ),
        child: Column(mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19,
                  color: isActive ? Colors.white : const Color(0xFF4B5563)),
              const SizedBox(height: 5),
              Text(label, textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isActive ? Colors.white : const Color(0xFF4B5563),
                    fontSize: 10,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  )),
            ]),
      ),
    );
  }
}