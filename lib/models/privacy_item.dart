import 'dart:ui';

class PrivacyItem {
  final String type;
  final String text;
  final Rect? rect;
  final String confidence;
  final List<Offset>? polygon;

  PrivacyItem({
    required this.type,
    required this.text,
    required this.rect,
    required this.confidence,
    this.polygon,
  });
}