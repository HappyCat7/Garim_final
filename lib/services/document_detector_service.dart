import 'dart:io';
import 'package:flutter/material.dart';
import '../models/detection_result.dart';
import 'roboflow_api_service.dart';

class DocumentDetectorService {
  final _roboflowService = RoboflowApiService(
    apiKey: 'KXeK4MBqa7qQrkG76J7C',
    workspaceName: '-0qria',
    workflowId: 'general-segmentation-api-15',  // ← 확인 필요
    targetClass: 'document',
  );

  Future<List<DetectionResult>> detect(File imageFile) async {
    try {
      final detections = await _roboflowService.detectCards(imageFile);

      return detections.map((detection) {
        return DetectionResult(
          type: DetectionType.document,
          boundingBox: detection.rect,
          confidence: detection.confidence,
        );
      }).toList();
    } catch (e) {
      debugPrint('문서 탐지 오류: $e');
      return [];
    }
  }

  void close() {}
}