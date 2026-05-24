import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/blur_region.dart';
import '../models/detection_result.dart';

enum _RH { tl, t, tr, r, br, b, bl, l }

Offset _rotPt(Offset p, Offset c, double angle) {
  final dx = p.dx - c.dx, dy = p.dy - c.dy;
  final cos = math.cos(angle), sin = math.sin(angle);
  return Offset(c.dx + dx * cos - dy * sin, c.dy + dx * sin + dy * cos);
}

Offset _handleBase(_RH h, Rect dr) => switch (h) {
  _RH.tl => dr.topLeft,
  _RH.t  => dr.topCenter,
  _RH.tr => dr.topRight,
  _RH.r  => dr.centerRight,
  _RH.br => dr.bottomRight,
  _RH.b  => dr.bottomCenter,
  _RH.bl => dr.bottomLeft,
  _RH.l  => dr.centerLeft,
};

class BlurRegionOverlay extends StatefulWidget {
  final List<BlurRegion> regions;
  final Size imageSize;
  final Size displaySize;
  final bool drawMode;
  final TransformationController transformationController;

  final void Function(BlurRegion) onRegionUpdated;
  final void Function(Rect) onRegionAdded;
  final void Function(String) onRegionDeleted;

  const BlurRegionOverlay({
    super.key,
    required this.regions,
    required this.imageSize,
    required this.displaySize,
    required this.drawMode,
    required this.transformationController,
    required this.onRegionUpdated,
    required this.onRegionAdded,
    required this.onRegionDeleted,
  });

  @override
  State<BlurRegionOverlay> createState() => _BlurRegionOverlayState();
}

class _BlurRegionOverlayState extends State<BlurRegionOverlay> {
  String? _selectedId;
  Offset? _drawStart;
  Rect? _drawingRect;

  double get _sx => widget.displaySize.width / widget.imageSize.width;
  double get _sy => widget.displaySize.height / widget.imageSize.height;

  Rect _toDisp(Rect img) => Rect.fromLTWH(
      img.left * _sx, img.top * _sy, img.width * _sx, img.height * _sy);

  Rect _toImg(Rect d) => Rect.fromLTWH(
      d.left / _sx, d.top / _sy, d.width / _sx, d.height / _sy);

  List<Offset> _corners(Rect dr, double angle) => [
    dr.topLeft, dr.topRight, dr.bottomRight, dr.bottomLeft
  ].map((p) => _rotPt(p, dr.center, angle)).toList();

  double get _zoomScale =>
      widget.transformationController.value.getMaxScaleOnAxis();

  RenderBox? get _renderBox => context.findRenderObject() as RenderBox?;

  // [Req 5] 리사이즈 콜백 — 줌 스케일 보정 포함
  void Function(Offset) _resizeCb(BlurRegion r, _RH handle) => (raw) {
    final cd = raw / _zoomScale;
    final id = Offset(cd.dx / _sx, cd.dy / _sy);
    final c = math.cos(-r.angle), s = math.sin(-r.angle);
    final ld = Offset(id.dx * c - id.dy * s, id.dx * s + id.dy * c);
    final nr = _applyResize(handle, r.boundingBox, ld, widget.imageSize);
    widget.onRegionUpdated(r.copyWith(boundingBox: nr));
  };

  static Rect _applyResize(_RH h, Rect o, Offset d, Size sz) {
    double l = o.left, t = o.top, r = o.right, b = o.bottom;
    switch (h) {
      case _RH.tl: l += d.dx; t += d.dy; break;
      case _RH.t:              t += d.dy; break;
      case _RH.tr: r += d.dx; t += d.dy; break;
      case _RH.r:  r += d.dx;            break;
      case _RH.br: r += d.dx; b += d.dy; break;
      case _RH.b:              b += d.dy; break;
      case _RH.bl: l += d.dx; b += d.dy; break;
      case _RH.l:  l += d.dx;            break;
    }
    l = l.clamp(0.0, sz.width);
    t = t.clamp(0.0, sz.height);
    r = r.clamp(0.0, sz.width);
    b = b.clamp(0.0, sz.height);
    const kMin = 8.0;
    if ((r - l).abs() < kMin) r = l + kMin;
    if ((b - t).abs() < kMin) b = t + kMin;
    return Rect.fromLTRB(
        math.min(l,r), math.min(t,b), math.max(l,r), math.max(t,b));
  }

