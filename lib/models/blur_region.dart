import 'package:flutter/material.dart';
import 'detection_result.dart';

@immutable
class BlurRegion {
  final String id;
  final DetectionType type;

  final Rect boundingBox;

  // 추가
  final List<Offset>? polygon;

  final double angle;
  final bool isBlurred;
  final bool isLocked;
  final BlurEffect effect;
  final double blurIntensity;

  final double confidence;
  final List<String> privacyTexts;

  const BlurRegion({
    required this.id,
    required this.type,
    required this.boundingBox,
    this.polygon,
    this.angle = 0.0,
    this.isBlurred = true,
    this.isLocked = false,
    this.effect = BlurEffect.mosaic,
    this.blurIntensity = 20.0,
    this.confidence = 1.0,
    this.privacyTexts = const [],
  });

  BlurRegion copyWith({
    Rect? boundingBox,
    List<Offset>? polygon,
    double? angle,
    bool? isBlurred,
    bool? isLocked,
    BlurEffect? effect,
    double? blurIntensity,
  }) =>
      BlurRegion(
        id: id,
        type: type,
        boundingBox: boundingBox ?? this.boundingBox,
        polygon: polygon ?? this.polygon,
        angle: angle ?? this.angle,
        isBlurred: isBlurred ?? this.isBlurred,
        isLocked: isLocked ?? this.isLocked,
        effect: effect ?? this.effect,
        blurIntensity: blurIntensity ?? this.blurIntensity,
        confidence: confidence,
        privacyTexts: privacyTexts,
      );

  factory BlurRegion.fromDetection(
      DetectionResult d, {
        required String id,
        BlurEffect defaultEffect = BlurEffect.mosaic,
        double defaultIntensity = 20.0,
      }) =>
      BlurRegion(
        id: id,
        type: d.type,
        boundingBox: d.boundingBox,
        polygon: d.polygon,
        confidence: d.confidence,
        privacyTexts: d.privacyTexts,
        effect: defaultEffect,
        blurIntensity: defaultIntensity,
      );

  factory BlurRegion.manual({
    required String id,
    required Rect rect,
  }) =>
      BlurRegion(
        id: id,
        type: DetectionType.manual,
        boundingBox: rect,
        effect: BlurEffect.mosaic,
        blurIntensity: 20.0,
      );

  bool get isManual => type == DetectionType.manual;

  Color get color => switch (type) {
    DetectionType.face => const Color(0xFFFF6B6B),
    DetectionType.licensePlate => const Color(0xFF6C63FF),
    DetectionType.document =>
    privacyTexts.isNotEmpty
        ? const Color(0xFFFF6B6B)
        : const Color(0xFF43E97B),
    DetectionType.card => Colors.orange,
    DetectionType.shippingLabel => Colors.purple,
    DetectionType.manual => const Color(0xFF00BCD4),
  };

  String get label {
    if (privacyTexts.isNotEmpty) {
      final text = privacyTexts.first;

      if (text.contains('이름')) return '이름';
      if (text.contains('전화')) return '전화';
      if (text.contains('주소')) return '주소';
      if (text.contains('이메일')) return '메일';
      if (text.contains('계좌')) return '계좌';
      if (text.contains('카드')) return '카드';
    }

    return switch (type) {
      DetectionType.face => '얼굴',
      DetectionType.licensePlate => '번호판',
      DetectionType.document => 'OCR',
      DetectionType.card => '카드',
      DetectionType.shippingLabel => '운송장',
      DetectionType.manual => '수동',
    };
  }
}