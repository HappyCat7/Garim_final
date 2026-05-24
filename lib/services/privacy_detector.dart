import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/privacy_item.dart';

class PrivacyDetector {
  static List<PrivacyItem> detect(List<TextLine> lines) {
    final List<_DetectedSpan> spans = [];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final rawText = line.text.trim();

      if (rawText.isEmpty) continue;
      if (_isTitleOrSectionHeader(rawText)) continue;
      if (_isTableHeader(rawText)) continue;

      final labelType = _labelType(rawText);
      final bool currentLineWaybillContext = _isWaybillContext(rawText);

      _addRegexMatches(
        spans: spans,
        line: line,
        regex: _rrnRegex,
        type: 'RRN',
        confidence: 'HIGH',
      );

      _addPartialRrnMatches(spans: spans, line: line);

      _addRegexMatches(
        spans: spans,
        line: line,
        regex: _phoneRegex,
        type: 'PHONE',
        confidence: 'HIGH',
      );

      _addEmailMatches(spans: spans, line: line);

      _addRegexMatches(
        spans: spans,
        line: line,
        regex: _cardRegex,
        type: 'CARD_NUMBER',
        confidence: 'HIGH',
      );

      _addRegexMatches(
        spans: spans,
        line: line,
        regex: _driverLicenseRegex,
        type: 'DRIVER_LICENSE',
        confidence: 'MEDIUM',
      );

      _addRegexMatches(
        spans: spans,
        line: line,
        regex: _passportRegex,
        type: 'PASSPORT_NUMBER',
        confidence: 'MEDIUM',
      );

      if (currentLineWaybillContext) {
        _addRegexMatches(
          spans: spans,
          line: line,
          regex: _waybillCodeRegex,
          type: 'WAYBILL_CODE',
          confidence: 'MEDIUM',
          avoidOverlapTypes: {
            'ACCOUNT_NUMBER',
            'PHONE',
            'CARD_NUMBER',
          },
        );
      }

      if ((_hasAccountContext(rawText) || _looksLikeAccountOnly(rawText)) &&
          !currentLineWaybillContext) {
        _addRegexMatches(
          spans: spans,
          line: line,
          regex: _accountRegex,
          type: 'ACCOUNT_NUMBER',
          confidence: 'HIGH',
          avoidOverlapTypes: {
            'PHONE',
            'CARD_NUMBER',
            'DRIVER_LICENSE',
            'RRN',
            'PARTIAL_RRN',
            'WAYBILL_CODE',
          },
        );
      }

      if (_hasBirthContext(rawText) || _looksLikeBirthDateOnly(rawText)) {
        _addRegexMatches(
          spans: spans,
          line: line,
          regex: _dateRegex,
          type: 'BIRTH_DATE',
          confidence: 'MEDIUM',
        );
      }

      final address = _extractAddressSpan(rawText);
      if (address != null) {
        _addManualSpan(
          spans: spans,
          line: line,
          span: address,
          type: 'ADDRESS',
          confidence: 'MEDIUM',
        );
      }

      final company = _extractCompanySpan(rawText);
      if (company != null) {
        _addManualSpan(
          spans: spans,
          line: line,
          span: company,
          type: 'COMPANY',
          confidence: 'MEDIUM',
        );
      }

      final department = _extractDepartmentSpan(rawText);
      if (department != null) {
        _addManualSpan(
          spans: spans,
          line: line,
          span: department,
          type: 'DEPARTMENT',
          confidence: 'MEDIUM',
        );
      }

      final position = _extractPositionSpan(rawText);
      if (position != null) {
        _addManualSpan(
          spans: spans,
          line: line,
          span: position,
          type: 'POSITION',
          confidence: 'MEDIUM',
        );
      }

      final waybillName = _extractWaybillNameSpan(
        rawText,
        isWaybillContext: currentLineWaybillContext,
      );

      if (waybillName != null) {
        _addManualSpan(
          spans: spans,
          line: line,
          span: waybillName,
          type: 'WAYBILL_NAME',
          confidence: 'MEDIUM',
        );
      } else {
        final names = _extractNameSpans(rawText);
        for (final name in names) {
          _addManualSpan(
            spans: spans,
            line: line,
            span: name,
            type: 'NAME',
            confidence: 'MEDIUM',
          );
        }
      }

      if (labelType != null) {
        _detectTableValueByLabel(
          spans: spans,
          lines: lines,
          labelIndex: i,
          labelType: labelType,
        );
      }
    }

    _addWaybillOrderNumberFragments(spans: spans, lines: lines);

