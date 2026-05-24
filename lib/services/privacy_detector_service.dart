import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/detection_result.dart';
import 'ocr_service.dart';
import 'privacy_detector.dart';

class PrivacyDetectorService {
  final OCRService _ocrService = OCRService();

  Future<List<DetectionResult>> detectWholeImage(File imageFile) async {
    try {
      final lines = await _ocrService.processImage(imageFile);
      return _convertItemsToDetectionResults(
        PrivacyDetector.detect(lines),
      );
    } catch (e) {
      debugPrint('전체 OCR 개인정보 탐지 오류: $e');
      return [];
    }
  }

  // 기존 DocumentTextScreen이 호출하던 함수도 유지한다.
  // 기존 프로젝트 구조 깨지지 않게 남겨둔 것.
  Future<List<DetectionResult>> detectFromRegion(
      File imageFile,
      Rect region,
      double imageWidth,
      double imageHeight,
      ) async {
    try {
      final lines = await _ocrService.processImage(imageFile);

      final filteredLines = lines.where((line) {
        final box = line.boundingBox;
        if (box == null) return false;
        return region.overlaps(box);
      }).toList();

      return _convertItemsToDetectionResults(
        PrivacyDetector.detect(filteredLines),
      );
    } catch (e) {
      debugPrint('영역 OCR 개인정보 탐지 오류: $e');
      return [];
    }
  }

  List<DetectionResult> _convertItemsToDetectionResults(
      List<dynamic> items,
      ) {
    return items.map((item) {
      final Rect rect = item.rect ?? _rectFromPolygon(item.polygon);

      return DetectionResult(
        type: DetectionType.document,
        boundingBox: rect,
        confidence: _confidenceToDouble(item.confidence),
        privacyTexts: [
          '${_convertType(item.type)}: ${item.text}',
        ],
        polygon: item.polygon,
      );
    }).where((result) {
      return result.boundingBox.width > 1 &&
          result.boundingBox.height > 1;
    }).toList();
  }

  Rect _rectFromPolygon(List<Offset>? polygon) {
    if (polygon == null || polygon.isEmpty) {
      return Rect.zero;
    }

    double left = polygon.first.dx;
    double top = polygon.first.dy;
    double right = polygon.first.dx;
    double bottom = polygon.first.dy;

    for (final point in polygon) {
      if (point.dx < left) left = point.dx;
      if (point.dy < top) top = point.dy;
      if (point.dx > right) right = point.dx;
      if (point.dy > bottom) bottom = point.dy;
    }

    return Rect.fromLTRB(left, top, right, bottom);
  }

  double _confidenceToDouble(String confidence) {
    switch (confidence) {
      case 'HIGH':
        return 0.99;
      case 'MEDIUM':
        return 0.85;
      case 'LOW':
        return 0.65;
      default:
        return 0.8;
    }
  }

  String _convertType(String type) {
    switch (type) {
      case 'RRN':
        return '주민번호';
      case 'PARTIAL_RRN':
        return '주민번호 일부';
      case 'PHONE':
        return '전화번호';
      case 'EMAIL':
        return '이메일';
      case 'CARD_NUMBER':
        return '카드번호';
      case 'ACCOUNT_NUMBER':
        return '계좌번호';
      case 'PASSPORT_NUMBER':
        return '여권번호';
      case 'DRIVER_LICENSE':
        return '면허번호';
      case 'BIRTH_DATE':
        return '생년월일';
      case 'ADDRESS':
        return '주소';
      case 'NAME':
        return '이름';
      case 'WAYBILL_NAME':
        return '운송장 이름';
      case 'WAYBILL_CODE':
        return '운송장 코드';
      case 'WAYBILL_ORDER_NUMBER':
        return '주문번호';
      case 'COMPANY':
        return '회사명';
      case 'DEPARTMENT':
        return '소속';
      case 'POSITION':
        return '직책';
      default:
        return type;
    }
  }

  void close() {
    _ocrService.close();
  }
}