  static Rect _norm(Rect r) => Rect.fromLTRB(
      math.min(r.left,r.right), math.min(r.top,r.bottom),
      math.max(r.left,r.right), math.max(r.top,r.bottom));

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.displaySize.width,
      height: widget.displaySize.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final region in widget.regions) _buildRegion(region),
          if (widget.drawMode && _drawingRect != null) _buildDrawPreview(),
          // [Req 2] 그리기 모드에서만 pan 인터셉터 활성
          if (widget.drawMode) _buildDrawOverlay(),
        ],
      ),
    );
  }

  Widget _buildRegion(BlurRegion region) {
    final dr = _toDisp(region.boundingBox);
    final isSel = _selectedId == region.id;
    final corners = _corners(dr, region.angle);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (region.isBlurred)
          _BlurPreview(corners: corners, displaySize: widget.displaySize, region: region),

        // [Req 1, 5] 박스 바디 탭 GestureDetector
        // translucent: 탭 처리, Pan은 InteractiveViewer 통과
        Positioned(
          left: dr.left, top: dr.top,
          child: Transform.rotate(
            angle: region.angle,
            alignment: Alignment.center,
            child: GestureDetector(
              // [Req 5] translucent + 최소 터치 크기 보장
              behavior: HitTestBehavior.translucent,
              onTap: () {
                setState(() => _selectedId = region.id);
                // [Req 1] 잠금 상태 체크 후 블러 토글
                if (!region.isLocked) {
                  widget.onRegionUpdated(
                      region.copyWith(isBlurred: !region.isBlurred));
                }
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                child: SizedBox(
                  width: dr.width, height: dr.height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CustomPaint(
                        size: Size(dr.width, dr.height),
                        painter: _BoxBorderPainter(
                          color: region.color,
                          isSelected: isSel,
                          isActive: region.isBlurred,
                        ),
                      ),
                      Positioned(
                        top: -22, left: 0,
                        child: _BoxLabel(region: region),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        if (isSel)
          _SelectionHandles(
            key: ValueKey('sel_${region.id}'),
            region: region,
            dispRect: dr,
            imageSize: widget.imageSize,
            resizeCb: _resizeCb,
            overlayRenderBox: () => _renderBox,
            onRotate: (a) => widget.onRegionUpdated(region.copyWith(angle: a)),
            onToggleLock: () => widget.onRegionUpdated(
                region.copyWith(isLocked: !region.isLocked)),
            onDelete: region.isManual
                ? () {
              widget.onRegionDeleted(region.id);
              setState(() => _selectedId = null);
            }
                : null,
          ),
      ],
    );
  }

  Widget _buildDrawPreview() {
    final n = _norm(_drawingRect!);
    return Positioned(
      left: n.left, top: n.top, width: n.width, height: n.height,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF00BCD4), width: 2),
            color: const Color(0xFF00BCD4).withOpacity(0.15),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawOverlay() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (d) => setState(() {
        _drawStart = d.localPosition;
        _drawingRect = Rect.fromLTWH(d.localPosition.dx, d.localPosition.dy, 0.01, 0.01);
        _selectedId = null;
      }),
      onPanUpdate: (d) {
        if (_drawStart == null) return;
        setState(() => _drawingRect = Rect.fromPoints(_drawStart!, d.localPosition));
      },
      onPanEnd: (_) {
        if (_drawingRect != null) {
          final n = _norm(_drawingRect!);
          if (n.width > 20 && n.height > 20) widget.onRegionAdded(_toImg(n));
        }
        setState(() { _drawStart = null; _drawingRect = null; });
      },
      child: SizedBox(width: widget.displaySize.width, height: widget.displaySize.height),
    );
  }
}

// ═══ 블러 프리뷰 (BackdropFilter, 8종) ═══════════════════════════════
class _BlurPreview extends StatelessWidget {
  final List<Offset> corners;
  final Size displaySize;
  final BlurRegion region;

  const _BlurPreview({
    required this.corners,
    required this.displaySize,
    required this.region,
  });

  @override
  Widget build(BuildContext context) => Positioned(
    left: 0, top: 0,
    width: displaySize.width, height: displaySize.height,
    child: ClipPath(clipper: _PolygonClipper(corners), child: _effect()),
  );

  Widget _effect() {
    switch (region.effect) {
      case BlurEffect.blackBar:
        return const ColoredBox(color: Colors.black);
      case BlurEffect.whiteBar:
        return const ColoredBox(color: Colors.white);
      case BlurEffect.redBar:
        return const ColoredBox(color: Color(0xFFDC1E1E));
      case BlurEffect.gaussian:
        return BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: region.blurIntensity.clamp(1.0, 30.0),
            sigmaY: region.blurIntensity.clamp(1.0, 30.0),
          ),
          child: Container(color: Colors.transparent),
        );
      case BlurEffect.mosaic:
        return Stack(children: [
          BackdropFilter(
            filter: ui.ImageFilter.blur(
              sigmaX: (region.blurIntensity * 0.8).clamp(4.0, 40.0),
              sigmaY: (region.blurIntensity * 0.8).clamp(4.0, 40.0),
            ),
            child: Container(color: Colors.transparent),
          ),
          CustomPaint(painter: _GridPainter(region.blurIntensity * 0.2 + 4)),
        ]);
      case BlurEffect.heavyPixelate:
        return Stack(children: [
          BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Container(color: Colors.transparent),
          ),
          CustomPaint(painter: _GridPainter(region.blurIntensity * 0.5 + 16)),
        ]);
      case BlurEffect.frostedGlass:
        return BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: region.blurIntensity.clamp(1.0, 20.0),
            sigmaY: region.blurIntensity.clamp(1.0, 20.0),
          ),
          child: Container(color: Colors.white.withOpacity(0.28)),
        );
      case BlurEffect.grayscaleBlur:
        return Stack(children: [
          BackdropFilter(
            filter: ui.ImageFilter.blur(
              sigmaX: region.blurIntensity.clamp(1.0, 20.0),
              sigmaY: region.blurIntensity.clamp(1.0, 20.0),
            ),
            child: Container(color: Colors.transparent),
          ),
          Container(color: Colors.grey.withOpacity(0.45)),
        ]);
    }
  }
}

