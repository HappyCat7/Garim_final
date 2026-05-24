import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../models/detection_result.dart';

class BlurService {
  Future<Uint8List> applyBlur(
      File imageFile,
      List<DetectionResult> detections,
      double imageWidth,
      double imageHeight, {
        BlurEffect effect = BlurEffect.mosaic,
        double blurIntensity = 20.0,
      }) async {
    final imageBytes = await imageFile.readAsBytes();
    img.Image originalImage = img.decodeImage(imageBytes)!;
    img.Image result = originalImage.clone();

    for (final detection in detections) {
      final box = detection.boundingBox;

      final left   = box.left.clamp(0, originalImage.width - 1).toInt();
      final top    = box.top.clamp(0, originalImage.height - 1).toInt();
      final right  = box.right.clamp(0, originalImage.width.toDouble()).toInt();
      final bottom = box.bottom.clamp(0, originalImage.height.toDouble()).toInt();

      if (right <= left || bottom <= top) continue;

      final cropWidth  = right - left;
      final cropHeight = bottom - top;

      switch (effect) {
        case BlurEffect.blackBar:
          img.fillRect(
            result,
            x1: left, y1: top, x2: right, y2: bottom,
            color: img.ColorRgb8(0, 0, 0),
          );
          break;

        case BlurEffect.frostedGlass:
          final crop = img.copyCrop(result, x: left, y: top,
              width: cropWidth, height: cropHeight);
          final blurred = img.gaussianBlur(crop,
              radius: blurIntensity.toInt().clamp(2, 15));
          img.compositeImage(result, blurred, dstX: left, dstY: top);

          for (int y = top; y < bottom && y < result.height; y++) {
            for (int x = left; x < right && x < result.width; x++) {
              final p = result.getPixel(x, y);
              result.setPixelRgb(
                x, y,
                (p.r * 0.55 + 230 * 0.45).round().clamp(0, 255),
                (p.g * 0.55 + 230 * 0.45).round().clamp(0, 255),
                (p.b * 0.55 + 230 * 0.45).round().clamp(0, 255),
              );
            }
          }
          break;

        case BlurEffect.gaussian:
        case BlurEffect.mosaic:
          final croppedArea = img.copyCrop(result,
              x: left, y: top, width: cropWidth, height: cropHeight);

          img.Image effectArea;
          if (effect == BlurEffect.gaussian) {
            effectArea = img.gaussianBlur(croppedArea,
                radius: blurIntensity.toInt());
          } else {
            effectArea = img.pixelate(croppedArea,
                size: blurIntensity.toInt(),
                mode: img.PixelateMode.upperLeft);
          }

          final centerX = cropWidth / 2;
          final centerY = cropHeight / 2;
          final radiusX = cropWidth / 2;
          final radiusY = cropHeight / 2;

          for (final p in effectArea) {
            final dx = p.x - centerX;
            final dy = p.y - centerY;
            final insideOval =
                (dx * dx) / (radiusX * radiusX) +
                    (dy * dy) / (radiusY * radiusY) <= 1.0;
            if (insideOval) {
              result.setPixel(left + p.x, top + p.y, p);
            }
          }
          break;
      }
    }

    return Uint8List.fromList(img.encodeJpg(result, quality: 90));
  }
}