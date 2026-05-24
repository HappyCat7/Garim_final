import 'package:flutter/material.dart';

enum BlurEffect {
  gaussian,
  mosaic,
  blackBar,
  frostedGlass,
}

enum DetectionType {
  face,
  licensePlate,
  document,
  card,
  shippingLabel,
  manual,
}

class DetectionResult {
  final DetectionType type;
  final Rect boundingBox;
  final double confidence;
  final List<String> privacyTexts;
  final List<Offset>? polygon;

  const DetectionResult({
    required this.type,
    required this.boundingBox,
    this.confidence = 1.0,
    this.privacyTexts = const [],
    this.polygon,
  });

  DetectionResult withRect(Rect rect) => DetectionResult(
    type: type,
    boundingBox: rect,
    confidence: confidence,
    privacyTexts: privacyTexts,
    polygon: polygon,
  );

  String get typeLabel {
    switch (type) {
      case DetectionType.face:          return '얼굴';
      case DetectionType.licensePlate:  return '번호판';
      case DetectionType.document:      return privacyTexts.isNotEmpty ? 'OCR' : '문서';
      case DetectionType.card:          return '카드';
      case DetectionType.shippingLabel: return '운송장';
      case DetectionType.manual:        return '수동';
    }
  }

  Color get typeColor {
    switch (type) {
      case DetectionType.face:          return const Color(0xFFFF6B6B);
      case DetectionType.licensePlate:  return const Color(0xFF6C63FF);
      case DetectionType.document:      return privacyTexts.isNotEmpty ? const Color(0xFFFF6B6B) : const Color(0xFF43E97B);
      case DetectionType.card:          return Colors.orange;
      case DetectionType.shippingLabel: return Colors.purple;
      case DetectionType.manual:        return const Color(0xFF00BCD4);
    }
  }
}