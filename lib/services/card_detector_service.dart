import 'dart:io';
import 'package:flutter/material.dart';
import '../models/detection_result.dart';
import 'roboflow_api_service.dart';

class CardDetectorService {
  final _roboflowService = RoboflowApiService(
    apiKey: 'KXeK4MBqa7qQrkG76J7C',
    workspaceName: '-0qria',
    workflowId: 'general-segmentation-api-2',
    targetClass: 'card',
  );

  Future<List<DetectionResult>> detect(File imageFile) async {
    try {
      debugPrint('Roboflow API 호출 시작');
      final cardDetections = await _roboflowService.detectCards(imageFile);
      debugPrint('Roboflow 탐지 결과: ${cardDetections.length}개');

      return cardDetections.map((detection) {
        return DetectionResult(
          type: DetectionType.card,
          boundingBox: detection.rect,
          confidence: detection.confidence,
        );
      }).toList();
    } catch (e) {
      debugPrint('카드 탐지 오류: $e');
      return [];
    }
  }

  void close() {
    // API 방식이라 닫을 리소스 없음
  }
}