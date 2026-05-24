import 'package:flutter/material.dart';

/// 사용자가 직접 드래그해서 그린 블러 박스 모델.
/// [rect]는 항상 원본 이미지 픽셀 좌표 기준입니다.
class ManualBlurBox {
  final String id;
  final Rect rect;
  final bool enabled;

  const ManualBlurBox({
    required this.id,
    required this.rect,
    this.enabled = true,
  });

  ManualBlurBox copyWith({Rect? rect, bool? enabled}) => ManualBlurBox(
    id: id,
    rect: rect ?? this.rect,
    enabled: enabled ?? this.enabled,
  );
}