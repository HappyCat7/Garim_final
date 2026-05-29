import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'detection_result.dart';

@immutable
class BlurRegion {
  final String id;
  final DetectionType type;
  final Rect boundingBox;
  final double angle;
  final bool isBlurred;
  final BlurEffect effect;
  final double blurIntensity;
  final double confidence;
  final List<String> privacyTexts;

  const BlurRegion({
    required this.id,
    required this.type,
    required this.boundingBox,
    this.angle = 0.0,
    this.isBlurred = true,
    this.effect = BlurEffect.gaussian,
    this.blurIntensity = 20.0,
    this.confidence = 1.0,
    this.privacyTexts = const [],
  });

  BlurRegion copyWith({
    Rect? boundingBox,
    double? angle,
    bool? isBlurred,
    BlurEffect? effect,
    double? blurIntensity,
  }) =>
      BlurRegion(
        id: id, type: type,
        boundingBox: boundingBox ?? this.boundingBox,
        angle: angle ?? this.angle,
        isBlurred: isBlurred ?? this.isBlurred,
        effect: effect ?? this.effect,
        blurIntensity: blurIntensity ?? this.blurIntensity,
        confidence: confidence,
        privacyTexts: privacyTexts,
      );

  // 💡 핵심 수정: polygon이 있으면 타이트한 크기와 기울기를 정확히 계산!
  factory BlurRegion.fromDetection(DetectionResult d, {
    required String id,
    BlurEffect defaultEffect = BlurEffect.gaussian,
    double defaultIntensity = 20.0,
  }) {
    Rect box = d.boundingBox;
    double angle = 0.0;

    if (d.polygon != null && d.polygon!.length == 4) {
      final tl = d.polygon![0];
      final tr = d.polygon![1];
      final br = d.polygon![2];
      final bl = d.polygon![3];

      // 각도 및 타이트한 width, height 계산
      angle = math.atan2(tr.dy - tl.dy, tr.dx - tl.dx);
      final width = math.sqrt(math.pow(tr.dx - tl.dx, 2) + math.pow(tr.dy - tl.dy, 2));
      final height = math.sqrt(math.pow(bl.dx - tl.dx, 2) + math.pow(bl.dy - tl.dy, 2));
      final center = Offset(
        (tl.dx + tr.dx + br.dx + bl.dx) / 4,
        (tl.dy + tr.dy + br.dy + bl.dy) / 4,
      );
      box = Rect.fromCenter(center: center, width: width, height: height);
    }

    return BlurRegion(
      id: id, type: d.type, boundingBox: box, angle: angle,
      confidence: d.confidence, privacyTexts: d.privacyTexts,
      effect: defaultEffect, blurIntensity: defaultIntensity,
    );
  }

  factory BlurRegion.manual({required String id, required Rect rect}) =>
      BlurRegion(id: id, type: DetectionType.manual, boundingBox: rect);

  bool get isManual => type == DetectionType.manual;

  Color get color => switch (type) {
    DetectionType.face          => const Color(0xFFFF6B6B),
    DetectionType.licensePlate  => const Color(0xFF6C63FF),
    DetectionType.document      => privacyTexts.isNotEmpty
        ? const Color(0xFFFF6B6B) : const Color(0xFF43E97B),
    DetectionType.card          => Colors.orange,
    DetectionType.shippingLabel => Colors.purple,
    DetectionType.manual        => const Color(0xFF00BCD4),
  };

  String get label => switch (type) {
    DetectionType.face          => '얼굴',
    DetectionType.licensePlate  => '번호판',
    DetectionType.document      => privacyTexts.isNotEmpty ? 'OCR' : '문서',
    DetectionType.card          => '카드',
    DetectionType.shippingLabel => '운송장',
    DetectionType.manual        => '수동',
  };
}