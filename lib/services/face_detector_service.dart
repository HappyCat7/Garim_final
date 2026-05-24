import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter/material.dart';
import '../models/detection_result.dart';

class FaceDetectorService {
  late FaceDetector _faceDetector;

  FaceDetectorService() {
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        minFaceSize: 0.1,
      ),
    );
  }

  Future<List<DetectionResult>> detect(InputImage inputImage) async {
    final faces = await _faceDetector.processImage(inputImage);
    return faces.map((face) {
      return DetectionResult(
        type: DetectionType.face,
        boundingBox: Rect.fromLTRB(
          face.boundingBox.left,
          face.boundingBox.top,
          face.boundingBox.right,
          face.boundingBox.bottom,
        ),
        confidence: 0.95,
      );
    }).toList();
  }

  Future<void> close() async {
    await _faceDetector.close();
  }
}