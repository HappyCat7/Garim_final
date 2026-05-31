import 'package:flutter/material.dart';
import 'dart:io';
import 'detection_summary_screen.dart';

class MultiResultScreen extends StatefulWidget {
  final List<File> imageFiles;

  const MultiResultScreen({
    super.key,
    required this.imageFiles,
  });

  @override
  State<MultiResultScreen> createState() => _MultiResultScreenState();
}

class _MultiResultScreenState extends State<MultiResultScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFFFF),
        foregroundColor: const Color(0xFF1F2937),
        title: Text(
          '${_currentIndex + 1} / ${widget.imageFiles.length}',
          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
        ),
        elevation: 0,
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.imageFiles.length,
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
        },
        itemBuilder: (context, index) {
          return DetectionSummaryScreen(
            imageFile: widget.imageFiles[index],
          );
        },
      ),
    );
  }
}