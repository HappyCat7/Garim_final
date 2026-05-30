import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/blur_region.dart';
import '../models/detection_result.dart';

enum _RH { tl, t, tr, r, br, b, bl, l }

Offset _rotPt(Offset p, Offset c, double a) {
  final dx = p.dx - c.dx, dy = p.dy - c.dy;
  final cos = math.cos(a), sin = math.sin(a);
  return Offset(c.dx + dx * cos - dy * sin, c.dy + dx * sin + dy * cos);
}

Offset _handleBase(_RH h, Rect dr) => switch (h) {
  _RH.tl => dr.topLeft,   _RH.t => dr.topCenter,  _RH.tr => dr.topRight,
  _RH.r  => dr.centerRight, _RH.br => dr.bottomRight,
  _RH.b  => dr.bottomCenter, _RH.bl => dr.bottomLeft, _RH.l => dr.centerLeft,
};

class BlurRegionOverlay extends StatefulWidget {
  final List<BlurRegion> regions;
  final Size imageSize;
  final Size displaySize;
  final bool drawMode;
  final TransformationController transformationController;
  final String? selectedId;

  final void Function(BlurRegion) onRegionUpdated;
  final void Function(Rect) onRegionAdded;
  final void Function(String) onRegionDeleted;
  final VoidCallback? onEditCommit;
  final void Function(String? id) onSelectionChanged;

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
    required this.onSelectionChanged,
    this.selectedId,
    this.onEditCommit,
  });

  @override
  State<BlurRegionOverlay> createState() => _BlurRegionOverlayState();
}

class _BlurRegionOverlayState extends State<BlurRegionOverlay> {
  String? _selectedId;
  Offset? _drawStart;
  Rect? _drawingRect;
  Offset? _boxDragLast;

  double get _sx => widget.displaySize.width / widget.imageSize.width;
  double get _sy => widget.displaySize.height / widget.imageSize.height;

  Rect _toDisp(Rect img) => Rect.fromLTWH(
      img.left * _sx, img.top * _sy, img.width * _sx, img.height * _sy);
  Rect _toImg(Rect d) => Rect.fromLTWH(
      d.left / _sx, d.top / _sy, d.width / _sx, d.height / _sy);

  List<Offset> _corners(Rect dr, double a) =>
      [dr.topLeft, dr.topRight, dr.bottomRight, dr.bottomLeft]
          .map((p) => _rotPt(p, dr.center, a)).toList();

  double get _zoomScale =>
      widget.transformationController.value.getMaxScaleOnAxis();
  RenderBox? get _renderBox => context.findRenderObject() as RenderBox?;

