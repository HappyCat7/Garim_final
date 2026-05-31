import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'multi_result_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;
  bool _autoPickerStarted = false;

  @override
  void initState() {
    super.initState();

    // 스플래시가 끝난 직후 바로 갤러리가 뜨면 너무 급하게 느껴지므로
    // 약 0.6초 동안 첫 화면을 유지한 뒤 사진 선택 화면을 연다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted || _autoPickerStarted) return;
        _autoPickerStarted = true;
        _pickImage();
      });
    });
  }

  // [Req 6] 단일 사진만 선택 — pickImage (pickMultiImage 완전 제거)
  Future<void> _pickImage() async {
    final XFile? file = await _picker.pickImage(source: ImageSource.gallery,imageQuality: 100);
    if (file == null) return;

    setState(() => _isLoading = true);
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MultiResultScreen(
          imageFiles: [File(file.path)],
        ),
      ),
    ).then((_) {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 60),
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: Color(0xFFF7FAFC),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Color(0xFFBFE4F5)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Image.asset(
                    'assets/splash_logo.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text('Garim',
                  style: TextStyle(
                      color: Color(0xFF1F2937),
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4)),
              const SizedBox(height: 8),
              const Text('AI가 사진 속 개인정보를 찾아 보호합니다',
                  style: TextStyle(color: Color(0xFF888888), fontSize: 14),
                  textAlign: TextAlign.center),
              const SizedBox(height: 48),
              _buildFeatureCard(Icons.face_outlined, '얼굴 탐지',
                  '사진 속 얼굴을 자동으로 찾아 블러처리', const Color(0xFF8FC9F7)),
              const SizedBox(height: 12),
              _buildFeatureCard(Icons.directions_car_outlined, '번호판 탐지',
                  '차량 번호판을 인식하여 블러처리', const Color(0xFF8FC9F7)),
              const SizedBox(height: 12),
              _buildFeatureCard(Icons.document_scanner_outlined, '문서 탐지',
                  '문서 내 개인정보를 탐지하여 블러처리', const Color(0xFF7DD3C7)),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _pickImage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8FC9F7),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                      width: 24, height: 24,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                      : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.photo_outlined, size: 20),
                      SizedBox(width: 8),
                      Text('사진 1장 선택',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureCard(
      IconData icon, String title, String description, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFFF7FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color(0xFFDCEFF8)),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Color(0xFF1F2937),
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(description,
                    style: const TextStyle(
                        color: Color(0xFF888888), fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}