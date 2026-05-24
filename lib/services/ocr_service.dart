import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OCRService {
  final TextRecognizer textRecognizer = TextRecognizer(
    script: TextRecognitionScript.korean,
  );

  Future<List<TextLine>> processImage(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);

    final RecognizedText recognizedText =
    await textRecognizer.processImage(inputImage);

    final List<TextLine> lines = [];

    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        lines.add(line);
      }
    }

    return lines;
  }

  void close() {
    textRecognizer.close();
  }
}