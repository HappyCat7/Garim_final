import 'package:flutter/material.dart';
import '../models/detection_result.dart';
import '../models/manual_blur_box.dart';

// ─── 내부 enum: 드래그 중인 핸들 종류 ────────────────────────────────
enum _Handle {
  none,
  topLeft, top, topRight,
  right,
  bottomRight, bottom, bottomLeft,
  left,
  body, // 박스 내부 터치 → 선택 전용 (이동 미구현)
}

// ─── 내부 클래스: 선택 상태 ────────────────────────────────────────
class _Selection {
  final bool isManual; // true=수동박스 / false=자동탐지
  final int index;     // manualBoxes 또는 detections 인덱스
  final String? manualId;

  const _Selection({
    required this.isManual,
    required this.index,
    this.manualId,
  });
}

/// DetectionOverlay
///
/// - [editMode] = false : GestureDetector 완전 비활성 (InteractiveViewer에 제스처 양보)
/// - [editMode] = true  : 제스처 활성 (드래그=박스 생성, 핸들 드래그=리사이즈, 탭=선택)
/// - 모든 Rect 저장은 원본 이미지 좌표 기준, 렌더링 시 displaySize로 스케일 변환
class DetectionOverlay extends StatefulWidget {
  // ── 기본 설정 ──
  final bool editMode;
  final Size imageSize;   // 원본 이미지 크기 (px)
  final Size displaySize; // 화면에 표시된 이미지 크기 (dp)

  // ── 자동 탐지 ──
  final List<DetectionResult> detections;
  final Map<int, Rect> detectionOverrides;      // 리사이즈된 자동탐지 rect (index→rect)
  final Map<DetectionType, bool> typeBlurEnabled;

  // ── 수동 박스 ──
  final List<ManualBlurBox> manualBoxes;

  // ── 개인정보 텍스트 영역 ──
  final List<DetectionResult> privacyDetections;
  final List<DetectionResult> cardPrivacyDetections;
  final bool useTextBlur;
  final bool useCardTextBlur;

  // ── 콜백 ──
  final void Function(Rect imageRect) onManualBoxAdded;
  final void Function(String id, Rect imageRect) onManualBoxUpdated;
  final void Function(String id) onManualBoxDeleted;
  final void Function(int index, Rect imageRect) onDetectionResized;

  const DetectionOverlay({
    super.key,
    required this.editMode,
    required this.imageSize,
    required this.displaySize,
    required this.detections,
    required this.detectionOverrides,
    required this.typeBlurEnabled,
    required this.manualBoxes,
    required this.privacyDetections,
    required this.cardPrivacyDetections,
    required this.useTextBlur,
    required this.useCardTextBlur,
    required this.onManualBoxAdded,
    required this.onManualBoxUpdated,
    required this.onManualBoxDeleted,
    required this.onDetectionResized,
  });

  @override
  State<DetectionOverlay> createState() => _DetectionOverlayState();
}

class _DetectionOverlayState extends State<DetectionOverlay> {
  // ── 선택 상태 ──
  _Selection? _sel;
  _Handle _handle = _Handle.none;

  // ── 새 박스 드로우 상태 ──
  bool _drawing = false;
  Offset? _drawStart;       // 드로우 시작점 (display coords)
  Rect? _drawingRect;       // 현재 그리는 중인 rect (display coords)

  // ── 리사이즈 상태 ──
  Offset? _resizeAnchor;     // 드래그 시작 위치 (display coords)
  Rect? _resizeOriginImage;  // 드래그 시작 시점의 rect (image coords)
  Rect? _liveImageRect;      // 드래그 중 실시간 rect (image coords)

  // ── 상수 ──
  static const double _kHandleR  = 15.0; // 핸들 히트 반경 (dp)
  static const double _kMinBoxDp = 18.0; // 새 박스 최소 크기 (dp)

  // ── 좌표 변환 헬퍼 ──────────────────────────────────────────────
  double get _sx => widget.displaySize.width  / widget.imageSize.width;
  double get _sy => widget.displaySize.height / widget.imageSize.height;

  Rect _toDisp(Rect img) => Rect.fromLTWH(
    img.left * _sx, img.top * _sy, img.width * _sx, img.height * _sy,
  );

  Rect _toImg(Rect disp) => Rect.fromLTWH(
    disp.left / _sx, disp.top / _sy, disp.width / _sx, disp.height / _sy,
  );

  /// 자동 탐지 박스의 유효 rect (오버라이드 우선)
  Rect _effAutoRect(int i) =>
      widget.detectionOverrides[i] ?? widget.detections[i].boundingBox;

