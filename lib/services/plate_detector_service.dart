import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../models/detection_result.dart';

class PlateDetectorService {
  Interpreter? _interpreter;
  static const int inputSize = 640;
  static const double confidenceThreshold = 0.5;
  static const double iouThreshold = 0.45;

  Future<void> loadModel() async {
    final options = InterpreterOptions()..threads = 4;
    _interpreter = await Interpreter.fromAsset(
      'assets/models/yolo_plate.tflite',
      options: options,
    );
    debugPrint('YOLO loaded: assets/models/yolo_plate.tflite');
    debugPrint('input shape: ${_interpreter!.getInputTensor(0).shape}');
    debugPrint('output shape: ${_interpreter!.getOutputTensor(0).shape}');
  }

  Future<List<DetectionResult>> detect(File imageFile) async {
    if (_interpreter == null) await loadModel();

    final imageBytes = await imageFile.readAsBytes();
    final originalImage = img.decodeImage(imageBytes)!;
    final originalWidth = originalImage.width.toDouble();
    final originalHeight = originalImage.height.toDouble();

    final resized = img.copyResize(originalImage,
        width: inputSize, height: inputSize);
    final input = _imageToFloat32(resized);

    final output = List.generate(
        1, (_) => List.generate(5, (_) => List.filled(8400, 0.0)));

    _interpreter!.run(input, output);

    return _parseOutput(output[0], originalWidth, originalHeight);
  }

  List<List<List<List<double>>>> _imageToFloat32(img.Image image) {
    final input = List.generate(
        1,
            (_) => List.generate(
            inputSize,
                (y) => List.generate(inputSize, (x) {
              final pixel = image.getPixel(x, y);
              return [
                pixel.r / 255.0,
                pixel.g / 255.0,
                pixel.b / 255.0,
              ];
            })));
    return input;
  }

  List<DetectionResult> _parseOutput(
      List<List<double>> output,
      double origWidth,
      double origHeight,
      ) {
    final results = <DetectionResult>[];
    final numDetections = output[0].length;

    for (int i = 0; i < numDetections; i++) {
      final cx = output[0][i];
      final cy = output[1][i];
      final w = output[2][i];
      final h = output[3][i];
      final confidence = output[4][i];

      if (confidence < confidenceThreshold) continue;

      final left = (cx - w / 2) * origWidth;
      final top = (cy - h / 2) * origHeight;
      final right = (cx + w / 2) * origWidth;
      final bottom = (cy + h / 2) * origHeight;

      results.add(DetectionResult(
        type: DetectionType.licensePlate,
        boundingBox: Rect.fromLTRB(left, top, right, bottom),
        confidence: confidence,
      ));
    }

    return _applyNMS(results);
  }

  List<DetectionResult> _applyNMS(List<DetectionResult> detections) {
    if (detections.isEmpty) return [];

    detections.sort((a, b) => b.confidence.compareTo(a.confidence));
    final selected = <DetectionResult>[];

    for (final detection in detections) {
      bool keep = true;
      for (final selectedDet in selected) {
        if (_iou(detection.boundingBox, selectedDet.boundingBox) >
            iouThreshold) {
          keep = false;
          break;
        }
      }
      if (keep) selected.add(detection);
    }

    return selected;
  }

  double _iou(Rect a, Rect b) {
    final intersectLeft = a.left > b.left ? a.left : b.left;
    final intersectTop = a.top > b.top ? a.top : b.top;
    final intersectRight = a.right < b.right ? a.right : b.right;
    final intersectBottom = a.bottom < b.bottom ? a.bottom : b.bottom;

    if (intersectRight < intersectLeft || intersectBottom < intersectTop) {
      return 0.0;
    }

    final intersectArea =
        (intersectRight - intersectLeft) * (intersectBottom - intersectTop);
    final aArea = a.width * a.height;
    final bArea = b.width * b.height;

    return intersectArea / (aArea + bArea - intersectArea);
  }

  void close() {
    _interpreter?.close();
  }
}