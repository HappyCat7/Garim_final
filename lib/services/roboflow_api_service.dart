import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class CardDetection {
  final Rect rect;
  final double confidence;
  final String label;
  final Map<String, dynamic> raw;

  CardDetection({
    required this.rect,
    required this.confidence,
    required this.label,
    required this.raw,
  });
}

class RoboflowApiService {
  final String apiKey;
  final String workspaceName;
  final String workflowId;
  final String targetClass;

  RoboflowApiService({
    required this.apiKey,
    required this.workspaceName,
    required this.workflowId,
    this.targetClass = 'card',
  });

  Future<List<CardDetection>> detectCards(File imageFile) async {
    final bytes = await imageFile.readAsBytes();

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('이미지를 디코딩할 수 없습니다.');
    }

    final imageWidth = decoded.width.toDouble();
    final imageHeight = decoded.height.toDouble();

    final base64Image = base64Encode(bytes);

    /*
      중요:
      예전 코드:
      https://serverless.roboflow.com/{workspace}/workflows/{workflow}

      수정 코드:
      https://detect.roboflow.com/infer/workflows/{workspace}/{workflow}

      Roboflow HTTP Workflow 공식 예시 기준 형식이다.
    */
    final endpoint = Uri.parse(
      'https://detect.roboflow.com/infer/workflows/$workspaceName/$workflowId',
    );

    final headers = {
      'Content-Type': 'application/json',
    };

    /*
      중요:
      Python SDK의 parameters={"classes": "card"}는
      Flutter HTTP에서는 inputs 안의 classes로 넣어야 한다.

      즉:
      inputs.image
      inputs.classes
    */
    final body = {
      'api_key': apiKey,
      'inputs': {
        'image': {
          'type': 'base64',
          'value': base64Image,
        },
        'classes': targetClass,
      },
    };

    final response = await http
        .post(
      endpoint,
      headers: headers,
      body: jsonEncode(body),
    )
        .timeout(const Duration(seconds: 30));

    debugPrint('Roboflow 응답 코드: ${response.statusCode}');
    debugPrint('Roboflow 응답 내용: ${response.body}');

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final responseText = _safeDecodeBody(response);

