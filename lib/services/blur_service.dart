import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../models/blur_region.dart';
import '../models/detection_result.dart';

class BlurService {
  Future<Uint8List> applyBlur(
      File imageFile,
      List<BlurRegion> regions,
      double imageWidth,
      double imageHeight,
      ) async {
    final bytes = await imageFile.readAsBytes();
    img.Image result = img.decodeImage(bytes)!;
    for (final region in regions) {
      if (!region.isBlurred) continue;
      result = _applyRegion(result, region);
    }
    return Uint8List.fromList(img.encodeJpg(result, quality: 92));
  }

  img.Image _applyRegion(img.Image src, BlurRegion region) =>
      region.angle.abs() < 0.01
          ? _applyRectBlur(src, region)
          : _applyRotatedBlur(src, region);

  // ── 비회전 Rect 블러 ─────────────────────────────────────────────
  img.Image _applyRectBlur(img.Image src, BlurRegion region) {
    final box = region.boundingBox;
    final l = box.left.clamp(0, src.width - 1).toInt();
    final t = box.top.clamp(0, src.height - 1).toInt();
    final r = box.right.clamp(0, src.width.toDouble()).toInt();
    final b = box.bottom.clamp(0, src.height.toDouble()).toInt();
    if (r <= l || b <= t) return src;
    final cw = r - l, ch = b - t;
    final crop = img.copyCrop(src, x: l, y: t, width: cw, height: ch);
    final processed = _processCrop(crop, region);
    img.compositeImage(src, processed, dstX: l, dstY: t);
    return src;
  }

  // ── 회전 박스 블러 ───────────────────────────────────────────────
  img.Image _applyRotatedBlur(img.Image src, BlurRegion region) {
    final box = region.boundingBox;
    final angle = region.angle;
    final cx = box.center.dx, cy = box.center.dy;
    final hw = box.width / 2, hh = box.height / 2;

    final aabb = _rotatedAABB(box, angle);
    final al = aabb.left.clamp(0, src.width - 1.0).toInt();
    final at = aabb.top.clamp(0, src.height - 1.0).toInt();
    final ar = aabb.right.clamp(0, src.width.toDouble()).toInt();
    final ab = aabb.bottom.clamp(0, src.height.toDouble()).toInt();
    if (ar <= al || ab <= at) return src;

    final cw = ar - al, ch = ab - at;
    final crop = img.copyCrop(src, x: al, y: at, width: cw, height: ch);
    final processed = _processCrop(crop, region);

    final cosN = math.cos(-angle), sinN = math.sin(-angle);
    final result = src.clone();
    for (int py = at; py < ab && py < src.height; py++) {
      for (int px = al; px < ar && px < src.width; px++) {
        final dx = px - cx, dy = py - cy;
        final lx = dx * cosN - dy * sinN;
        final ly = dx * sinN + dy * cosN;
        if (lx.abs() <= hw && ly.abs() <= hh) {
          final cpx = px - al, cpy = py - at;
          if (cpx >= 0 && cpx < processed.width &&
              cpy >= 0 && cpy < processed.height) {
            result.setPixel(px, py, processed.getPixel(cpx, cpy));
          }
        }
      }
    }
    return result;
  }

  // ── 효과별 이미지 처리 ───────────────────────────────────────────
  img.Image _processCrop(img.Image crop, BlurRegion region) {
    switch (region.effect) {
      case BlurEffect.gaussian:
        return img.gaussianBlur(crop,
            radius: region.blurIntensity.toInt().clamp(2, 50));

      case BlurEffect.frostedGlass:
      // [수정됨] 크리스탈 산란(Scatter) 효과 - 픽셀을 무작위로 흩뿌려 깨진 유리 느낌 구현
        final intensity = region.blurIntensity.toInt().clamp(2, 40);
        final result = crop.clone();
        final rand = math.Random(42);

        for (int y = 0; y < crop.height; y++) {
          for (int x = 0; x < crop.width; x++) {
            int dx = ((rand.nextDouble() - 0.5) * 2 * intensity).toInt();
            int dy = ((rand.nextDouble() - 0.5) * 2 * intensity).toInt();

            int nx = (x + dx).clamp(0, crop.width - 1);
            int ny = (y + dy).clamp(0, crop.height - 1);

            result.setPixel(x, y, crop.getPixel(nx, ny));
          }
        }
        return result;

      case BlurEffect.pixelate:
        return img.pixelate(crop,
            size: region.blurIntensity.toInt().clamp(2, 80),
            mode: img.PixelateMode.upperLeft);

      case BlurEffect.fog:
        final blurred = img.gaussianBlur(crop,
            radius: region.blurIntensity.toInt().clamp(5, 50));
        for (final p in blurred) {
          blurred.setPixelRgb(p.x, p.y,
            (p.r * 0.45 + 240 * 0.55).round().clamp(0, 255),
            (p.g * 0.45 + 240 * 0.55).round().clamp(0, 255),
            (p.b * 0.45 + 240 * 0.55).round().clamp(0, 255),
          );
        }
        return blurred;
    }
  }

  Rect _rotatedAABB(Rect rect, double angle) {
    final c = rect.center;
    final cosA = math.cos(angle), sinA = math.sin(angle);
    final corners = [rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft]
        .map((p) {
      final dx = p.dx - c.dx, dy = p.dy - c.dy;
      return Offset(c.dx + dx * cosA - dy * sinA, c.dy + dx * sinA + dy * cosA);
    }).toList();
    final xs = corners.map((p) => p.dx);
    final ys = corners.map((p) => p.dy);
    return Rect.fromLTRB(xs.reduce(math.min), ys.reduce(math.min),
        xs.reduce(math.max), ys.reduce(math.max));
  }
}