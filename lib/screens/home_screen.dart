import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
//import 'result_screen.dart';
import 'multi_result_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;

  Future<void> _pickImage() async {
    final List<XFile> files = await _picker.pickMultiImage(
      imageQuality: 100,
    );
    if (files.isEmpty) return;

    setState(() => _isLoading = true);

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MultiResultScreen(
          imageFiles: files.map((f) => File(f.path)).toList(),
        ),
      ),
    ).then((_) => setState(() => _isLoading = false));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 60),

              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF3D3D3D),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: Color(0xFF6C63FF),
                  size: 40,
                ),
              ),

              const SizedBox(height: 24),

              const Text(
                '가림',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'AI가 사진 속 개인정보를 찾아 보호합니다',
                style: TextStyle(
                  color: Color(0xFF888888),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 60),

              _buildFeatureCard(
                Icons.face_outlined,
                '얼굴 탐지',
                '사진 속 얼굴을 자동으로 찾아 블러처리',
                const Color(0xFFFF6B6B),
              ),
              const SizedBox(height: 12),
              _buildFeatureCard(
                Icons.directions_car_outlined,
                '번호판 탐지',
                '차량 번호판을 인식하여 블러처리',
                const Color(0xFF6C63FF),
              ),
              const SizedBox(height: 12),
              _buildFeatureCard(
                Icons.document_scanner_outlined,
                '문서 탐지',
                '문서 내 개인정보를 탐지하여 블러처리',
                const Color(0xFF43E97B),
              ),

              const Spacer(),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _pickImage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                      : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.photo_library_outlined, size: 20),
                      SizedBox(width: 8),
                      Text(
                        '갤러리에서 사진 선택',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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
      IconData icon,
      String title,
      String description,
      Color color,
      ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2D2D2D)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
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
    );
  }
}