      throw Exception(
        'Roboflow API 오류\n'
            'status=${response.statusCode}\n'
            '${_shorten(responseText)}',
      );
    }

    final resultText = utf8.decode(response.bodyBytes);
    final dynamic resultJson = jsonDecode(resultText);

    final predictions = _findPredictions(resultJson);

    final detections = <CardDetection>[];

    for (final pred in predictions) {
      final label = _getLabel(pred);
      final confidence = _getConfidence(pred);

      final rect = _getRectFromPrediction(
        pred,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );

      if (rect == null) continue;

      final safeRect = Rect.fromLTRB(
        rect.left.clamp(0.0, imageWidth - 1).toDouble(),
        rect.top.clamp(0.0, imageHeight - 1).toDouble(),
        rect.right.clamp(0.0, imageWidth - 1).toDouble(),
        rect.bottom.clamp(0.0, imageHeight - 1).toDouble(),
      );

      if (safeRect.width <= 1 || safeRect.height <= 1) continue;

      detections.add(
        CardDetection(
          rect: safeRect,
          confidence: confidence,
          label: label,
          raw: pred,
        ),
      );
    }

    detections.sort((a, b) => b.confidence.compareTo(a.confidence));

    return detections;
  }

  List<Map<String, dynamic>> _findPredictions(dynamic obj) {
    final found = <Map<String, dynamic>>[];

    void visit(dynamic value) {
      if (value is Map) {
        final map = value.cast<String, dynamic>();

        if (map['predictions'] is List) {
          for (final item in map['predictions']) {
            if (item is Map) {
              found.add(item.cast<String, dynamic>());
            }
          }
        }

        for (final child in map.values) {
          visit(child);
        }
      } else if (value is List) {
        for (final item in value) {
          visit(item);
        }
      }
    }

    visit(obj);

    return found;
  }

  String _getLabel(Map<String, dynamic> pred) {
    final value = pred['class'] ??
        pred['label'] ??
        pred['class_name'] ??
        pred['name'] ??
        targetClass;

    return value.toString();
  }

  double _getConfidence(Map<String, dynamic> pred) {
    final value = pred['confidence'] ??
        pred['score'] ??
        pred['class_confidence'] ??
        1.0;

    if (value is num) return value.toDouble();

    return double.tryParse(value.toString()) ?? 0.0;
  }

  Rect? _getRectFromPrediction(
      Map<String, dynamic> pred, {
        required double imageWidth,
        required double imageHeight,
      }) {
    if (_hasKeys(pred, ['x', 'y', 'width', 'height'])) {
      return _xywhToRect(
        x: _toDouble(pred['x']),
        y: _toDouble(pred['y']),
        w: _toDouble(pred['width']),
        h: _toDouble(pred['height']),
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );
    }

    for (final key in ['bbox', 'bounding_box', 'box']) {
      final box = pred[key];

      if (box is Map) {
        final map = box.cast<String, dynamic>();

        if (_hasKeys(map, ['x', 'y', 'width', 'height'])) {
          return _xywhToRect(
            x: _toDouble(map['x']),
            y: _toDouble(map['y']),
            w: _toDouble(map['width']),
            h: _toDouble(map['height']),
            imageWidth: imageWidth,
            imageHeight: imageHeight,
          );
        }

        if (_hasKeys(map, ['x1', 'y1', 'x2', 'y2'])) {
          return _x1y1x2y2ToRect(
            x1: _toDouble(map['x1']),
            y1: _toDouble(map['y1']),
            x2: _toDouble(map['x2']),
            y2: _toDouble(map['y2']),
            imageWidth: imageWidth,
            imageHeight: imageHeight,
          );
        }
      }
    }

    if (_hasKeys(pred, ['x1', 'y1', 'x2', 'y2'])) {
      return _x1y1x2y2ToRect(
        x1: _toDouble(pred['x1']),
        y1: _toDouble(pred['y1']),
        x2: _toDouble(pred['x2']),
        y2: _toDouble(pred['y2']),
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );
    }

    if (pred['points'] is List) {
      return _pointsToRect(
        pred['points'] as List,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );
    }

    if (pred['polygon'] is List) {
      return _pointsToRect(
        pred['polygon'] as List,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );
    }

    return null;
  }

  Rect _xywhToRect({
    required double x,
    required double y,
    required double w,
    required double h,
    required double imageWidth,
    required double imageHeight,
  }) {
    /*
      Roboflow 일반 object detection:
      x, y = 중심 좌표
      width, height = 박스 크기
    */
    if ([x, y, w, h].every((v) => v >= 0 && v <= 1)) {
      x *= imageWidth;
      w *= imageWidth;
      y *= imageHeight;
      h *= imageHeight;
    }

    return Rect.fromLTRB(
      x - w / 2,
      y - h / 2,
      x + w / 2,
      y + h / 2,
    );
  }

  Rect _x1y1x2y2ToRect({
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    required double imageWidth,
    required double imageHeight,
  }) {
    if ([x1, y1, x2, y2].every((v) => v >= 0 && v <= 1)) {
      x1 *= imageWidth;
      x2 *= imageWidth;
      y1 *= imageHeight;
      y2 *= imageHeight;
    }

    return Rect.fromLTRB(x1, y1, x2, y2);
  }

  Rect? _pointsToRect(
      List points, {
        required double imageWidth,
        required double imageHeight,
      }) {
    final xs = <double>[];
    final ys = <double>[];

    for (final p in points) {
      if (p is Map && p.containsKey('x') && p.containsKey('y')) {
        xs.add(_toDouble(p['x']));
        ys.add(_toDouble(p['y']));
      }
    }

    if (xs.isEmpty || ys.isEmpty) return null;

    var minX = xs.reduce((a, b) => a < b ? a : b);
    var maxX = xs.reduce((a, b) => a > b ? a : b);
    var minY = ys.reduce((a, b) => a < b ? a : b);
    var maxY = ys.reduce((a, b) => a > b ? a : b);

    if ([minX, maxX, minY, maxY].every((v) => v >= 0 && v <= 1)) {
      minX *= imageWidth;
      maxX *= imageWidth;
      minY *= imageHeight;
      maxY *= imageHeight;
    }

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  bool _hasKeys(Map<String, dynamic> map, List<String> keys) {
    return keys.every(map.containsKey);
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  String _safeDecodeBody(http.Response response) {
    try {
      return utf8.decode(response.bodyBytes);
    } catch (_) {
      return response.body;
    }
  }

  String _shorten(String text) {
    final cleaned = text.replaceAll(apiKey, 'API_KEY_HIDDEN');

    if (cleaned.length <= 350) return cleaned;

    return '${cleaned.substring(0, 350)}...';
  }
}