class _PolygonClipper extends CustomClipper<Path> {
  final List<Offset> corners;
  const _PolygonClipper(this.corners);
  @override Path getClip(Size s) => Path()..addPolygon(corners, true);
  @override bool shouldReclip(_PolygonClipper o) => corners != o.corners;
}

class _GridPainter extends CustomPainter {
  final double tileSize;
  const _GridPainter(this.tileSize);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withOpacity(0.1)..strokeWidth = 0.5;
    for (double x = 0; x < size.width; x += tileSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += tileSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }
  @override bool shouldRepaint(_GridPainter o) => tileSize != o.tileSize;
}

class _BoxBorderPainter extends CustomPainter {
  final Color color;
  final bool isSelected, isActive;
  const _BoxBorderPainter({required this.color, required this.isSelected, required this.isActive});

  @override
  void paint(Canvas canvas, Size size) {
    final c = isActive ? color : color.withOpacity(0.35);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4)),
      Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = isSelected ? 3.0 : 2.0,
    );
    if (isSelected) {
      canvas.drawRRect(
        RRect.fromRectAndRadius((Offset.zero & size).deflate(1), const Radius.circular(3)),
        Paint()..color = c.withOpacity(0.1)..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(_BoxBorderPainter o) =>
      color != o.color || isSelected != o.isSelected || isActive != o.isActive;
}

class _BoxLabel extends StatelessWidget {
  final BlurRegion region;
  const _BoxLabel({required this.region});

  static String _el(BlurEffect e) => switch (e) {
    BlurEffect.gaussian      => 'G',
    BlurEffect.mosaic        => 'M',
    BlurEffect.blackBar      => 'B',
    BlurEffect.frostedGlass  => 'F',
    BlurEffect.whiteBar      => 'W',
    BlurEffect.redBar        => 'R',
    BlurEffect.heavyPixelate => 'HP',
    BlurEffect.grayscaleBlur => 'GS',
  };

  @override
  Widget build(BuildContext context) {
    final c = region.isBlurred ? region.color : region.color.withOpacity(0.4);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)),
          child: Text('${region.label} ${_el(region.effect)}',
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        if (region.isLocked)
          Container(
            margin: const EdgeInsets.only(left: 3),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: Colors.amber.shade700, borderRadius: BorderRadius.circular(4)),
            child: const Icon(Icons.lock, color: Colors.white, size: 9),
          ),
      ],
    );
  }
}

// ═══ 선택 핸들 ═══════════════════════════════════════════════════════
class _SelectionHandles extends StatelessWidget {
  final BlurRegion region;
  final Rect dispRect;
  final Size imageSize;
  final void Function(Offset) Function(BlurRegion, _RH) resizeCb;
  final RenderBox? Function() overlayRenderBox;
  final void Function(double) onRotate;
  final VoidCallback onToggleLock;
  final VoidCallback? onDelete;

  const _SelectionHandles({
    super.key,
    required this.region,
    required this.dispRect,
    required this.imageSize,
    required this.resizeCb,
    required this.overlayRenderBox,
    required this.onRotate,
    required this.onToggleLock,
    this.onDelete,
  });

  Offset _hp(_RH h) =>
      _rotPt(_handleBase(h, dispRect), dispRect.center, region.angle);