    return _removeDuplicates(
      spans.map((e) => e.toPrivacyItem()).toList(),
    );
  }

  static void _addWaybillOrderNumberFragments({
    required List<_DetectedSpan> spans,
    required List<TextLine> lines,
  }) {
    for (final labelLine in lines) {
      final labelText = labelLine.text.trim();
      final labelRect = labelLine.boundingBox;

      final compactLabel = labelText.replaceAll(' ', '');

      final bool isOrderLabel =
          compactLabel.contains('주문번') || compactLabel.contains('주문번호');

      if (!isOrderLabel) continue;

      for (final candidateLine in lines) {
        if (candidateLine == labelLine) continue;

        final text = candidateLine.text.trim();
        final rect = candidateLine.boundingBox;
        if (text.isEmpty) continue;

        final compact = text.replaceAll(' ', '');
        final normalized = compact.replaceAll(',', '');

        final bool looksOrderNumber =
            RegExp(r'^[0-9]{8,15}$').hasMatch(normalized) ||
                RegExp(r'^[0-9]{1,4},[0-9]{6,12}$').hasMatch(compact);

        if (!looksOrderNumber) continue;

        final dx = (rect.center.dx - labelRect.center.dx).abs();
        final dy = (rect.center.dy - labelRect.center.dy).abs();

        final bool nearOrderLabel = dx < 420 && dy < 260;
        if (!nearOrderLabel) continue;

        final alreadyDetected = spans.any((span) {
          final sr = span.rect;
          final overlap = sr.overlaps(rect.inflate(8));
          return overlap &&
              (span.type == 'WAYBILL_ORDER_NUMBER' ||
                  span.type == 'WAYBILL_CODE' ||
                  span.type == 'ACCOUNT_NUMBER');
        });

        if (alreadyDetected) continue;

        _addManualSpan(
          spans: spans,
          line: candidateLine,
          span: _TextSpanResult(
            value: text,
            start: 0,
            end: text.length,
          ),
          type: 'WAYBILL_ORDER_NUMBER',
          confidence: 'MEDIUM',
        );
      }
    }
  }

  static bool _isWaybillContext(String text) {
    final compact = text.replaceAll(' ', '').toUpperCase();

    return compact.contains('CJ') ||
        compact.contains('대한통운') ||
        compact.contains('택배') ||
        compact.contains('운송') ||
        compact.contains('연번') ||
        compact.contains('배송') ||
        compact.contains('개인정보유출') ||
        compact.contains('폐기바랍') ||
        compact.contains('천안병천') ||
        compact.contains('TW2S') ||
        compact.contains('RPB') ||
        compact.contains('DOO') ||
        compact.contains('DO0') ||
        compact.contains('주문번') ||
        compact.contains('주문번호');
  }

  static _TextSpanResult? _extractWaybillNameSpan(
      String text, {
        required bool isWaybillContext,
      }) {
    final compact = text.trim();

    final blacklist = {
      '오전',
      '오후',
      '현용',
      '배송',
      '운송',
      '택배',
      '연번',
      '주문번',
      '주문번호',
      '보내는이',
      '받는이',
      '내는이',
      '개인정보',
      '보호',
      '이메일',
      '메일',
      '주소',
      '연락처',
      '전화번호',
      '전화',
      '회사명',
      '담당자',
      '성명',
      '이름',
      '직책',
      '소속',
      '계좌번호',
      '생년월일',
      '주민번호',
      '주민등록번호',
    };

    if (blacklist.contains(compact)) return null;

    final maskedMatch = RegExp(
      r'^([가-힣]{1,3}[\*＊xX][가-힣]{0,2}|[가-힣]{1,2}[\*＊xX][가-힣]{1,2})$',
    ).firstMatch(compact);

    if (maskedMatch != null) {
      final value = maskedMatch.group(1);
      if (value == null) return null;

      final start = compact.indexOf(value);

      return _TextSpanResult(
        value: value,
        start: start,
        end: start + value.length,
      );
    }

    if (!isWaybillContext) return null;

    final plainMatch = RegExp(r'^([가-힣]{2,4})$').firstMatch(compact);
    if (plainMatch == null) return null;

    final value = plainMatch.group(1);
    if (value == null) return null;

    if (!_hasLikelyKoreanSurname(value)) return null;

    final start = compact.indexOf(value);

    return _TextSpanResult(
      value: value,
      start: start,
      end: start + value.length,
    );
  }

  static void _detectTableValueByLabel({
    required List<_DetectedSpan> spans,
    required List<TextLine> lines,
    required int labelIndex,
    required String labelType,
  }) {
    final labelLine = lines[labelIndex];
    final labelRect = labelLine.boundingBox;

    TextLine? valueLine;

    for (final candidate in lines) {
      if (candidate == labelLine) continue;

      final rect = candidate.boundingBox;

      final sameRow = (rect.center.dy - labelRect.center.dy).abs() < 18;
      final isRightSide = rect.left > labelRect.right + 40;

      if (sameRow && isRightSide) {
        valueLine = candidate;
        break;
      }
    }

    if (valueLine == null) return;

    final valueText = valueLine.text.trim();

    if (labelType == 'NAME') {
      final waybillName = _extractWaybillNameSpan(
        valueText,
        isWaybillContext: _isWaybillContext(valueText),
      );

      if (waybillName != null) {
        _addManualSpan(
          spans: spans,
          line: valueLine,
          span: waybillName,
          type: 'WAYBILL_NAME',
          confidence: 'MEDIUM',
        );
      } else {
        final names = _extractNameSpans(valueText);
        for (final name in names) {
          _addManualSpan(
            spans: spans,
            line: valueLine,
            span: name,
            type: 'NAME',
            confidence: 'MEDIUM',
          );
        }
      }
      return;
    }

    if (labelType == 'COMPANY') {
      final company = _extractCompanySpan(valueText);
      if (company != null) {
        _addManualSpan(
          spans: spans,
          line: valueLine,
          span: company,
          type: 'COMPANY',
          confidence: 'MEDIUM',
        );
      }
      return;
    }

    if (labelType == 'DEPARTMENT') {
      final department = _extractDepartmentSpan(valueText);
      if (department != null) {
        _addManualSpan(
          spans: spans,
          line: valueLine,
          span: department,
          type: 'DEPARTMENT',
          confidence: 'MEDIUM',
        );
      }
      return;
    }

    if (labelType == 'POSITION') {
      final position = _extractPositionSpan(valueText);
      if (position != null) {
        _addManualSpan(
          spans: spans,
          line: valueLine,
          span: position,
          type: 'POSITION',
          confidence: 'MEDIUM',
        );
      }
      return;
    }

    if (labelType == 'RRN') {
      _addRegexMatches(
        spans: spans,
        line: valueLine,
        regex: _rrnRegex,
        type: 'RRN',
        confidence: 'HIGH',
      );
      _addPartialRrnMatches(spans: spans, line: valueLine);
      return;
    }

    if (labelType == 'PHONE') {
      _addRegexMatches(
        spans: spans,
        line: valueLine,
        regex: _phoneRegex,
        type: 'PHONE',
        confidence: 'HIGH',
      );
      return;
    }

    if (labelType == 'EMAIL') {
      _addEmailMatches(spans: spans, line: valueLine);
      return;
    }

    if (labelType == 'ADDRESS') {
      final address = _extractAddressSpan(valueText);
      if (address != null) {
        _addManualSpan(
          spans: spans,
          line: valueLine,
          span: address,
          type: 'ADDRESS',
          confidence: 'MEDIUM',
        );
      }
      return;
    }

    if (labelType == 'ACCOUNT_NUMBER') {
      _addRegexMatches(
        spans: spans,
        line: valueLine,
        regex: _accountRegex,
        type: 'ACCOUNT_NUMBER',
        confidence: 'HIGH',
        avoidOverlapTypes: {
          'PHONE',
          'CARD_NUMBER',
          'DRIVER_LICENSE',
          'RRN',
          'PARTIAL_RRN',
          'WAYBILL_CODE',
        },
      );
      return;
    }

    if (labelType == 'BIRTH_DATE') {
      _addRegexMatches(
        spans: spans,
        line: valueLine,
        regex: _dateRegex,
        type: 'BIRTH_DATE',
        confidence: 'MEDIUM',
      );
      return;
    }
  }

  static void _addRegexMatches({
    required List<_DetectedSpan> spans,
    required TextLine line,
    required RegExp regex,
    required String type,
    required String confidence,
    Set<String> avoidOverlapTypes = const {},
  }) {
    final text = line.text.trim();

    for (final match in regex.allMatches(text)) {
      final value = text.substring(match.start, match.end);

      if (_isDocumentNumber(type, value, text)) continue;

      final candidate = _DetectedSpan(
        type: type,
        text: value,
        rect: _rectForTextSpan(
          line: line,
          start: match.start,
          end: match.end,
        ),
        polygon: _polygonForTextSpan(
          line: line,
          start: match.start,
          end: match.end,
        ),
        confidence: confidence,
        lineText: text,
        start: match.start,
        end: match.end,
      );

      if (_overlapsExisting(
        candidate: candidate,
        spans: spans,
        avoidTypes: avoidOverlapTypes,
      )) {
        continue;
      }

      spans.add(candidate);
    }
  }

  static void _addPartialRrnMatches({
    required List<_DetectedSpan> spans,
    required TextLine line,
  }) {
    final text = line.text.trim();
    final compact = text.replaceAll(' ', '');

    final hasRrnContext = compact.contains('주민등록번호') ||
        compact.contains('주민번호') ||
        compact.contains('뒤1자리') ||
        compact.contains('뒤1자') ||
        compact.contains('뒷자리');

    final isOnlySixDigits = RegExp(r'^[0-9]{6}$').hasMatch(compact);

    if (!isOnlySixDigits && !hasRrnContext) return;
    if (_rrnRegex.hasMatch(text)) return;

    for (final match in _partialRrnRegex.allMatches(text)) {
      final value = text.substring(match.start, match.end);

      final candidate = _DetectedSpan(
        type: 'PARTIAL_RRN',
        text: value,
        rect: _rectForTextSpan(
          line: line,
          start: match.start,
          end: match.end,
        ),
        polygon: _polygonForTextSpan(
          line: line,
          start: match.start,
          end: match.end,
        ),
        confidence: 'MEDIUM',
        lineText: text,
        start: match.start,
        end: match.end,
      );

      if (_overlapsExisting(
        candidate: candidate,
        spans: spans,
        avoidTypes: {
          'RRN',
          'PHONE',
          'ACCOUNT_NUMBER',
          'CARD_NUMBER',
          'DRIVER_LICENSE',
          'BIRTH_DATE',
        },
      )) {
        continue;
      }

      spans.add(candidate);
    }
  }

  static void _addEmailMatches({
    required List<_DetectedSpan> spans,
    required TextLine line,
  }) {
    final text = line.text.trim();
    final compact = text.replaceAll(RegExp(r'\s+'), '');

    for (final match in _emailRegex.allMatches(compact)) {
      final start = _mapCompactIndexToOriginal(
        originalText: text,
        compactIndex: match.start,
      );

      final end = _mapCompactIndexToOriginal(
        originalText: text,
        compactIndex: match.end,
      );

      final value = compact.substring(match.start, match.end);

      final candidate = _DetectedSpan(
        type: 'EMAIL',
        text: value,
        rect: _rectForTextSpan(
          line: line,
          start: start,
          end: end,
        ),
        polygon: _polygonForTextSpan(
          line: line,
          start: start,
          end: end,
        ),
        confidence: 'HIGH',
        lineText: text,
        start: start,
        end: end,
      );

      spans.add(candidate);
    }
  }

  static int _mapCompactIndexToOriginal({
    required String originalText,
    required int compactIndex,
  }) {
    int compactCount = 0;

    for (int i = 0; i < originalText.length; i++) {
      if (originalText[i].trim().isEmpty) continue;

      if (compactCount == compactIndex) return i;

      compactCount++;
    }

    return originalText.length;
  }

  static void _addManualSpan({
    required List<_DetectedSpan> spans,
    required TextLine line,
    required _TextSpanResult span,
    required String type,
    required String confidence,
  }) {
    final candidate = _DetectedSpan(
      type: type,
      text: span.value,
      rect: _rectForTextSpan(
        line: line,
        start: span.start,
        end: span.end,
      ),
      polygon: _polygonForTextSpan(
        line: line,
        start: span.start,
        end: span.end,
      ),
      confidence: confidence,
      lineText: line.text.trim(),
      start: span.start,
      end: span.end,
    );

    if (_overlapsExisting(
      candidate: candidate,
      spans: spans,
      avoidTypes: {
        'PHONE',
        'EMAIL',
        'RRN',
        'PARTIAL_RRN',
        'CARD_NUMBER',
        'ACCOUNT_NUMBER',
        'DRIVER_LICENSE',
        'PASSPORT_NUMBER',
        'BIRTH_DATE',
        'ADDRESS',
        'COMPANY',
        'DEPARTMENT',
        'POSITION',
        'WAYBILL_NAME',
        'WAYBILL_CODE',
        'WAYBILL_ORDER_NUMBER',
      },
    )) {
      return;
    }

    spans.add(candidate);
  }

  static Rect _rectForTextSpan({
    required TextLine line,
    required int start,
    required int end,
  }) {
    final lineText = line.text.trim();
    final lineRect = line.boundingBox;

    if (lineText.isEmpty) return Rect.zero;

    final safeStart = start.clamp(0, lineText.length);
    final safeEnd = end.clamp(safeStart, lineText.length);

    final elementRects = <Rect>[];
    int searchStart = 0;

    for (final element in line.elements) {
      final elementText = element.text;
      final elementRect = element.boundingBox;

      if (elementText.isEmpty) continue;

      final elementStart = lineText.indexOf(elementText, searchStart);
      if (elementStart == -1) continue;

      final elementEnd = elementStart + elementText.length;
      searchStart = elementEnd;

      final overlapStart = safeStart > elementStart ? safeStart : elementStart;
      final overlapEnd = safeEnd < elementEnd ? safeEnd : elementEnd;

      if (overlapStart >= overlapEnd) continue;

      final localStart = overlapStart - elementStart;
      final localEnd = overlapEnd - elementStart;

      final charWidth = elementRect.width / elementText.length;

      final rect = Rect.fromLTRB(
        elementRect.left + charWidth * localStart,
        elementRect.top,
        elementRect.left + charWidth * localEnd,
        elementRect.bottom,
      );

      elementRects.add(rect);
    }

    if (elementRects.isNotEmpty) {
      return _unionRects(elementRects).inflate(1.0);
    }

    final charWidth = lineRect.width / lineText.length;

    return Rect.fromLTRB(
      lineRect.left + charWidth * safeStart,
      lineRect.top,
      lineRect.left + charWidth * safeEnd,
      lineRect.bottom,
    ).inflate(1.0);
  }

  static List<Offset>? _polygonForTextSpan({
    required TextLine line,
    required int start,
    required int end,
  }) {
    final lineText = line.text.trim();

    if (lineText.isEmpty) return null;

    final safeStart = start.clamp(0, lineText.length);
    final safeEnd = end.clamp(safeStart, lineText.length);

    final List<List<Offset>> selectedPolygons = [];

    int searchStart = 0;

    for (final element in line.elements) {
      final elementText = element.text;
      if (elementText.isEmpty) continue;

      final elementStart = lineText.indexOf(elementText, searchStart);
      if (elementStart == -1) continue;

      final elementEnd = elementStart + elementText.length;
      searchStart = elementEnd;

      final overlapStart = safeStart > elementStart ? safeStart : elementStart;
      final overlapEnd = safeEnd < elementEnd ? safeEnd : elementEnd;

      if (overlapStart >= overlapEnd) continue;
      if (element.cornerPoints.length < 4) continue;

      final points = element.cornerPoints
          .map((point) => Offset(point.x.toDouble(), point.y.toDouble()))
          .toList();

      final double localStartRatio =
          (overlapStart - elementStart) / elementText.length;
      final double localEndRatio =
          (overlapEnd - elementStart) / elementText.length;

      final Offset leftTop = points[0];
      final Offset rightTop = points[1];
      final Offset rightBottom = points[2];
      final Offset leftBottom = points[3];

      final Offset spanLeftTop =
      Offset.lerp(leftTop, rightTop, localStartRatio)!;
      final Offset spanRightTop =
      Offset.lerp(leftTop, rightTop, localEndRatio)!;
      final Offset spanRightBottom =
      Offset.lerp(leftBottom, rightBottom, localEndRatio)!;
      final Offset spanLeftBottom =
      Offset.lerp(leftBottom, rightBottom, localStartRatio)!;

      selectedPolygons.add([
        spanLeftTop,
        spanRightTop,
        spanRightBottom,
        spanLeftBottom,
      ]);
    }

    if (selectedPolygons.isEmpty) return null;

    final Offset leftTop = selectedPolygons.first[0];
    final Offset rightTop = selectedPolygons.last[1];
    final Offset rightBottom = selectedPolygons.last[2];
    final Offset leftBottom = selectedPolygons.first[3];

    return [
      leftTop,
      rightTop,
      rightBottom,
      leftBottom,
    ];
  }

  static Rect _unionRects(List<Rect> rects) {
    double left = rects.first.left;
    double top = rects.first.top;
    double right = rects.first.right;
    double bottom = rects.first.bottom;

    for (final rect in rects.skip(1)) {
      if (rect.left < left) left = rect.left;
      if (rect.top < top) top = rect.top;
      if (rect.right > right) right = rect.right;
      if (rect.bottom > bottom) bottom = rect.bottom;
    }

    return Rect.fromLTRB(left, top, right, bottom);
  }

  static bool _overlapsExisting({
    required _DetectedSpan candidate,
    required List<_DetectedSpan> spans,
    required Set<String> avoidTypes,
  }) {
    for (final span in spans) {
      if (!avoidTypes.contains(span.type)) continue;

      final bool sameVisualPosition =
          (span.rect.center.dy - candidate.rect.center.dy).abs() < 4 &&
              (span.rect.center.dx - candidate.rect.center.dx).abs() < 4;

      if (!sameVisualPosition) continue;

      final overlap = candidate.start < span.end && candidate.end > span.start;

      if (overlap) return true;
    }

    return false;
  }

  static bool _isTitleOrSectionHeader(String text) {
    final compact = text.replaceAll(' ', '');

    final headers = [
      '고객서비스신청서',
      '개인정보수집동의서',
      '보안서약서',
      '채용분야및인원',
      '응시자격요건',
      '정보보안경영시스템인증서',
      '개인정보보호경영시스템인증서',
      '신청인정보',
      '금융정보',
      '추가인증정보',
      '담당자정보',
    ];

    if (headers.contains(compact)) return true;
    if (compact.endsWith('정보') && compact.length <= 8) return true;

    return false;
  }

  static bool _isTableHeader(String text) {
    final compact = text.replaceAll(' ', '');

    return compact == '항목' ||
        compact == '내용' ||
        compact == '구분' ||
        compact == '자격요건' ||
        compact == '담당업무' ||
        compact == '채용분야' ||
        compact == '인원';
  }

  static bool _isFieldLabelOnly(String text) {
    final compact = text.replaceAll(' ', '');

    final labels = [
      '이름',
      '성명',
      '회사명',
      '소속',
      '직책',
      '주민등록번호',
      '주민번호',
      '전화번호',
      '연락처',
      '이메일',
      '메일',
      '주소',
      '계좌번호',
      '생년월일',
      '여권번호',
      '운전면허번호',
      '면허번호',
      '카드번호',
      '서명인',
      '서명일자',
      '주문번',
      '주문번호',
      '보내는이',
      '받는이',
      '내는이',
    ];

    return labels.contains(compact);
  }

  static String? _labelType(String text) {
    final compact = text.replaceAll(' ', '');

    if (compact == '이름' || compact == '성명' || compact == '서명인') {
      return 'NAME';
    }

    if (compact.contains('회사명')) return 'COMPANY';
    if (compact == '소속') return 'DEPARTMENT';
    if (compact == '직책') return 'POSITION';

    if (compact.contains('주민등록번호') || compact.contains('주민번호')) {
      return 'RRN';
    }

    if (compact.contains('전화번호') || compact.contains('연락처')) {
      return 'PHONE';
    }

    if (compact.contains('이메일') || compact.toLowerCase().contains('email')) {
      return 'EMAIL';
    }

    if (compact == '주소' || compact.contains('거주지주소')) {
      return 'ADDRESS';
    }

    if (compact.contains('계좌번호')) return 'ACCOUNT_NUMBER';
    if (compact.contains('생년월일')) return 'BIRTH_DATE';

    return null;
  }

  static bool _hasBirthContext(String text) {
    final compact = text.replaceAll(' ', '');

    return compact.contains('생년월일') ||
        compact.contains('출생') ||
        compact.toLowerCase().contains('birth') ||
        compact.toLowerCase().contains('dob');
  }

  static bool _hasAccountContext(String text) {
    final compact = text.replaceAll(' ', '');

    return compact.contains('계좌') ||
        compact.contains('은행') ||
        compact.contains('입금') ||
        compact.contains('출금') ||
        compact.contains('자동이체');
  }

  static bool _looksLikeAccountOnly(String text) {
    final compact = text.replaceAll(' ', '');

    if (_waybillCodeRegex.hasMatch(compact)) return false;
    if (!_accountRegex.hasMatch(compact)) return false;
    if (_phoneRegex.hasMatch(compact)) return false;
    if (_driverLicenseRegex.hasMatch(compact)) return false;
    if (_cardRegex.hasMatch(compact)) return false;
    if (_rrnRegex.hasMatch(compact)) return false;

    return true;
  }

  static bool _looksLikeBirthDateOnly(String text) {
    final compact = text.replaceAll(' ', '');

    if (!_dateRegex.hasMatch(compact)) return false;

    final dateOnly = RegExp(
      r'^(19|20)[0-9]{2}[-./][0-9]{1,2}[-./][0-9]{1,2}$',
    );

    return dateOnly.hasMatch(compact);
  }

  static bool _isDocumentNumber(
      String type,
      String matchedText,
      String fullLine,
      ) {
    final compactLine = fullLine.replaceAll(' ', '');

    if (compactLine.contains('접수번호') ||
        compactLine.contains('신청번호') ||
        compactLine.contains('문서번호') ||
        compactLine.contains('관리번호') ||
        compactLine.contains('공고제')) {
      return true;
    }

    if (type == 'BIRTH_DATE') return false;

    return false;
  }

  static _TextSpanResult? _extractAddressSpan(String text) {
    final compact = text.replaceAll(' ', '');

    if (_isNonAddressSentence(compact)) return null;

    final hasKoreanAddressStart = RegExp(
      r'(서울|부산|대구|인천|광주|대전|울산|세종|경기|강원|충북|충남|전북|전남|경북|경남|제주|충청남도|천안시|고양시|종로구|동남구|덕양구|병천면)',
    ).hasMatch(compact);

    final hasKoreanAddressDetail = RegExp(
      r'([0-9]+길|[0-9]+로|[0-9]+번지|[0-9]+호|[0-9]+층|[0-9]+동|가전7길|종로1길|아파트|빌라|마을|단지|빌딩)',
    ).hasMatch(compact);

    if (hasKoreanAddressStart && hasKoreanAddressDetail) {
      return _TextSpanResult(
        value: text,
        start: 0,
        end: text.length,
      );
    }

    final hasRegion = RegExp(
      r'(서울|부산|대구|인천|광주|대전|울산|세종|경기|강원|충북|충남|전북|전남|경북|경남|제주|천안|충청남도|충남)',
    ).hasMatch(compact);

    final hasAddressUnit = RegExp(
      r'(특별시|광역시|도|시|군|구|읍|면|동|리|로|길|번길|가길|층|호|빌딩|아파트|단지)',
    ).hasMatch(compact);

    final hasDigit = RegExp(r'[0-9]').hasMatch(compact);

    if (hasRegion && hasAddressUnit && hasDigit) {
      return _TextSpanResult(
        value: text,
        start: 0,
        end: text.length,
      );
    }

    final roadAddressRegex = RegExp(
      r'(서울|부산|대구|인천|광주|대전|울산|세종|경기|강원|충북|충남|전북|전남|경북|경남|제주|천안|충청남도)'
      r'[가-힣0-9\s,\-\(\)]*'
      r'(로|길|번길|가길)\s?[0-9]*',
    );

    final roadMatch = roadAddressRegex.firstMatch(text);

    if (roadMatch != null) {
      final value = text.substring(roadMatch.start, roadMatch.end).trim();

      return _TextSpanResult(
        value: value,
        start: roadMatch.start,
        end: roadMatch.end,
      );
    }

    final detailAddressRegex = RegExp(
      r'^[0-9]+(번|동|호|층|단지)|[0-9]+번\s?(가길|길|로)',
    );

    if (detailAddressRegex.hasMatch(compact)) {
      return _TextSpanResult(
        value: text,
        start: 0,
        end: text.length,
      );
    }

    if (_looksLikeBuildingOrHousingName(compact)) {
      return _TextSpanResult(
        value: text,
        start: 0,
        end: text.length,
      );
    }

    return null;
  }

  static bool _isNonAddressSentence(String compact) {
    if (compact.isEmpty) return true;

    if (compact.contains('서비스') ||
        compact.contains('고객센터') ||
        compact.contains('센터') ||
        compact.contains('상담') ||
        compact.contains('문의')) {
      return true;
    }

    if (RegExp(r'15[0-9]{2}[-]?[0-9A-Za-z]{3,4}').hasMatch(compact)) {
      return true;
    }

    if (compact.contains('@') ||
        compact.contains('이메일') ||
        compact.contains('메일') ||
        compact.toLowerCase().contains('email')) {
      return true;
    }

    if (compact.contains('주민등록번호') ||
        compact.contains('주민번호') ||
        compact.contains('뒤1자리') ||
        compact.contains('뒤1자') ||
        compact.contains('뒷자리') ||
        compact.contains('표기')) {
      return true;
    }

    if (RegExp(r'^[0-9]+\.').hasMatch(compact)) return true;
    if (RegExp(r'^제[0-9]+조').hasMatch(compact)) return true;

    final sentenceKeywords = [
      '공고',
      '응시자격',
      '자격요건',
      '결격사유',
      '지방공무원법',
      '인사규정',
      '해당되지',
      '관련분야',
      '경력',
      '학위',
      '회사에서',
      '회사밖으로',
      '프로그램',
      '서류',
      '자료',
      '외부로',
      '유출',
      '누설',
      '보관된',
      '작성한',
      '구매한',
      '개발한',
      '근무중',
      '일체',
      '허가없이',
      '부서단위',
      '책임자',
      '이상으로',
      '근무한',
    ];

    return sentenceKeywords.any((keyword) => compact.contains(keyword));
  }

  static bool _looksLikeBuildingOrHousingName(String compact) {
    if (compact.length < 4) return false;

    final buildingKeywords = [
      '아파트',
      '빌라',
      '오피스텔',
      '주택',
      '맨션',
      '타운',
      '하우스',
      '빌리지',
      '팰리스',
      '캐슬',
      '자이',
      '푸르지오',
      '래미안',
      '힐스테이트',
      '아이파크',
      '더샵',
      '롯데캐슬',
      'e편한세상',
      '이편한세상',
      '센트럴',
      '파크',
      '리버',
      '포레',
      '메르디앙',
      '월드',
      '마을',
      '단지',
      '빌딩',
    ];

    if (buildingKeywords.any((keyword) => compact.contains(keyword))) {
      return true;
    }

    if (RegExp(r'[0-9]+단지').hasMatch(compact)) return true;
    if (RegExp(r'[0-9]+동').hasMatch(compact)) return true;
    if (RegExp(r'[0-9]+호').hasMatch(compact)) return true;

    return false;
  }

  static _TextSpanResult? _extractCompanySpan(String text) {
    final compact = text.trim();
    final noSpace = compact.replaceAll(' ', '');

    if (_isFieldLabelOnly(compact)) return null;

    final sentenceBlockKeywords = [
      '회사에서',
      '회사의',
      '회사에',
      '회사 밖',
      '회사밖',
      '본회사',
      '본 회사',
      '프로그램',
      '구매한',
      '개발한',
      '근무',
      '직원',
      '보안',
      '지침',
      '재산',
      '손해',
      '유출',
      '누설',
      '사항',
      '일체',
    ];

    if (sentenceBlockKeywords.any((word) => compact.contains(word))) {
      return null;
    }

    if (compact.contains('주식회사')) {
      if (compact.length > 30) return null;

      return _TextSpanResult(
        value: compact,
        start: 0,
        end: compact.length,
      );
    }

    if (compact.startsWith('(주)')) {
      if (compact.length > 30) return null;

      return _TextSpanResult(
        value: compact,
        start: 0,
        end: compact.length,
      );
    }

    final companySuffixRegex = RegExp(
      r'^([가-힣A-Za-z0-9\s]{2,25}(공사|공단|재단|협회|조합|기관|추진단|연구원|대학교|병원|테크|산업|기업))$',
    );

    final match = companySuffixRegex.firstMatch(compact);
    if (match == null) return null;

    final value = match.group(1);
    if (value == null) return null;

    if (noSpace == '회사') return null;

    final start = compact.indexOf(value);

    return _TextSpanResult(
      value: value,
      start: start,
      end: start + value.length,
    );
  }

  static _TextSpanResult? _extractDepartmentSpan(String text) {
    final compact = text.trim();

    if (_isFieldLabelOnly(compact)) return null;

    final departmentRegex = RegExp(
      r'^[가-힣A-Za-z0-9]{2,20}(팀|부|실|과|센터|본부)$',
    );

    if (!departmentRegex.hasMatch(compact)) return null;

    return _TextSpanResult(
      value: compact,
      start: 0,
      end: compact.length,
    );
  }

  static _TextSpanResult? _extractPositionSpan(String text) {
    final compact = text.trim();

    if (_isFieldLabelOnly(compact)) return null;

    final positions = [
      '인턴',
      '사원',
      '주임',
      '대리',
      '과장',
      '차장',
      '부장',
      '팀장',
      '실장',
      '본부장',
      '대표',
      '대표이사',
      '이사',
      '상무',
      '전무',
      '사장',
      '회장',
      '연구원',
      '선임',
      '책임',
      '수석',
    ];

    if (positions.contains(compact)) {
      return _TextSpanResult(
        value: compact,
        start: 0,
        end: compact.length,
      );
    }

    for (final position in positions) {
      final index = compact.indexOf(position);
      if (index >= 0 && compact.length <= 10) {
        return _TextSpanResult(
          value: position,
          start: index,
          end: index + position.length,
        );
      }
    }

    return null;
  }

  static List<_TextSpanResult> _extractNameSpans(String text) {
    final List<_TextSpanResult> results = [];
    final compact = text.trim();

    if (_isTitleOrSectionHeader(compact)) return results;
    if (_isTableHeader(compact)) return results;
    if (_isFieldLabelOnly(compact)) return results;
    if (_extractDepartmentSpan(compact) != null) return results;
    if (_extractCompanySpan(compact) != null) return results;
    if (_isGeneralDocumentTerm(compact)) return results;

    final patterns = [
      RegExp(r'대표이사\s*([가-힣]{2,4})'),
      RegExp(r'대표\s*([가-힣]{2,4})'),
      RegExp(r'본인\s*([가-힣]{2,4})'),
      RegExp(r'신청인\s*([가-힣]{2,4})'),
      RegExp(r'고객\s*([가-힣]{2,4})'),
      RegExp(r'배우자\s*([가-힣]{2,4})'),
      RegExp(r'직원은\s*([가-힣]{2,4})'),
      RegExp(r'담당자는\s*([가-힣]{2,4})'),
      RegExp(r'담당자\s*([가-힣]{2,4})'),
      RegExp(r'서명인[:：]?\s*([가-힣]{2,4})'),
      RegExp(r'수령인\s*([가-힣]{2,4})'),
      RegExp(r'받는\s*사람\s*([가-힣]{2,4})'),
      RegExp(r'보낸\s*사람\s*([가-힣]{2,4})'),
      RegExp(r'^([가-힣]{2,4})\s*(인턴|사원|주임|대리|과장|차장|부장|팀장|실장|본부장|대표|대표이사|이사|상무|전무|사장|회장|연구원|선임|책임|수석)$'),
    ];

    for (final regex in patterns) {
      for (final match in regex.allMatches(compact)) {
        final name = match.group(1);
        if (name == null) continue;
        if (!_isLikelyKoreanName(name)) continue;

        final fullMatch = match.group(0)!;
        final localIndex = fullMatch.indexOf(name);
        if (localIndex < 0) continue;

        final start = match.start + localIndex;
        final end = start + name.length;

        results.add(
          _TextSpanResult(
            value: name,
            start: start,
            end: end,
          ),
        );
      }
    }

    final plainName = _extractPlainKoreanName(compact);
    if (plainName != null) {
      results.add(plainName);
    }

    return results;
  }

  static _TextSpanResult? _extractPlainKoreanName(String text) {
    final compact = text.trim();

    if (_isFieldLabelOnly(compact)) return null;
    if (_extractDepartmentSpan(compact) != null) return null;
    if (_extractPositionSpan(compact) != null) return null;
    if (_extractCompanySpan(compact) != null) return null;
    if (_isGeneralDocumentTerm(compact)) return null;
    if (_looksLikeBuildingOrHousingName(compact)) return null;

    final match = RegExp(r'^([가-힣]{2,4})\s*(님|씨|\(인\)|\(서명\))?$')
        .firstMatch(compact);

    if (match == null) return null;

    final name = match.group(1);
    if (name == null) return null;
    if (!_isLikelyKoreanName(name)) return null;

    final start = compact.indexOf(name);
    final end = start + name.length;

    return _TextSpanResult(
      value: name,
      start: start,
      end: end,
    );
  }

  static bool _isGeneralDocumentTerm(String text) {
    final compact = text.replaceAll(' ', '');

    final terms = [
      '사무국장',
      '공동',
      '다음',
      '우대요건',
      '자격요건',
      '해당하는사람',
      '채용분야',
      '담당업무',
      '인원',
      '구분',
      '관련분야',
      '영어가능자',
      '경력이있는자',
      '이상인자',
      '유입',
      '신규',
      '고객',
      '브랜드',
      '이미지',
      '강화',
      '프로젝트',
      '목적',
      '기간',
      '오전',
      '오후',
      '새벽',
      '배송',
      '택배',
      '운송',
      '문앞',
      '문앞배송',
      '공동현관',
      '출입번호',
      '개인정보',
      '보호',
      '주문번',
      '주문번호',
      '보내는이',
      '받는이',
      '내는이',
    ];

    if (terms.contains(compact)) return true;

    if (compact.endsWith('요건')) return true;
    if (compact.endsWith('업무')) return true;
    if (compact.endsWith('분야')) return true;

    return false;
  }

  static bool _isLikelyKoreanName(String text) {
    if (text.length < 2 || text.length > 4) return false;

    final blacklist = [
      '정보',
      '신청',
      '서비스',
      '고객',
      '금융',
      '추가',
      '인증',
      '담당',
      '직원',
      '귀하',
      '문의',
      '등록',
      '처리',
      '번호',
      '연락',
      '연락처',
      '이메일',
      '메일',
      '전화',
      '전화번호',
      '주소',
      '내용',
      '항목',
      '이름',
      '성명',
      '생년월일',
      '계좌번호',
      '주민등록번호',
      '주민번호',
      '여권번호',
      '면허번호',
      '운전면허번호',
      '카드번호',
      '서명인',
      '서명일자',
      '회사명',
      '소속',
      '직책',
      '마케팅',
      '마케팅팀',
      '개발팀',
      '인사팀',
      '총무팀',
      '영업팀',
      '보안팀',
      '기획팀',
      '디자인팀',
      '사원',
      '주임',
      '대리',
      '과장',
      '차장',
      '부장',
      '팀장',
      '대표',
      '이사',
      '상무',
      '전무',
      '회장',
      '사무국장',
      '공동',
      '다음',
      '우대요건',
      '자격요건',
      '유입',
      '신규',
      '브랜드',
      '이미지',
      '강화',
      '프로젝트',
      '목적',
      '기간',
      '오전',
      '오후',
      '새벽',
      '배송',
      '택배',
      '운송',
      '문앞',
      '문앞배송',
      '공동현관',
      '출입번호',
      '개인정보',
      '보호',
      '주문번',
      '주문번호',
      '보내는이',
      '받는이',
      '내는이',
    ];

    if (blacklist.contains(text)) return false;

    if (text.endsWith('팀')) return false;
    if (text.endsWith('부')) return false;
    if (text.endsWith('실')) return false;
    if (text.endsWith('장')) return false;
    if (text.endsWith('요건')) return false;

    if (text.endsWith('공사')) return false;
    if (text.endsWith('공단')) return false;
    if (text.endsWith('재단')) return false;
    if (text.endsWith('협회')) return false;
    if (text.endsWith('조합')) return false;
    if (text.endsWith('기관')) return false;
    if (text.endsWith('추진단')) return false;
    if (text.endsWith('연구원')) return false;
    if (text.endsWith('대학교')) return false;
    if (text.endsWith('병원')) return false;

    if (!_hasLikelyKoreanSurname(text)) return false;

    return RegExp(r'^[가-힣]{2,4}$').hasMatch(text);
  }

  static bool _hasLikelyKoreanSurname(String text) {
    if (text.isEmpty) return false;

    final cleaned = text.replaceAll(RegExp(r'[\*＊xX]'), '');
    if (cleaned.isEmpty) return false;

    final surnames = [
      '김',
      '이',
      '박',
      '최',
      '정',
      '강',
      '조',
      '윤',
      '장',
      '임',
      '한',
      '오',
      '서',
      '신',
      '권',
      '황',
      '안',
      '송',
      '전',
      '홍',
      '유',
      '고',
      '문',
      '양',
      '손',
      '배',
      '백',
      '허',
      '남',
      '심',
      '노',
      '하',
      '곽',
      '성',
      '차',
      '주',
      '우',
      '구',
      '민',
      '류',
      '나',
      '진',
    ];

    return surnames.contains(cleaned[0]);
  }

  static final RegExp _rrnRegex = RegExp(
    r'[0-9]{6}[-]?[1-4][0-9]{6}',
  );

  static final RegExp _partialRrnRegex = RegExp(
    r'[0-9]{6}',
  );

  static final RegExp _phoneRegex = RegExp(
    r'01[016789][-]?\d{3,4}[-]?\d{4}',
  );

  static final RegExp _emailRegex = RegExp(
    r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
    caseSensitive: false,
  );

  static final RegExp _cardRegex = RegExp(
    r'(?:[0-9]{4}[-]?){3}[0-9]{4}',
  );

  static final RegExp _accountRegex = RegExp(
    r'[0-9]{2,6}[-][0-9]{2,6}[-][0-9]{4,8}',
  );

  static final RegExp _waybillCodeRegex = RegExp(
    r'[0-9A-Za-z]{4}[-][0-9A-Za-z]{4}[-][0-9A-Za-z]{4}',
  );

  static final RegExp _passportRegex = RegExp(
    r'[A-Z][0-9]{8}',
  );

  static final RegExp _driverLicenseRegex = RegExp(
    r'[0-9]{2}[-]?[0-9]{2}[-]?[0-9]{6}[-]?[0-9]{2}',
  );

  static final RegExp _dateRegex = RegExp(
    r'(19|20)[0-9]{2}[-./][0-9]{1,2}[-./][0-9]{1,2}',
  );

  static List<PrivacyItem> _removeDuplicates(List<PrivacyItem> items) {
    final seen = <String>{};
    final unique = <PrivacyItem>[];

    for (final item in items) {
      final rect = item.rect;
      final key =
          '${item.type}_${item.text}_${rect?.left.toStringAsFixed(1)}_${rect?.top.toStringAsFixed(1)}_${rect?.right.toStringAsFixed(1)}_${rect?.bottom.toStringAsFixed(1)}';

      if (!seen.contains(key)) {
        seen.add(key);
        unique.add(item);
      }
    }

    return unique;
  }
}

class _DetectedSpan {
  final String type;
  final String text;
  final Rect rect;
  final List<Offset>? polygon;
  final String confidence;
  final String lineText;
  final int start;
  final int end;

  _DetectedSpan({
    required this.type,
    required this.text,
    required this.rect,
    required this.polygon,
    required this.confidence,
    required this.lineText,
    required this.start,
    required this.end,
  });

  PrivacyItem toPrivacyItem() {
    return PrivacyItem(
      type: type,
      text: text,
      rect: rect,
      confidence: confidence,
      polygon: polygon,
    );
  }
}

class _TextSpanResult {
  final String value;
  final int start;
  final int end;

  _TextSpanResult({
    required this.value,
    required this.start,
    required this.end,
  });
}