  /// 선택된 박스의 현재 이미지 rect (드래그 중이면 live값)
  Rect? get _selImageRect {
    if (_sel == null) return null;
    if (_liveImageRect != null) return _liveImageRect;
    if (_sel!.isManual) {
      if (_sel!.index >= widget.manualBoxes.length) return null;
      return widget.manualBoxes[_sel!.index].rect;
    } else {
      if (_sel!.index >= widget.detections.length) return null;
      return _effAutoRect(_sel!.index);
    }
  }

  // ── 히트 테스트 ─────────────────────────────────────────────────

  _Handle _hitHandle(Rect dr, Offset pos) {
    final pts = <_Handle, Offset>{
      _Handle.topLeft:     dr.topLeft,
      _Handle.top:         dr.topCenter,
      _Handle.topRight:    dr.topRight,
      _Handle.right:       dr.centerRight,
      _Handle.bottomRight: dr.bottomRight,
      _Handle.bottom:      dr.bottomCenter,
      _Handle.bottomLeft:  dr.bottomLeft,
      _Handle.left:        dr.centerLeft,
    };
    for (final e in pts.entries) {
      if ((pos - e.value).distance <= _kHandleR) return e.key;
    }
    if (dr.inflate(4).contains(pos)) return _Handle.body;
    return _Handle.none;
  }

  /// 전체 박스 히트 테스트 (수동 박스 우선 → 자동 탐지 순서)
  _Selection? _hitBox(Offset pos) {
    for (int i = widget.manualBoxes.length - 1; i >= 0; i--) {
      if (_toDisp(widget.manualBoxes[i].rect).inflate(4).contains(pos)) {
        return _Selection(isManual: true, index: i, manualId: widget.manualBoxes[i].id);
      }
    }
    for (int i = widget.detections.length - 1; i >= 0; i--) {
      if (_toDisp(_effAutoRect(i)).inflate(4).contains(pos)) {
        return _Selection(isManual: false, index: i);
      }
    }
    return null;
  }

  // ── 리사이즈 계산 ───────────────────────────────────────────────

  Rect _applyResize(_Handle handle, Rect origin, Offset imgDelta) {
    double l = origin.left, t = origin.top,
        r = origin.right, b = origin.bottom;
    final dx = imgDelta.dx, dy = imgDelta.dy;

    switch (handle) {
      case _Handle.topLeft:     l += dx; t += dy; break;
      case _Handle.top:         t += dy;           break;
      case _Handle.topRight:    r += dx; t += dy; break;
      case _Handle.right:       r += dx;           break;
      case _Handle.bottomRight: r += dx; b += dy; break;
      case _Handle.bottom:      b += dy;           break;
      case _Handle.bottomLeft:  l += dx; b += dy; break;
      case _Handle.left:        l += dx;           break;
      default: break;
    }

    // 이미지 범위 클램프
    l = l.clamp(0.0, widget.imageSize.width);
    t = t.clamp(0.0, widget.imageSize.height);
    r = r.clamp(0.0, widget.imageSize.width);
    b = b.clamp(0.0, widget.imageSize.height);

    // 최소 크기 강제 (image coords 10px)
    const kMin = 10.0;
    if ((r - l).abs() < kMin) {
      final movesLeft = handle == _Handle.left ||
          handle == _Handle.topLeft || handle == _Handle.bottomLeft;
      if (movesLeft) {
        l = r - kMin;
      } else {
        r = l + kMin;
      }
    }
    if ((b - t).abs() < kMin) {
      final movesTop = handle == _Handle.top ||
          handle == _Handle.topLeft || handle == _Handle.topRight;
      if (movesTop) {
        t = b - kMin;
      } else {
        b = t + kMin;
      }
    }

    // 반전 정규화
    return Rect.fromLTRB(
      l < r ? l : r, t < b ? t : b,
      l < r ? r : l, t < b ? b : t,
    );
  }

  static Rect _normalize(Rect r) => Rect.fromLTRB(
    r.left  < r.right  ? r.left  : r.right,
    r.top   < r.bottom ? r.top   : r.bottom,
    r.left  < r.right  ? r.right : r.left,
    r.top   < r.bottom ? r.bottom: r.top,
  );

  // ── 제스처 핸들러 ────────────────────────────────────────────────

