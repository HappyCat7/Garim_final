import 'dart:io';
import 'package:flutter/material.dart';
import '../models/detection_result.dart';
import 'roboflow_api_service.dart';

class ShippingLabelDetectorService {
  final _roboflowService = RoboflowApiService(
    apiKey: 'KXeK4MBqa7qQrkG76J7C',
    workspaceName: '-0qria',
    workflowId: 'general-segmentation-api-16',
    targetClass: 'shipping-label',
  );

  Future<List<DetectionResult>> detect(File imageFile) async {
    try {
      final detections = await _roboflowService.detectCards(imageFile);
      return detections.map((d) => DetectionResult(
        type: DetectionType.shippingLabel,
        boundingBox: d.rect,
        confidence: d.confidence,
      )).toList();
    } catch (e) {
      debugPrint('운송장 탐지 오류: $e');
      return [];
    }
  }

  void close() {}
}