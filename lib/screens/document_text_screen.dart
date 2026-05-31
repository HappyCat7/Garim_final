import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:typed_data';
import '../services/privacy_detector_service.dart';
import '../models/detection_result.dart';

class DocumentTextScreen extends StatefulWidget {
  final File imageFile;
  final List<DetectionResult> documentDetections;
  final Size imageSize;
  final String title;

  const DocumentTextScreen({
    super.key,
    required this.imageFile,
    required this.documentDetections,
    required this.imageSize,
    this.title = '문서 텍스트 탐지',
  });

  @override
  State<DocumentTextScreen> createState() => _DocumentTextScreenState();
}

class _DocumentTextScreenState extends State<DocumentTextScreen> {
  final _privacyService = PrivacyDetectorService();
  List<DetectionResult> _privacyResults = [];
  Uint8List? _imageBytes;
  bool _isProcessing = true;
  String _statusMessage = '텍스트 분석 중...';

  final _transformationController = TransformationController();
  bool _isZoomed = false;
  bool _pointerInImage = false;

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(() {
      final scale = _transformationController.value.getMaxScaleOnAxis();
      final zoomed = scale > 1.01;
      if (zoomed != _isZoomed) {
        setState(() => _isZoomed = zoomed);
      }
    });
    _analyze();
  }

  Future<void> _analyze() async {
    try {
      _imageBytes = await widget.imageFile.readAsBytes();

      setState(() => _statusMessage = '개인정보를 검사하고 있어요...');

      List<DetectionResult> allPrivacy = [];
      for (final doc in widget.documentDetections) {
        final privacy = await _privacyService.detectFromRegion(
          widget.imageFile,
          doc.boundingBox,
          widget.imageSize.width,
          widget.imageSize.height,
        );
        allPrivacy.addAll(privacy);
      }

      setState(() {
        _privacyResults = allPrivacy;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = '오류: $e';
      });
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _privacyService.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFFFF),
        foregroundColor: const Color(0xFF1F2937),
        title: Text(widget.title,              // ← 이렇게
            style: const TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: _isProcessing ? _buildLoading() : _buildResult(),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Color(0xFF6C63FF)),
          const SizedBox(height: 24),
          Text(_statusMessage,
              style: const TextStyle(color: Color(0xFF1F2937), fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildResult() {
    return Column(
      children: [
        // 탐지 결과 요약
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Color(0xFFF7FAFC),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                _privacyResults.isEmpty
                    ? Icons.check_circle_outline
                    : Icons.warning_amber_rounded,
                color: _privacyResults.isEmpty
                    ? const Color(0xFF7DD3C7)
                    : const Color(0xFF8FC9F7),
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _privacyResults.isEmpty
                          ? '개인정보가 발견되지 않았습니다'
                          : '${_privacyResults.length}개의 개인정보가 발견되었습니다',
                      style: const TextStyle(
                        color: Color(0xFF1F2937),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    if (_privacyResults.isNotEmpty)
                      Text(
                        _privacyResults
                            .expand((r) => r.privacyTexts)
                            .toSet()
                            .join(', '),
                        style: const TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 이미지 + 개인정보 영역 표시
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Listener(
              onPointerDown: (_) => setState(() => _pointerInImage = true),
              onPointerUp: (_) => setState(() => _pointerInImage = false),
              onPointerCancel: (_) => setState(() => _pointerInImage = false),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final displayWidth = constraints.maxWidth;
                    final displayHeight = widget.imageSize.height *
                        displayWidth /
                        widget.imageSize.width;

                    return InteractiveViewer(
                      transformationController: _transformationController,
                      minScale: 1.0,
                      maxScale: 5.0,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(
                        width: displayWidth,
                        height: displayHeight,
                        child: Stack(
                          children: [
                            // 원본 이미지
                            Positioned.fill(
                              child: Image.memory(
                                _imageBytes!,
                                fit: BoxFit.fill,
                              ),
                            ),

                            // 문서 영역 표시 (초록 박스)
                            ...widget.documentDetections.map((d) {
                              final scaleX = displayWidth / widget.imageSize.width;
                              final scaleY = displayHeight / widget.imageSize.height;
                              return Positioned(
                                left: d.boundingBox.left * scaleX,
                                top: d.boundingBox.top * scaleY,
                                width: d.boundingBox.width * scaleX,
                                height: d.boundingBox.height * scaleY,
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Color(0xFF7DD3C7),
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              );
                            }),

                            // 개인정보 영역 표시 (빨간 박스)
                            ..._privacyResults.map((d) {
                              final scaleX = displayWidth / widget.imageSize.width;
                              final scaleY = displayHeight / widget.imageSize.height;
                              final left = d.boundingBox.left * scaleX;
                              final top = d.boundingBox.top * scaleY;
                              final width = d.boundingBox.width * scaleX;
                              final height = d.boundingBox.height * scaleY;

                              return Positioned(
                                left: left,
                                top: top,
                                width: width,
                                height: height,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Container(
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: Color(0xFF8FC9F7),
                                          width: 2,
                                        ),
                                        color: Color(0xFF8FC9F7)
                                            .withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                    Positioned(
                                      top: -18,
                                      left: 0,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Color(0xFF8FC9F7),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          d.privacyTexts.isNotEmpty
                                              ? d.privacyTexts.first
                                              : '개인정보',
                                          style: const TextStyle(
                                            color: Color(0xFF1F2937),
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),

        // 하단 버튼
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (_privacyResults.isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context, {
                        'useTextBlur': true,
                        'privacyResults': _privacyResults,
                      });
                    },
                    icon: const Icon(Icons.text_fields),
                    label: const Text('개인정보 영역만 블러처리'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8FC9F7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context, {
                      'useTextBlur': false,
                      'privacyResults': [],
                    });
                  },
                  icon: const Icon(Icons.blur_on),
                  label: const Text('문서 전체 블러처리'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8FC9F7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text(
                    '취소 (블러 안함)',
                    style: TextStyle(color: Color(0xFF888888)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}