  void _onPanStart(DragStartDetails d) {
    final pos = d.localPosition;

    // 1) 선택된 박스의 핸들인가?
    if (_sel != null && _selImageRect != null) {
      final selDisp = _toDisp(_selImageRect!);
      final h = _hitHandle(selDisp, pos);
      if (h != _Handle.none) {
        _handle = h;
        _resizeAnchor = pos;
        _resizeOriginImage = _selImageRect;
        _liveImageRect = _resizeOriginImage;
        return; // setState 불필요 (live rect는 onPanUpdate에서 갱신)
      }
    }

    // 2) 아무 박스라도 히트? → 선택 + 이동 준비 (이동 미구현이므로 선택만)
    final hit = _hitBox(pos);
    if (hit != null) {
      setState(() {
        _sel = hit;
        _handle = _Handle.body;
        _drawing = false;
        _drawingRect = null;
        _liveImageRect = null;
      });
      _resizeAnchor = pos;
      _resizeOriginImage = hit.isManual
          ? widget.manualBoxes[hit.index].rect
          : _effAutoRect(hit.index);
      _liveImageRect = _resizeOriginImage;
      return;
    }

    // 3) 빈 공간 → 새 박스 그리기 시작
    setState(() {
      _sel = null;
      _handle = _Handle.none;
      _drawing = true;
      _drawStart = pos;
      _drawingRect = Rect.fromLTWH(pos.dx, pos.dy, 0.001, 0.001);
      _liveImageRect = null;
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final pos = d.localPosition;

    // 새 박스 드로우 업데이트
    if (_drawing && _drawStart != null) {
      setState(() => _drawingRect = Rect.fromPoints(_drawStart!, pos));
      return;
    }

    // 핸들 리사이즈 (body는 이동 미구현 → 무시)
    if (_handle != _Handle.none && _handle != _Handle.body &&
        _sel != null &&
        _resizeAnchor != null && _resizeOriginImage != null) {
      final totalDisp = pos - _resizeAnchor!;
      final imgDelta = Offset(totalDisp.dx / _sx, totalDisp.dy / _sy);
      setState(() =>
      _liveImageRect = _applyResize(_handle, _resizeOriginImage!, imgDelta));
    }
  }

  void _onPanEnd(DragEndDetails _) {
    // ── 새 박스 확정 ──
    if (_drawing && _drawingRect != null) {
      final norm = _normalize(_drawingRect!);
      if (norm.width >= _kMinBoxDp && norm.height >= _kMinBoxDp) {
        widget.onManualBoxAdded(_toImg(norm));
      }
      setState(() {
        _drawing = false;
        _drawStart = null;
        _drawingRect = null;
      });
      return;
    }

    // ── 리사이즈 확정 ──
    if (_handle != _Handle.none && _handle != _Handle.body &&
        _sel != null && _liveImageRect != null) {
      final committed = _liveImageRect!;
      if (_sel!.isManual) {
        widget.onManualBoxUpdated(_sel!.manualId!, committed);
      } else {
        widget.onDetectionResized(_sel!.index, committed);
      }
      setState(() {
        _handle = _Handle.none;
        _resizeAnchor = null;
        _resizeOriginImage = null;
        _liveImageRect = null;
      });
    }
  }

  void _onTapUp(TapUpDetails d) {
    // 탭 = 선택 / 선택 해제
    final hit = _hitBox(d.localPosition);
    setState(() {
      _sel = hit;
      _drawing = false;
      _drawingRect = null;
      _liveImageRect = null;
    });
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // edit 모드: opaque(터치 흡수) / view 모드: translucent(InteractiveViewer에 양보)
      behavior: widget.editMode
          ? HitTestBehavior.opaque
          : HitTestBehavior.translucent,
      onTapUp:     widget.editMode ? _onTapUp     : null,
      onPanStart:  widget.editMode ? _onPanStart  : null,
      onPanUpdate: widget.editMode ? _onPanUpdate : null,
      onPanEnd:    widget.editMode ? _onPanEnd    : null,
      child: SizedBox(
        width: widget.displaySize.width,
        height: widget.displaySize.height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // ① 자동 탐지 박스
            ..._buildAutoBoxes(),
            // ② 문서 개인정보 텍스트 영역
            if (widget.useTextBlur)
              ..._buildPrivacyAreas(widget.privacyDetections, const Color(0xFF43E97B)),
            // ③ 카드 개인정보 텍스트 영역
            if (widget.useCardTextBlur)
              ..._buildPrivacyAreas(widget.cardPrivacyDetections, Colors.orange),
            // ④ 수동 박스
            ..._buildManualBoxes(),
            // ⑤ 드로우 미리보기 (그리는 중)
            if (_drawing && _drawingRect != null) _buildDrawPreview(),
            // ⑥ 삭제 버튼 (선택 상태 + 편집 모드)
            if (_sel != null && _selImageRect != null && widget.editMode)
              _buildDeleteBtn(),
          ],
        ),
      ),
    );
  }

  // ── Box 렌더러 ──────────────────────────────────────────────────

  List<Widget> _buildAutoBoxes() {
    return widget.detections.asMap().entries.map((entry) {
      final i = entry.key;
      final d = entry.value;
      final isActive = widget.typeBlurEnabled[d.type] ?? true;
      final isSel = _sel != null && !_sel!.isManual && _sel!.index == i;
      final imgRect =
      (isSel && _liveImageRect != null) ? _liveImageRect! : _effAutoRect(i);

      return _buildBoxWidget(
        displayRect: _toDisp(imgRect),
        color: d.typeColor,
        label: isActive ? d.typeLabel : '${d.typeLabel} (OFF)',
        isActive: isActive,
        isSelected: isSel,
        showHandles: isSel && widget.editMode,
      );
    }).toList();
  }

  List<Widget> _buildManualBoxes() {
    return widget.manualBoxes.asMap().entries.map((entry) {
      final i = entry.key;
      final box = entry.value;
      final isSel = _sel != null && _sel!.isManual && _sel!.index == i;
      final imgRect =
      (isSel && _liveImageRect != null) ? _liveImageRect! : box.rect;

      return _buildBoxWidget(
        displayRect: _toDisp(imgRect),
        color: const Color(0xFF00BCD4),
        label: '수동',
        isActive: true,
        isSelected: isSel,
        showHandles: isSel && widget.editMode,
      );
    }).toList();
  }

  Widget _buildBoxWidget({
    required Rect displayRect,
    required Color color,
    required String label,
    required bool isActive,
    required bool isSelected,
    required bool showHandles,
  }) {
    final borderColor = isActive ? color : color.withValues(alpha: 0.3);

    return Positioned(
      left: displayRect.left,
      top: displayRect.top,
      width: displayRect.width,
      height: displayRect.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 박스 테두리
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: borderColor,
                width: isSelected ? 3.0 : 2.0,
              ),
              color: isSelected
                  ? color.withValues(alpha: 0.07)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          // 레이블
          Positioned(
            top: -22,
            left: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: borderColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          // 8개 리사이즈 핸들 (선택 상태 + 편집 모드)
          if (showHandles) ..._buildHandles(displayRect.size, color),
        ],
      ),
    );
  }

  /// 8방향 리사이즈 핸들 (박스 로컬 좌표 기준)
  List<Widget> _buildHandles(Size boxSize, Color color) {
    final w = boxSize.width;
    final h = boxSize.height;
    final positions = [
      Offset(0,     0    ), // topLeft
      Offset(w / 2, 0    ), // top
      Offset(w,     0    ), // topRight
      Offset(w,     h / 2), // right
      Offset(w,     h    ), // bottomRight
      Offset(w / 2, h    ), // bottom
      Offset(0,     h    ), // bottomLeft
      Offset(0,     h / 2), // left
    ];

    return positions.map((p) {
      return Positioned(
        left: p.dx - _kHandleR,
        top:  p.dy - _kHandleR,
        width:  _kHandleR * 2,
        height: _kHandleR * 2,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  /// 드래그 중 새 박스 미리보기
  Widget _buildDrawPreview() {
    final norm = _normalize(_drawingRect!);
    return Positioned(
      left:   norm.left,
      top:    norm.top,
      width:  norm.width,
      height: norm.height,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF00BCD4), width: 2.0),
          color: const Color(0xFF00BCD4).withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  /// 선택된 박스 우상단의 삭제(또는 잠금) 버튼
  Widget _buildDeleteBtn() {
    final ir = _selImageRect;
    if (ir == null) return const SizedBox.shrink();
    final dr = _toDisp(ir);
    final isManual = _sel!.isManual;

    return Positioned(
      // 박스 우상단 모서리에서 핸들 반경만큼 오프셋
      left: dr.right - _kHandleR,
      top:  dr.top   - _kHandleR,
      child: GestureDetector(
        onTap: () {
          if (isManual && _sel!.manualId != null) {
            // 수동 박스 삭제
            widget.onManualBoxDeleted(_sel!.manualId!);
          }
          // 자동 탐지는 삭제 불가 (잠금 아이콘) → 선택만 해제
          setState(() {
            _sel = null;
            _liveImageRect = null;
          });
        },
        child: Container(
          width:  _kHandleR * 2,
          height: _kHandleR * 2,
          decoration: BoxDecoration(
            color: isManual ? Colors.red.shade600 : Colors.grey.shade700,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 4,
              ),
            ],
          ),
          child: Icon(
            isManual ? Icons.close : Icons.lock_outline,
            color: Colors.white,
            size: 14,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPrivacyAreas(
      List<DetectionResult> items, Color color) {
    return items.map((d) {
      final dr = _toDisp(d.boundingBox);
      return Positioned(
        left: dr.left, top: dr.top,
        width: dr.width, height: dr.height,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 2),
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      );
    }).toList();
  }
}