  @override
  void didUpdateWidget(BlurRegionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedId != _selectedId) {
      _selectedId = widget.selectedId;
    }
  }

  void _select(String? id) {
    if (_selectedId == id) return;
    setState(() => _selectedId = id);
    widget.onSelectionChanged(id);
  }

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
    l = l.clamp(0.0, sz.width); t = t.clamp(0.0, sz.height);
    r = r.clamp(0.0, sz.width); b = b.clamp(0.0, sz.height);
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
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () { if (_selectedId != null) _select(null); },
            ),
          ),
          for (final region in widget.regions) _buildRegion(region),
          if (widget.drawMode && _drawingRect != null) _buildDrawPreview(),
          if (widget.drawMode) _buildDrawOverlay(),
        ],
      ),
    );
  }

  Widget _buildRegion(BlurRegion region) {
    final dr = _toDisp(region.boundingBox);
    final isSel = _selectedId == region.id;
    final isRotated = region.angle.abs() > 0.01;
    final corners = isRotated ? _corners(dr, region.angle) : null;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (region.isBlurred)
          if (!isRotated)
            Positioned(
              left: dr.left, top: dr.top,
              width: dr.width, height: dr.height,
              child: ClipRect(child: _buildEffect(region)),
            )
          else
            Positioned(
              left: 0, top: 0,
              width: widget.displaySize.width,
              height: widget.displaySize.height,
              child: ClipPath(
                clipper: _PolygonClipper(corners!),
                clipBehavior: Clip.hardEdge,
                child: _buildEffect(region),
              ),
            ),

        Positioned(
          left: dr.left, top: dr.top,
          child: Transform.rotate(
            angle: region.angle,
            alignment: Alignment.center,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) {
                HapticFeedback.lightImpact();
                _select(region.id);
              },
              onPanStart: (d) {
                HapticFeedback.selectionClick();
                _select(region.id);
                _boxDragLast = d.globalPosition;
              },
              onPanUpdate: (d) {
                if (_boxDragLast == null) return;
                final delta = d.globalPosition - _boxDragLast!;
                _boxDragLast = d.globalPosition;

                final dx = delta.dx / (_zoomScale * _sx);
                final dy = delta.dy / (_zoomScale * _sy);

                final shiftedBox = region.boundingBox.shift(Offset(dx, dy));
                widget.onRegionUpdated(region.copyWith(boundingBox: shiftedBox));
              },
              onPanEnd: (_) {
                _boxDragLast = null;
                widget.onEditCommit?.call();
              },

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
                  ],
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
            onRotate: (a) =>
                widget.onRegionUpdated(region.copyWith(angle: a)),
            onDelete: region.isManual
                ? () {
              widget.onRegionDeleted(region.id);
              _select(null);
            }
                : null,
            onCommit: widget.onEditCommit,
          ),
      ],
    );
  }

  Widget _buildEffect(BlurRegion region) {
    final intensity = region.blurIntensity;

    switch (region.effect) {
      case BlurEffect.gaussian:
        return BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: intensity, sigmaY: intensity),
          child: Container(color: Colors.transparent),
        );

      case BlurEffect.frostedGlass:
        return Stack(fit: StackFit.expand, children: [
          BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
            child: Container(color: Colors.transparent),
          ),
          CustomPaint(painter: _ScatteredGlassPainter(intensity)),
        ]);

      case BlurEffect.pixelate:
        return Stack(fit: StackFit.expand, children: [
          BackdropFilter(
            filter: ui.ImageFilter.blur(
              sigmaX: (intensity * 0.4).clamp(4, 40),
              sigmaY: (intensity * 0.4).clamp(4, 40),
            ),
            child: Container(color: Colors.transparent),
          ),
          CustomPaint(painter: _GridPainter(intensity * 0.5 + 4)),
        ]);

      case BlurEffect.fog:
        return Stack(fit: StackFit.expand, children: [
          BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: intensity, sigmaY: intensity),
            child: Container(color: Colors.transparent),
          ),
          Container(color: const Color(0xFFF0F0F0).withOpacity(0.55)),
        ]);

      case BlurEffect.point:
        return Stack(fit: StackFit.expand, children: [
          BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
            child: Container(color: Colors.white.withOpacity(0.15)),
          ),
          CustomPaint(painter: _PointPainter(intensity)),
        ]);
    }
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

  Widget _buildDrawOverlay() => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onPanStart: (d) => setState(() {
      _drawStart = d.localPosition;
      _drawingRect = Rect.fromLTWH(d.localPosition.dx, d.localPosition.dy, 0.01, 0.01);
      _select(null);
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

// ═══ Painters ════════════════════════════════════════════════════════

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
    final p = Paint()..color = Colors.black.withOpacity(0.12)..strokeWidth = 0.5;
    for (double x = 0; x < size.width; x += tileSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += tileSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }
  @override bool shouldRepaint(_GridPainter o) => tileSize != o.tileSize;
}

class _ScatteredGlassPainter extends CustomPainter {
  final double intensity;
  const _ScatteredGlassPainter(this.intensity);

  @override
  void paint(Canvas canvas, Size size) {
    final rand = math.Random(42);
    final paint = Paint()..style = PaintingStyle.fill;

    int numDots = (size.width * size.height / (60 - intensity.clamp(5, 55))).toInt();

    for (int i = 0; i < numDots; i++) {
      double x = rand.nextDouble() * size.width;
      double y = rand.nextDouble() * size.height;
      double r = rand.nextDouble() * (intensity * 0.08).clamp(1.0, 3.5);

      paint.color = rand.nextBool()
          ? Colors.white.withOpacity(rand.nextDouble() * 0.6 + 0.2)
          : Colors.white.withOpacity(0.1);

      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(_ScatteredGlassPainter o) => intensity != o.intensity;
}

class _PointPainter extends CustomPainter {
  final double intensity;
  const _PointPainter(this.intensity);

  @override
  void paint(Canvas canvas, Size size) {
    final rand = math.Random(42);
    final paint = Paint()..style = PaintingStyle.fill;
    int numDots = (size.width * size.height / 50).toInt();

    for (int i = 0; i < numDots; i++) {
      double x = rand.nextDouble() * size.width;
      double y = rand.nextDouble() * size.height;
      double r = rand.nextDouble() * (intensity * 0.15) + 2.0;

      paint.color = Colors.black.withOpacity(rand.nextDouble() * 0.3 + 0.1);
      canvas.drawCircle(Offset(x, y), r, paint);

      paint.color = Colors.white.withOpacity(rand.nextDouble() * 0.5 + 0.1);
      canvas.drawCircle(Offset(x + r, y + r), r * 0.8, paint);
    }
  }
  @override bool shouldRepaint(_PointPainter o) => intensity != o.intensity;
}

class _BoxBorderPainter extends CustomPainter {
  final Color color;
  final bool isSelected, isActive;
  const _BoxBorderPainter({required this.color, required this.isSelected, required this.isActive});

  @override
  void paint(Canvas canvas, Size size) {
    final c = isActive ? color : color.withOpacity(0.35);
    if (isSelected) {
      canvas.drawRRect(
        RRect.fromRectAndRadius((Offset.zero & size).inflate(4), const Radius.circular(8)),
        Paint()
          ..color = c.withOpacity(0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 8),
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4)),
      Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = isSelected ? 1.5 : 1.0,
    );
    if (isSelected) {
      canvas.drawRRect(
        RRect.fromRectAndRadius((Offset.zero & size).deflate(1), const Radius.circular(3)),
        Paint()..color = c.withOpacity(0.09)..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(_BoxBorderPainter o) =>
      color != o.color || isSelected != o.isSelected || isActive != o.isActive;
}

class _SelectionHandles extends StatelessWidget {
  final BlurRegion region;
  final Rect dispRect;
  final Size imageSize;
  final void Function(Offset) Function(BlurRegion, _RH) resizeCb;
  final RenderBox? Function() overlayRenderBox;
  final void Function(double) onRotate;
  final VoidCallback? onDelete;
  final VoidCallback? onCommit;

  const _SelectionHandles({
    super.key, required this.region, required this.dispRect,
    required this.imageSize, required this.resizeCb,
    required this.overlayRenderBox, required this.onRotate,
    this.onDelete, this.onCommit,
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
          child: IgnorePointer(
            child: CustomPaint(painter: _DashLinePainter(
              from: _rotPt(Offset(dispRect.center.dx, dispRect.top),
                  dispRect.center, region.angle),
              to: rotPos, color: color,
            )),
          ),
        ),
        for (final h in _RH.values)
          _ResizeHandle(
            key: ValueKey('rh_${region.id}_${h.name}'),
            position: _hp(h), color: color,
            onDelta: resizeCb(region, h), onCommit: onCommit,
          ),
        _RotationHandle(
          key: ValueKey('rot_${region.id}'),
          position: rotPos, boxCenter: dispRect.center,
          currentAngle: region.angle, color: color,
          overlayRenderBox: overlayRenderBox,
          onAngleChanged: onRotate, onCommit: onCommit,
        ),
        if (onDelete != null)
          Positioned(
            left: trPos.dx + 6, top: trPos.dy - 24,
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

class _ResizeHandle extends StatefulWidget {
  final Offset position;
  final Color color;
  final void Function(Offset) onDelta;
  final VoidCallback? onCommit;

  const _ResizeHandle({
    super.key, required this.position,
    required this.color, required this.onDelta, this.onCommit,
  });

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  Offset? _last;

  @override
  Widget build(BuildContext context) {
    const vr = 3.5;
    // 💡 크기 조절 인식 영역(Padding)을 24px -> 10px로 대폭 줄여서 오작동 방지!
    const pad = 10.0;
    const total = vr + pad;

    return Positioned(
      left: widget.position.dx - total,
      top: widget.position.dy - total,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) {
          HapticFeedback.selectionClick();
          _last = d.globalPosition;
        },
        onPanUpdate: (d) {
          if (_last == null) return;
          widget.onDelta(d.globalPosition - _last!);
          _last = d.globalPosition;
        },
        onPanEnd: (_) { _last = null; widget.onCommit?.call(); },
        child: SizedBox(
          width: total * 2, height: total * 2,
          child: Center(
            child: Container(
              width: vr * 2, height: vr * 2,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: widget.color, width: 1.5),
                boxShadow: const [
                  BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 1))
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RotationHandle extends StatefulWidget {
  final Offset position, boxCenter;
  final double currentAngle;
  final Color color;
  final RenderBox? Function() overlayRenderBox;
  final void Function(double) onAngleChanged;
  final VoidCallback? onCommit;

  const _RotationHandle({
    super.key, required this.position, required this.boxCenter,
    required this.currentAngle, required this.color,
    required this.overlayRenderBox, required this.onAngleChanged, this.onCommit,
  });

  @override
  State<_RotationHandle> createState() => _RotationHandleState();
}

class _RotationHandleState extends State<_RotationHandle> {
  double? _startTouch, _startBox;

  @override
  Widget build(BuildContext context) {
    const vr = 5.5;
    // 💡 회전 인식 영역(Padding)도 16px -> 10px로 줄였습니다.
    const pad = 10.0;
    const total = vr + pad;

    return Positioned(
      left: widget.position.dx - total,
      top: widget.position.dy - total,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) {
          HapticFeedback.selectionClick();
          final ro = widget.overlayRenderBox(); if (ro == null) return;
          final lp = ro.globalToLocal(d.globalPosition);
          _startTouch = math.atan2(lp.dy - widget.boxCenter.dy, lp.dx - widget.boxCenter.dx);
          _startBox = widget.currentAngle;
        },
        onPanUpdate: (d) {
          if (_startTouch == null || _startBox == null) return;
          final ro = widget.overlayRenderBox(); if (ro == null) return;
          final lp = ro.globalToLocal(d.globalPosition);
          final cur = math.atan2(lp.dy - widget.boxCenter.dy, lp.dx - widget.boxCenter.dx);
          widget.onAngleChanged(_startBox! + (cur - _startTouch!));
        },
        onPanEnd: (_) { _startTouch = null; _startBox = null; widget.onCommit?.call(); },
        child: SizedBox(
          width: total * 2, height: total * 2,
          child: Center(
            child: Container(
              width: vr * 2, height: vr * 2,
              decoration: BoxDecoration(
                color: widget.color, shape: BoxShape.circle,
                boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 5)],
              ),
              child: const Icon(Icons.rotate_right, color: Colors.white, size: 9),
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
  void paint(Canvas canvas, Size size) => canvas.drawLine(from, to,
      Paint()..color = color.withOpacity(0.6)..strokeWidth = 1.5);
  @override bool shouldRepaint(_DashLinePainter o) => from != o.from || to != o.to;
}

class _ActionDot extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _ActionDot({required this.icon, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    width: 28, height: 28,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle,
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)]),
    child: Icon(icon, color: Colors.white, size: 14),
  );
}