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

  img.Image _applyRectBlur(img.Image src, BlurRegion region) {
    final box = region.boundingBox;
    final l = box.left.clamp(0, src.width - 1).toInt();
    final t = box.top.clamp(0, src.height - 1).toInt();
    final r = box.right.clamp(0, src.width.toDouble()).toInt();
    final b = box.bottom.clamp(0, src.height.toDouble()).toInt();
    if (r <= l || b <= t) return src;
    final cw = r - l, ch = b - t;

    switch (region.effect) {
      case BlurEffect.blackBar:
        img.fillRect(src, x1: l, y1: t, x2: r, y2: b,
            color: img.ColorRgb8(0, 0, 0));
        break;
      case BlurEffect.whiteBar:
        img.fillRect(src, x1: l, y1: t, x2: r, y2: b,
            color: img.ColorRgb8(255, 255, 255));
        break;
      case BlurEffect.redBar:
        img.fillRect(src, x1: l, y1: t, x2: r, y2: b,
            color: img.ColorRgb8(220, 30, 30));
        break;
      case BlurEffect.gaussian:
        final crop = img.copyCrop(src, x: l, y: t, width: cw, height: ch);
        img.compositeImage(src,
            img.gaussianBlur(crop, radius: region.blurIntensity.toInt().clamp(2, 30)),
            dstX: l, dstY: t);
        break;
      case BlurEffect.mosaic:
        final crop = img.copyCrop(src, x: l, y: t, width: cw, height: ch);
        img.compositeImage(src,
            img.pixelate(crop,
                size: region.blurIntensity.toInt().clamp(2, 80),
                mode: img.PixelateMode.upperLeft),
            dstX: l, dstY: t);
        break;
      case BlurEffect.heavyPixelate:
        final crop = img.copyCrop(src, x: l, y: t, width: cw, height: ch);
        img.compositeImage(src,
            img.pixelate(crop,
                size: region.blurIntensity.toInt().clamp(20, 100),
                mode: img.PixelateMode.upperLeft),
            dstX: l, dstY: t);
        break;
      case BlurEffect.frostedGlass:
        final crop = img.copyCrop(src, x: l, y: t, width: cw, height: ch);
        final blurred = img.gaussianBlur(crop,
            radius: region.blurIntensity.toInt().clamp(2, 15));
        img.compositeImage(src, blurred, dstX: l, dstY: t);
        for (int py = t; py < b; py++) {
          for (int px = l; px < r; px++) {
            final p = src.getPixel(px, py);
            src.setPixelRgb(px, py,
              (p.r * 0.55 + 230 * 0.45).round().clamp(0, 255),
              (p.g * 0.55 + 230 * 0.45).round().clamp(0, 255),
              (p.b * 0.55 + 230 * 0.45).round().clamp(0, 255),
            );
          }
        }
        break;
      case BlurEffect.grayscaleBlur:
        final crop = img.copyCrop(src, x: l, y: t, width: cw, height: ch);
        final gray = img.grayscale(crop);
        img.compositeImage(src,
            img.gaussianBlur(gray,
                radius: region.blurIntensity.toInt().clamp(2, 20)),
            dstX: l, dstY: t);
        break;
    }
    return src;
  }

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

  img.Image _processCrop(img.Image crop, BlurRegion region) {
    switch (region.effect) {
      case BlurEffect.blackBar:
        final r = img.Image(width: crop.width, height: crop.height);
        img.fill(r, color: img.ColorRgb8(0, 0, 0));
        return r;
      case BlurEffect.whiteBar:
        final r = img.Image(width: crop.width, height: crop.height);
        img.fill(r, color: img.ColorRgb8(255, 255, 255));
        return r;
      case BlurEffect.redBar:
        final r = img.Image(width: crop.width, height: crop.height);
        img.fill(r, color: img.ColorRgb8(220, 30, 30));
        return r;
      case BlurEffect.gaussian:
        return img.gaussianBlur(crop,
            radius: region.blurIntensity.toInt().clamp(2, 30));
      case BlurEffect.mosaic:
        return img.pixelate(crop,
            size: region.blurIntensity.toInt().clamp(2, 80),
            mode: img.PixelateMode.upperLeft);
      case BlurEffect.heavyPixelate:
        return img.pixelate(crop,
            size: region.blurIntensity.toInt().clamp(20, 100),
            mode: img.PixelateMode.upperLeft);
      case BlurEffect.frostedGlass:
        final blurred = img.gaussianBlur(crop,
            radius: region.blurIntensity.toInt().clamp(2, 15));
        for (final p in blurred) {
          blurred.setPixelRgb(p.x, p.y,
            (p.r * 0.55 + 230 * 0.45).round().clamp(0, 255),
            (p.g * 0.55 + 230 * 0.45).round().clamp(0, 255),
            (p.b * 0.55 + 230 * 0.45).round().clamp(0, 255),
          );
        }
        return blurred;
      case BlurEffect.grayscaleBlur:
        return img.gaussianBlur(img.grayscale(crop),
            radius: region.blurIntensity.toInt().clamp(2, 20));
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