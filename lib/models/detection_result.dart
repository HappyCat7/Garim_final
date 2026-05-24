import 'package:flutter/material.dart';

// [Req 4] 8종 블러 효과
enum BlurEffect {
  gaussian,       // 가우시안 흐림
  mosaic,         // 모자이크
  blackBar,       // 검정 줄
  frostedGlass,   // 반투명 유리
  whiteBar,       // 흰색 줄
  redBar,         // 빨간색 줄 (Redaction)
  heavyPixelate,  // 아주 굵은 픽셀 모자이크
  grayscaleBlur,  // 흑백 흐림
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

  String get typeLabel => switch (type) {
    DetectionType.face          => '얼굴',
    DetectionType.licensePlate  => '번호판',
    DetectionType.document      => privacyTexts.isNotEmpty ? 'OCR' : '문서',
    DetectionType.card          => '카드',
    DetectionType.shippingLabel => '운송장',
    DetectionType.manual        => '수동',
  };

  Color get typeColor => switch (type) {
    DetectionType.face          => const Color(0xFFFF6B6B),
    DetectionType.licensePlate  => const Color(0xFF6C63FF),
    DetectionType.document      => privacyTexts.isNotEmpty
        ? const Color(0xFFFF6B6B)
        : const Color(0xFF43E97B),
    DetectionType.card          => Colors.orange,
    DetectionType.shippingLabel => Colors.purple,
    DetectionType.manual        => const Color(0xFF00BCD4),
  };
}