  @override
  Widget build(BuildContext context) {
    final color = region.color;
    final rotPos = _rotPt(
        Offset(dispRect.center.dx, dispRect.top - 48), dispRect.center, region.angle);
    final trPos = _hp(_RH.tr);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _DashLinePainter(
              from: _rotPt(Offset(dispRect.center.dx, dispRect.top), dispRect.center, region.angle),
              to: rotPos,
              color: color,
            ),
          ),
        ),
        for (final h in _RH.values)
          _ResizeHandle(
            key: ValueKey('rh_${region.id}_${h.name}'),
            position: _hp(h),
            color: color,
            onDelta: resizeCb(region, h),
          ),
        _RotationHandle(
          key: ValueKey('rot_${region.id}'),
          position: rotPos,
          boxCenter: dispRect.center,
          currentAngle: region.angle,
          color: color,
          overlayRenderBox: overlayRenderBox,
          onAngleChanged: onRotate,
        ),
        Positioned(
          left: trPos.dx + 8,
          top: trPos.dy - 22,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggleLock,
            child: _ActionDot(
              icon: region.isLocked ? Icons.lock : Icons.lock_open,
              color: region.isLocked ? Colors.amber.shade700 : Colors.grey.shade600,
            ),
          ),
        ),
        if (onDelete != null)
          Positioned(
            left: trPos.dx + 46,
            top: trPos.dy - 22,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDelete,
              child: const _ActionDot(icon: Icons.close, color: Color(0xFFE53935)),
            ),
          ),
      ],
    );
  }
}

// ─── [Req 5] 리사이즈 핸들 — 터치 영역 대폭 확장 ────────────────────
class _ResizeHandle extends StatefulWidget {
  final Offset position;
  final Color color;
  final void Function(Offset) onDelta;

  const _ResizeHandle({
    super.key, required this.position,
    required this.color, required this.onDelta,
  });

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  Offset? _last;

  @override
  Widget build(BuildContext context) {
    // [Req 5] 시각적 반경 20px + 투명 패딩 10px = 터치 유효 직경 60px
    const vr = 20.0;   // visual radius
    const pad = 10.0;  // invisible hitbox padding
    const total = vr + pad;

    return Positioned(
      left: widget.position.dx - total,
      top: widget.position.dy - total,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) => _last = d.globalPosition,
        onPanUpdate: (d) {
          if (_last == null) return;
          widget.onDelta(d.globalPosition - _last!);
          _last = d.globalPosition;
        },
        onPanEnd: (_) => _last = null,
        child: SizedBox(
          width: total * 2,
          height: total * 2,
          child: Center(
            child: Container(
              width: vr * 2,
              height: vr * 2,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: widget.color, width: 2.5),
                boxShadow: const [
                  BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2))
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── 회전 핸들 ────────────────────────────────────────────────────────
class _RotationHandle extends StatefulWidget {
  final Offset position;
  final Offset boxCenter;
  final double currentAngle;
  final Color color;
  final RenderBox? Function() overlayRenderBox;
  final void Function(double) onAngleChanged;

  const _RotationHandle({
    super.key, required this.position, required this.boxCenter,
    required this.currentAngle, required this.color,
    required this.overlayRenderBox, required this.onAngleChanged,
  });

  @override
  State<_RotationHandle> createState() => _RotationHandleState();
}

class _RotationHandleState extends State<_RotationHandle> {
  double? _startTouch, _startBox;

  @override
  Widget build(BuildContext context) {
    const vr = 20.0;
    const pad = 10.0;
    const total = vr + pad;

    return Positioned(
      left: widget.position.dx - total,
      top: widget.position.dy - total,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) {
          final ro = widget.overlayRenderBox();
          if (ro == null) return;
          final lp = ro.globalToLocal(d.globalPosition);
          _startTouch = math.atan2(
              lp.dy - widget.boxCenter.dy, lp.dx - widget.boxCenter.dx);
          _startBox = widget.currentAngle;
        },
        onPanUpdate: (d) {
          if (_startTouch == null || _startBox == null) return;
          final ro = widget.overlayRenderBox();
          if (ro == null) return;
          final lp = ro.globalToLocal(d.globalPosition);
          final cur = math.atan2(
              lp.dy - widget.boxCenter.dy, lp.dx - widget.boxCenter.dx);
          widget.onAngleChanged(_startBox! + (cur - _startTouch!));
        },
        onPanEnd: (_) { _startTouch = null; _startBox = null; },
        child: SizedBox(
          width: total * 2, height: total * 2,
          child: Center(
            child: Container(
              width: vr * 2, height: vr * 2,
              decoration: BoxDecoration(
                color: widget.color, shape: BoxShape.circle,
                boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6)],
              ),
              child: const Icon(Icons.rotate_right, color: Colors.white, size: 16),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashLinePainter extends CustomPainter {
  final Offset from, to;
  final Color color;
  const _DashLinePainter({required this.from, required this.to, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(from, to,
        Paint()..color = color.withOpacity(0.6)..strokeWidth = 1.5);
  }

  @override bool shouldRepaint(_DashLinePainter o) => from != o.from || to != o.to;
}

class _ActionDot extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _ActionDot({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: 30, height: 30,
    decoration: BoxDecoration(
      color: color, shape: BoxShape.circle,
      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
    ),
    child: Icon(icon, color: Colors.white, size: 15),
  );
}