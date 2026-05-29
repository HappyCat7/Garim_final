import 'package:flutter/material.dart';

// [요구사항 2 반영] 블러 텍스처 4종으로 통폐합 및 리뉴얼
enum BlurEffect {
  gaussian,      // 1. 기존 흐림 (Standard Gaussian Blur)
  frostedGlass,  // 2. 유리 질감 (Frosted Glass - 약간의 밝기 증가 + 블러)
  pixelate,      // 3. 픽셀 블러 (Pixelate - 부드러운 기본 픽셀화)
  fog,           // 4. 뿌연 안개 (Fog/Mist - 뽀얀 느낌의 블러 처리)
}

enum DetectionType {
  face, licensePlate, document, card, shippingLabel, manual,
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
        ? const Color(0xFFFF6B6B) : const Color(0xFF43E97B),
    DetectionType.card          => Colors.orange,
    DetectionType.shippingLabel => Colors.purple,
    DetectionType.manual        => const Color(0xFF00BCD4),
  };
}