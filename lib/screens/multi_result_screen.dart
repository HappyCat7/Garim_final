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