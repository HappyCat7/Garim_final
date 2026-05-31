import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

class ExportScreen extends StatefulWidget {
  final Uint8List blurredImage;
  final Uint8List originalBytes;

  const ExportScreen({
    super.key,
    required this.blurredImage,
    required this.originalBytes,
  });

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  bool _isSaving  = false;
  bool _isSharing = false;
  bool _savedDone = false;

  Future<void> _saveImage() async {
    setState(() => _isSaving = true);
    try {
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/garim_save.jpg');
      await file.writeAsBytes(widget.blurredImage);
      await Gal.putImage(file.path);
      setState(() => _savedDone = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('갤러리에 저장됐어요'),
            backgroundColor: Color(0xFF43E97B),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패: $e'), backgroundColor: Colors.red.shade900),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _shareImage() async {
    setState(() => _isSharing = true);
    try {
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/garim_share.jpg');
      await file.writeAsBytes(widget.blurredImage);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: '가림 앱으로 개인정보를 보호했어요',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('공유 실패: $e'), backgroundColor: Colors.red.shade900),
        );
      }
    } finally {
      setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFFFF),
        foregroundColor: const Color(0xFF1F2937),
        title: const Text('저장 · 공유', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: Column(
        children: [
          // ── 이미지 미리보기 ────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 5.0,
                  child: Image.memory(
                    widget.blurredImage,
                    fit: BoxFit.contain,
                    width: double.infinity,
                  ),
                ),
              ),
            ),
          ),

          // ── 완료 배너 ─────────────────────────────────────────────
          if (_savedDone)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Color(0xFF7DD3C7).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Color(0xFF7DD3C7).withValues(alpha: 0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: Color(0xFF7DD3C7), size: 18),
                  SizedBox(width: 8),
                  Text('갤러리에 저장됐어요',
                      style: TextStyle(color: Color(0xFF2F8F83), fontSize: 13)),
                ],
              ),
            ),

          const SizedBox(height: 8),

          // ── 버튼 영역 ─────────────────────────────────────────────
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  // 저장 버튼
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _saveImage,
                      icon: _isSaving
                          ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            color: Color(0xFF1F2937), strokeWidth: 2),
                      )
                          : const Icon(Icons.save_alt_outlined),
                      label: Text(_isSaving ? '저장 중...' : '갤러리에 저장'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8FC9F7),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        textStyle: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // 공유 버튼
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSharing ? null : _shareImage,
                      icon: _isSharing
                          ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            color: Color(0xFF1F2937), strokeWidth: 2),
                      )
                          : const Icon(Icons.share_outlined),
                      label: Text(_isSharing ? '공유 중...' : '공유하기'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFCFC4F7),
                        foregroundColor: const Color(0xFF1F2937),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        textStyle: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // 다시 편집 버튼
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: const Text('다시 편집하기'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF4B5563),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}