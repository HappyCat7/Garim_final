import 'package:flutter/material.dart';
import 'detection_result.dart';

/// ─────────────────────────────────────────────────────────────────────
/// 편집 화면의 통합 블러 영역 모델.
/// YOLO 탐지 박스 · OCR 영역 · 수동 박스를 하나로 표현.
/// 각 박스마다 독립적인 ON/OFF · 잠금 · 효과 · 강도 · 회전각을 보유.
/// ─────────────────────────────────────────────────────────────────────
@immutable
class BlurRegion {
  final String id;
  final DetectionType type;

  /// 원본 이미지 픽셀 좌표 기준 AABB (회전 전 기준 Rect)
  final Rect boundingBox;

  /// 박스 중심 기준 회전각 (라디안, 시계방향 양수 — Flutter Transform.rotate 규격)
  final double angle;

  /// 개별 블러 ON/OFF (false = 블러 해제, 박스 윤곽만 표시)
  final bool isBlurred;

  /// 잠금 상태: true이면 탭으로 블러 토글 불가 (리사이즈·회전 조작은 가능)
  final bool isLocked;

  /// 이 박스에 개별 지정된 블러 효과
  final BlurEffect effect;

  /// 블러 강도 (gaussian/mosaic/frostedGlass 전용)
  final double blurIntensity;

  final double confidence;
  final List<String> privacyTexts;

  const BlurRegion({
    required this.id,
    required this.type,
    required this.boundingBox,
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
        angle: angle ?? this.angle,
        isBlurred: isBlurred ?? this.isBlurred,
        isLocked: isLocked ?? this.isLocked,
        effect: effect ?? this.effect,
        blurIntensity: blurIntensity ?? this.blurIntensity,
        confidence: confidence,
        privacyTexts: privacyTexts,
      );

  /// DetectionResult → BlurRegion 변환
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
        confidence: d.confidence,
        privacyTexts: d.privacyTexts,
        effect: defaultEffect,
        blurIntensity: defaultIntensity,
      );

  /// 수동 박스 생성
  factory BlurRegion.manual({required String id, required Rect rect}) =>
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
    privacyTexts.isNotEmpty ? const Color(0xFFFF6B6B) : const Color(0xFF43E97B),
    DetectionType.card => Colors.orange,
    DetectionType.shippingLabel => Colors.purple,
    DetectionType.manual => const Color(0xFF00BCD4),
  };

  String get label => switch (type) {
    DetectionType.face => '얼굴',
    DetectionType.licensePlate => '번호판',
    DetectionType.document => privacyTexts.isNotEmpty ? 'OCR' : '문서',
    DetectionType.card => '카드',
    DetectionType.shippingLabel => '운송장',
    DetectionType.manual => '수동',
  };
}