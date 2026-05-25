import 'dart:io';

import 'package:flutter/material.dart';

import '../models/detection_result.dart';
import 'ocr_service.dart';
import 'privacy_detector.dart';

class PrivacyDetectorService {
  final OCRService _ocrService = OCRService();

  Future<List<DetectionResult>> detectWholeImage(File imageFile) async {
    try {
      final lines = await _ocrService.processImage(imageFile);

      _printOcrDebugLog(
        lines,
        title: '전체 이미지 OCR',
      );

      final items = PrivacyDetector.detect(lines);

      _printDetectedDebugLog(
        items,
        title: '전체 이미지 개인정보 탐지 결과',
      );

      return _convertItemsToDetectionResults(items);
    } catch (e) {
      debugPrint('전체 OCR 개인정보 탐지 오류: $e');
      return [];
    }
  }

  Future<List<DetectionResult>> detectFromRegion(
      File imageFile,
      Rect region,
      double imageWidth,
      double imageHeight,
      ) async {
    try {
      final lines = await _ocrService.processImage(imageFile);

      _printOcrDebugLog(
        lines,
        title: '원본 전체 OCR',
      );

      final filteredLines = lines.where((line) {
        final box = line.boundingBox;
        return region.overlaps(box);
      }).toList();

      _printOcrDebugLog(
        filteredLines,
        title: '영역 필터링 OCR',
      );

      final items = PrivacyDetector.detect(filteredLines);

      _printDetectedDebugLog(
        items,
        title: '영역 개인정보 탐지 결과',
      );

      return _convertItemsToDetectionResults(items);
    } catch (e) {
      debugPrint('영역 OCR 개인정보 탐지 오류: $e');
      return [];
    }
  }

  void _printOcrDebugLog(
      List<dynamic> lines, {
        required String title,
      }) {
    debugPrint('');
    debugPrint('========== $title ==========');
    debugPrint('OCR LINE COUNT: ${lines.length}');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      debugPrint('----- OCR LINE #$i -----');
      debugPrint('TEXT: ${line.text}');
      debugPrint('BOX : ${line.boundingBox}');

      try {
        debugPrint('ELEMENT COUNT: ${line.elements.length}');

        for (int j = 0; j < line.elements.length; j++) {
          final element = line.elements[j];

          debugPrint(
            '  ELEMENT #$j | text="${element.text}" | box=${element.boundingBox} | points=${element.cornerPoints}',
          );
        }
      } catch (e) {
        debugPrint('ELEMENT LOG ERROR: $e');
      }
    }

    debugPrint('========== END $title ==========');
    debugPrint('');
  }

  void _printDetectedDebugLog(
      List<dynamic> items, {
        required String title,
      }) {
    debugPrint('');
    debugPrint('========== $title ==========');
    debugPrint('DETECTED COUNT: ${items.length}');

    for (int i = 0; i < items.length; i++) {
      final item = items[i];

      debugPrint('----- DETECTED ITEM #$i -----');
      debugPrint('TYPE: ${item.type}');
      debugPrint('TEXT: ${item.text}');
      debugPrint('CONFIDENCE: ${item.confidence}');
      debugPrint('RECT: ${item.rect}');
      debugPrint('POLYGON: ${item.polygon}');
    }

    debugPrint('========== END $title ==========');
    debugPrint('');
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
      return result.boundingBox.width > 1 && result.boundingBox.height > 1;
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
      case 'REGISTER_NUMBER':
      case 'WAYBILL_TRACKING_NUMBER':
      case 'TRACKING_NUMBER':
        return '등기번호';
      case 'ORDER_NUMBER':
      case 'WAYBILL_ORDER_NUMBER':
        return '주문번호';
      case 'PASSPORT_NUMBER':
      case 'PASSPORT_NO':
        return '여권번호';
      case 'PASSPORT_NAME':
      case 'PASSPORT_ENGLISH_NAME':
        return '여권 이름';
      case 'PASSPORT_MRZ':
      case 'PASSPORT_MRZ_CODE':
      case 'PASSPORT_MRZ_LINE':
      case 'PASSPORT_MRZ_TEXT':
      case 'PASSPORT_MACHINE_READABLE_ZONE':
      case 'PASSPORT_MACHINE_READABLE_CODE':
      case 'PASSPORT_MACHINE_READABLE_LINE':
      case 'PASSPORT_CODE':
      case 'PASSPORT_LINE':
        return '여권 하단 코드';
      case 'PASSPORT_PERSONAL_NUMBER':
      case 'PASSPORT_ID_NUMBER':
        return '주민번호 뒷자리';
      case 'PASSPORT_NATIONALITY':
      case 'PASSPORT_COUNTRY':
        return '국적';
      case 'PASSPORT_ISSUE_DATE':
      case 'PASSPORT_ISSUED_DATE':
        return '여권 발급일';
      case 'PASSPORT_EXPIRY_DATE':
      case 'PASSPORT_EXPIRATION_DATE':
        return '여권 만료일';
      case 'PASSPORT_DATE':
        return '여권 날짜';
      case 'PASSPORT_TYPE':
        return '여권종류';
      case 'PASSPORT_NATIONAL_CODE':
        return '국가코드';
      case 'PASSPORT_AUTHORITY':
        return '발급기관';
      case 'PASSPORT_SEX':
        return '성별';
      case 'PASSPORT_KOREAN_NAME':
        return '이름';
      case 'PASSPORT_BIRTH_DATE':
        return '생년월일';
      case 'PASSPORT_INFO':
      case 'PASSPORT_PERSONAL_INFO':
      case 'PASSPORT_FIELD':
      case 'PASSPORT_VALUE':
      case 'PASSPORT_DATA':
      case 'PASSPORT':
        return '여권 정보';
      default:
        return type;
    }
  }

  void close() {
    _ocrService.close();
  }
}
