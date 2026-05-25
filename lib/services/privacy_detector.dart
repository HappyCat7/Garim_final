import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/privacy_item.dart';

class PrivacyDetector {
  static List<PrivacyItem> detect(List<TextLine> lines) {
    final List<_DetectedSpan> spans = [];

    // 문서 전체가 운송장/택배 양식이면, 이름/등기번호/주문번호 등
    // 일부 항목이 개별 줄에서 문맥 키워드 없이 떨어져 OCR 되어도 탐지할 수 있게 한다.
    final bool globalWaybillContext = lines.any(
          (line) => _isWaybillContext(line.text.trim()),
    );

    // 여권은 일부가 잘려 있거나 확대된 이미지에서도 Passport No, KOR, MRZ 등
    // 고정 키워드/형태가 남아있는 경우가 많으므로 전체 OCR 기준 문맥을 먼저 판단한다.
    final bool globalPassportContext = _isPassportContext(lines);

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final rawText = line.text.trim();

      if (rawText.isEmpty) continue;
      if (_isTitleOrSectionHeader(rawText)) continue;
      if (_isTableHeader(rawText)) continue;

      final labelType = _labelType(rawText);
      final bool currentLineWaybillContext =
          _isWaybillContext(rawText) || globalWaybillContext;

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
        avoidOverlapTypes: {
          'RRN',
          'PARTIAL_RRN',
        },
      );

      _addRegexMatches(
        spans: spans,
        line: line,
        regex: _passportRegex,
        type: 'PASSPORT_NUMBER',
        confidence: globalPassportContext ? 'HIGH' : 'MEDIUM',
        avoidOverlapTypes: {
          'RRN',
          'DRIVER_LICENSE',
        },
      );

      if (globalPassportContext || _looksLikePassportLine(rawText)) {
        _addPassportSpecificSpans(
          spans: spans,
          line: line,
          isGlobalPassportContext: globalPassportContext,
        );
      }

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

      // 등기번호는 계좌번호와 형태가 비슷하므로 계좌번호보다 먼저 분리한다.
      if (_hasRegisterNumberContext(rawText)) {
        _addRegexMatches(
          spans: spans,
          line: line,
          regex: _registerNumberRegex,
          type: 'REGISTER_NUMBER',
          confidence: 'MEDIUM',
          avoidOverlapTypes: {
            'PHONE',
            'CARD_NUMBER',
            'ACCOUNT_NUMBER',
            'WAYBILL_CODE',
          },
        );
      }

      // 주문번호는 같은 줄에 "주문번호 : 3907981 099519925" 형태로 붙어 나오는 경우가 많다.
      // 일반 숫자/계좌번호 패턴과 섞이지 않도록 주문번호 라벨 뒤 값만 별도 탐지한다.
      final inlineOrderNumber = _extractInlineOrderNumberSpan(rawText);
      if (inlineOrderNumber != null) {
        _addManualSpan(
          spans: spans,
          line: line,
          span: inlineOrderNumber,
          type: 'WAYBILL_ORDER_NUMBER',
          confidence: 'MEDIUM',
        );
      }

      // 운송장 문서에서는 바코드/등기번호/운송장번호가 계좌번호 형태로 오탐될 수 있어
      // 계좌번호 키워드가 있을 때만 계좌번호로 인정한다.
      if (_hasAccountContext(rawText) ||
          (!currentLineWaybillContext && _looksLikeAccountOnly(rawText))) {
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
            'REGISTER_NUMBER',
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
          type: 'NAME',
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

    if (globalPassportContext) {
      _addPassportContextualFields(spans: spans, lines: lines);
    }

    return _removeDuplicates(
      _applyPriorityRules(
        spans.map((e) => e.toPrivacyItem()).toList(),
      ),
    );
  }

  static _TextSpanResult? _extractInlineOrderNumberSpan(String text) {
    final compact = text.trim();

    if (!compact.replaceAll(' ', '').contains('주문번호') &&
        !compact.replaceAll(' ', '').contains('주문번')) {
      return null;
    }

    final match = RegExp(
      r'(주문번호|주문번)\s*[:：]?\s*([0-9][0-9\s,\-]{5,30}[0-9])',
    ).firstMatch(compact);

    if (match == null) return null;

    final value = match.group(2);
    if (value == null) return null;

    final normalized = value.replaceAll(RegExp(r'[^0-9]'), '');

    // 주문번호는 서비스마다 길이가 다르므로 너무 짧은 숫자만 제외한다.
    if (normalized.length < 8 || normalized.length > 24) {
      return null;
    }

    final start = match.start + match.group(0)!.indexOf(value);
    final end = start + value.length;

    return _TextSpanResult(
      value: value.trim(),
      start: start,
      end: end,
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


  static bool _isPassportContext(List<TextLine> lines) {
    int score = 0;

    for (final line in lines) {
      final compact = _normalizePassportText(line.text);
      final mrzCompact = _normalizeMrzText(line.text);

      if (compact.contains('PASSPORT')) score += 3;
      if (compact.contains('여권')) score += 3;
      if (compact.contains('PASSPORTNO')) score += 3;
      if (compact.contains('PERSONALNO')) score += 2;
      if (compact.contains('주민등록번호')) score += 2;
      if (compact.contains('NATIONALITY')) score += 2;
      if (compact.contains('DATEOFBIRTH')) score += 2;
      if (compact.contains('DATEOFISSUE')) score += 1;
      if (compact.contains('DATEOFEXPIRY')) score += 1;
      if (compact.contains('KOR')) score += 1;
      if (compact.contains('REPUBLICOFKOREA')) score += 3;
      if (_isPassportMrzLine(mrzCompact)) score += 4;
      if (_passportRegex.hasMatch(compact)) score += 2;
    }

    return score >= 5;
  }

  static bool _looksLikePassportLine(String text) {
    final compact = _normalizePassportText(text);
    final mrzCompact = _normalizeMrzText(text);

    return compact.contains('PASSPORT') ||
        compact.contains('여권') ||
        compact.contains('PERSONALNO') ||
        compact.contains('NATIONALITY') ||
        compact.contains('NTIONALITY') ||
        compact.contains('DATEOFBIRTH') ||
        compact.contains('OFBIRTH') ||
        compact.contains('DATEOFISSUE') ||
        compact.contains('ISSUE') ||
        compact.contains('LSSUE') ||
        compact.contains('DATEOFEXPIRY') ||
        compact.contains('EXPIRY') ||
        compact.contains('PIY') ||
        compact.contains('REPUBLICOFKOREA') ||
        compact.contains('ASSORTNO') ||
        compact.contains('PASSPORTNO') ||
        _isPassportMrzLine(mrzCompact) ||
        _passportRegex.hasMatch(compact);
  }

  static void _addPassportSpecificSpans({
    required List<_DetectedSpan> spans,
    required TextLine line,
    required bool isGlobalPassportContext,
  }) {
    final text = line.text.trim();
    if (text.isEmpty) return;

    final compact = _normalizePassportText(text);
    final mrzCompact = _normalizeMrzText(text);

    // MRZ는 이름, 여권번호, 국적, 생년월일, 성별, 개인번호 등이 압축된 영역이므로
    // 한 줄 전체를 민감한 여권 개인정보 영역으로 잡는다.
    if (_isPassportMrzLine(mrzCompact)) {
      _addManualSpan(
        spans: spans,
        line: line,
        span: _TextSpanResult(
          value: text,
          start: 0,
          end: text.length,
        ),
        type: 'PASSPORT_MRZ',
        confidence: 'HIGH',
      );
      return;
    }

    if (!isGlobalPassportContext) return;

    final personalNo = _extractPassportPersonalNumberSpan(text);
    if (personalNo != null) {
      _addManualSpan(
        spans: spans,
        line: line,
        span: personalNo,
        type: 'PASSPORT_PERSONAL_NUMBER',
        confidence: 'HIGH',
      );
    }

    final passportDate = _extractPassportDateSpan(text);
    if (passportDate != null) {
      _addManualSpan(
        spans: spans,
        line: line,
        span: passportDate,
        type: 'PASSPORT_DATE',
        confidence: 'MEDIUM',
      );
    }

    final englishName = _extractPassportEnglishNameSpan(text);
    if (englishName != null) {
      _addManualSpan(
        spans: spans,
        line: line,
        span: englishName,
        type: 'PASSPORT_NAME',
        confidence: 'MEDIUM',
      );
    }

    final koreanName = _extractPassportKoreanNameSpan(text);
    if (koreanName != null) {
      _addManualSpan(
        spans: spans,
        line: line,
        span: koreanName,
        type: 'NAME',
        confidence: 'MEDIUM',
      );
    }
  }


  static bool _isPassportMrzLine(String normalizedText) {
    if (!_mrzRegex.hasMatch(normalizedText)) return false;

    // MRZ는 반드시 '<'가 많이 포함되거나, 여권번호+국가코드+생년월일+성별+만료일이
    // 압축된 두 번째 줄 구조를 가져야 한다.
    // MINISTRY OF FOREIGN AFFAIRS 같은 긴 영문 기관명이 MRZ로 오탐되는 것을 방지한다.
    final hasMrzSeparator = normalizedText.contains('<');
    final looksFirstLine = normalizedText.startsWith('P') &&
        normalizedText.contains('KOR') &&
        hasMrzSeparator;

    final looksSecondLine = RegExp(
      r'^[A-Z0-9]{8,9}[0-9][A-Z]{3}[0-9]{6}[0-9]?[MF<]',
    ).hasMatch(normalizedText);

    return looksFirstLine || looksSecondLine;
  }

  static String _normalizePassportText(String text) {
    return text
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('〈', '<')
        .replaceAll('《', '<')
        .replaceAll('«', '<')
        .replaceAll('‹', '<')
        .toUpperCase();
  }

  static String _normalizeMrzText(String text) {
    return text
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('〈', '<')
        .replaceAll('《', '<')
        .replaceAll('«', '<')
        .replaceAll('‹', '<')
        .replaceAll(' ', '')
        .toUpperCase();
  }

  static String _normalizePassportTextForDate(String text) {
    return text
        .toUpperCase()
        .replaceAll('I', '1')
        .replaceAll('L', '1')
        .replaceAll('O', '0');
  }

  static void _addPassportContextualFields({
    required List<_DetectedSpan> spans,
    required List<TextLine> lines,
  }) {
    for (int i = 0; i < lines.length; i++) {
      final labelLine = lines[i];
      final labelText = labelLine.text.trim();
      final labelKey = _normalizePassportText(labelText);

      final String? type = _passportLabelType(labelKey);
      if (type == null) continue;

      final valueLine = _findPassportValueLine(
        lines: lines,
        labelLine: labelLine,
        labelType: type,
      );

      if (valueLine == null) continue;

      final valueText = valueLine.text.trim();
      final span = _passportValueSpanForType(type, valueText);
      if (span == null) continue;

      _addManualSpan(
        spans: spans,
        line: valueLine,
        span: span,
        type: type,
        confidence: type == 'PASSPORT_NUMBER' || type == 'PASSPORT_PERSONAL_NUMBER'
            ? 'HIGH'
            : 'MEDIUM',
      );
    }
  }

  static String? _passportLabelType(String key) {
    if (key.contains('PASSPORTNO') || key.contains('ASSPORTNO') || key.contains('여권번호') || key.contains('여번')) {
      return 'PASSPORT_NUMBER';
    }
    if (key.contains('SURNAME')) return 'PASSPORT_NAME';
    if (key.contains('GIVEN') || key.contains('GIHN') || key.contains('G1HN') || key.contains('이름')) {
      return 'PASSPORT_NAME';
    }
    if (key.contains('BIRTH') || key.contains('0FBIRTH') || key.contains('OFBIRTH') || key.contains('생년월일')) {
      return 'BIRTH_DATE';
    }
    if (key.contains('NATIONALITY') || key.contains('NTIONALITY') || key.contains('국적')) {
      return 'PASSPORT_NATIONALITY';
    }
    if (key.contains('ISSUE') || key.contains('LSSUE') || key.contains('발급일')) {
      return 'PASSPORT_ISSUE_DATE';
    }
    if (key.contains('EXPIRY') || key.contains('PIRY') || key.contains('기간만') || key.contains('만료일')) {
      return 'PASSPORT_EXPIRY_DATE';
    }
    if (key.contains('PERSONALNO') || key.contains('주민등록번호') || key.contains('주민번호')) {
      return 'PASSPORT_PERSONAL_NUMBER';
    }
    return null;
  }

  static TextLine? _findPassportValueLine({
    required List<TextLine> lines,
    required TextLine labelLine,
    required String labelType,
  }) {
    final labelRect = labelLine.boundingBox;
    final candidates = <_TableValueCandidate>[];

    for (final candidate in lines) {
      if (candidate == labelLine) continue;

      final text = candidate.text.trim();
      if (text.isEmpty) continue;

      final rect = candidate.boundingBox;
      if (rect.top < labelRect.top - 2) continue;
      if (rect.top - labelRect.bottom > 32) continue;

      final horizontalOverlap = rect.right >= labelRect.left - 12 && rect.left <= labelRect.right + 90;
      final startsNearLabel = (rect.left - labelRect.left).abs() < 80;
      final isBelow = rect.center.dy > labelRect.center.dy;

      if (!isBelow || (!horizontalOverlap && !startsNearLabel)) continue;
      if (!_looksValidPassportValue(labelType, text)) continue;

      final dx = (rect.left - labelRect.left).abs();
      final dy = (rect.top - labelRect.bottom).abs();
      candidates.add(_TableValueCandidate(line: candidate, score: dy + dx * 0.03));
    }

    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => a.score.compareTo(b.score));
    return candidates.first.line;
  }

  static bool _looksValidPassportValue(String type, String text) {
    final trimmed = text.trim();
    final key = _normalizePassportText(trimmed);
    final mrz = _normalizeMrzText(trimmed);

    if (_passportLabelType(key) != null) return false;
    if (_isPassportMrzLine(mrz)) return false;

    switch (type) {
      case 'PASSPORT_NUMBER':
        return _passportRegex.hasMatch(key);
      case 'PASSPORT_NAME':
        return RegExp(r'^[A-Z][A-Z\s\-]{1,24}$').hasMatch(trimmed.toUpperCase()) ||
            _isLikelyKoreanName(trimmed.replaceAll(RegExp(r'\s+'), ''));
      case 'BIRTH_DATE':
      case 'PASSPORT_ISSUE_DATE':
      case 'PASSPORT_EXPIRY_DATE':
        return _extractPassportDateSpan(trimmed) != null;
      case 'PASSPORT_NATIONALITY':
        return key.contains('KOR') || key.contains('REPUBLICOFKOREA') || key.length >= 3;
      case 'PASSPORT_PERSONAL_NUMBER':
        return RegExp(r'^[0-9]{7}$').hasMatch(key);
      default:
        return false;
    }
  }

  static _TextSpanResult? _passportValueSpanForType(String type, String text) {
    final original = text.trim();
    if (original.isEmpty) return null;

    if (type == 'PASSPORT_NUMBER') {
      final match = _passportRegex.firstMatch(_normalizePassportText(original));
      if (match == null) return null;
      return _TextSpanResult(value: original, start: 0, end: original.length);
    }

    if (type == 'PASSPORT_NAME') {
      final english = _extractPassportEnglishNameSpan(original);
      if (english != null) return english;
      final korean = _extractPassportKoreanNameSpan(original);
      if (korean != null) return korean;
      return null;
    }

    if (type == 'BIRTH_DATE' || type == 'PASSPORT_ISSUE_DATE' || type == 'PASSPORT_EXPIRY_DATE') {
      return _extractPassportDateSpan(original);
    }

    if (type == 'PASSPORT_NATIONALITY') {
      return _TextSpanResult(value: original, start: 0, end: original.length);
    }

    if (type == 'PASSPORT_PERSONAL_NUMBER') {
      return _extractPassportPersonalNumberSpan(original);
    }

    return null;
  }

  static _TextSpanResult? _extractPassportPersonalNumberSpan(String text) {
    final compact = text.trim();

    // 한국 여권의 Personal No 영역은 예시처럼 7자리 숫자로 OCR 되는 경우가 많다.
    // 일반 문서에서는 위험하지만, 여권 문맥 안에서는 주민번호 뒷자리/개인번호로 처리한다.
    final match = RegExp(r'^[0-9]{7}$').firstMatch(compact);
    if (match == null) return null;

    return _TextSpanResult(
      value: compact,
      start: 0,
      end: compact.length,
    );
  }

  static _TextSpanResult? _extractPassportDateSpan(String text) {
    final original = text.trim();
    final normalized = _normalizePassportTextForDate(original);

    final looksLikePassportDate = RegExp(
      r'^[0-9]{1,2}.*(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC|월).*[0-9IOOL]{4}$',
    ).hasMatch(normalized);

    if (!looksLikePassportDate) return null;

    return _TextSpanResult(
      value: original,
      start: 0,
      end: original.length,
    );
  }

  static _TextSpanResult? _extractPassportEnglishNameSpan(String text) {
    final original = text.trim();
    final upper = original.toUpperCase();
    final compact = upper.replaceAll(RegExp(r'\s+'), '');

    if (!RegExp(r'^[A-Z][A-Z\s\-]{1,24}$').hasMatch(upper)) return null;

    final blacklist = {
      'PM',
      'M',
      'F',
      'KOR',
      'PMKOR',
      'PASSPORT',
      'REPUBLIC',
      'REPUBLICOFKOREA',
      'MINISTRY',
      'MINISSOF',
      'MINISTRYOFFOREIGNAFFAIRSANDTRADE',
      'MINISTRYOFFOREIGNAFFAIRS',
      'FOREIGNAFFAIRS',
      'AUTHORITY',
      'THORITY',
      'NATIONALITY',
      'NTIONALITY',
      'SURNAME',
      'GIVENNAMES',
      'GIHNAMES',
      'DATEOFBIRTH',
      'OFBIRTH',
      'DATEOFISSUE',
      'WDATEOFISSUE',
      'DATEOFEXPIRY',
    };

    if (blacklist.contains(compact)) return null;
    if (compact.length < 2 || compact.length > 24) return null;
    if (compact.contains('DATE') || compact.contains('ISSUE')) return null;
    if (compact.contains('BIRTH') || compact.contains('NATIONAL')) return null;
    if (compact.contains('FOREIGN') || compact.contains('AFFAIRS')) return null;

    return _TextSpanResult(
      value: original,
      start: 0,
      end: original.length,
    );
  }

  static _TextSpanResult? _extractPassportKoreanNameSpan(String text) {
    final compact = text.trim().replaceAll(RegExp(r'\s+'), '');

    if (!_isLikelyKoreanName(compact)) return null;

    final start = text.indexOf(compact);

    return _TextSpanResult(
      value: compact,
      start: start < 0 ? 0 : start,
      end: start < 0 ? text.length : start + compact.length,
    );
  }

  static bool _isWaybillContext(String text) {
    final compact = text.replaceAll(' ', '').toUpperCase();

    return compact.contains('CJ') ||
        compact.contains('대한통운') ||
        compact.contains('우체국') ||
        compact.contains('접수국') ||
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
        compact.contains('주문번호') ||
        compact.contains('주문처') ||
        compact.contains('고객주문처') ||
        compact.contains('등기번호') ||
        compact.contains('받는분') ||
        compact.contains('보내는분');
  }

  static _TextSpanResult? _extractWaybillNameSpan(
      String text, {
        required bool isWaybillContext,
      }) {
    final compact = text.trim();
    final nameCandidateText = compact
        .replaceFirst(RegExp(r'^\([0-9]+/[0-9]+\)\s*'), '')
        .trim();

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
      '성과분석',
      '주간보고',
      '월간보고',
      '광고운영',
      '콘텐츠제작',
      'SNS운영',
      '업무내용',
      '지급조건',
      '계약개요',
      '계좌번호',
      '생년월일',
      '주민번호',
      '주민등록번호',
    };

    if (blacklist.contains(compact) || blacklist.contains(nameCandidateText)) {
      return null;
    }

    // OCR이 마스킹 문자를 *, x 뿐 아니라 O/0/ㅇ/○/●처럼 잘못 읽는 경우를 보완한다.
    // 예: 임*진, 임진O0, 김플*, 이O영 등
    final maskedMatch = RegExp(
      r'^([가-힣]{1,3}[\*＊xXoO0ㅇ○●•]{1,2}[가-힣]{0,2}|[가-힣]{1,2}[\*＊xXoO0ㅇ○●•]{1,2}[가-힣]{1,2})$',
    ).firstMatch(nameCandidateText);

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

    final plainMatch = RegExp(r'^([가-힣]{2,4})$').firstMatch(nameCandidateText);
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

    final valueLine = _findTableValueLine(
      lines: lines,
      labelLine: labelLine,
      labelType: labelType,
    );

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
          type: 'NAME',
          confidence: 'MEDIUM',
        );
      } else {
        final names = _extractNameSpans(
          valueText,
          allowPlainName: true,
        );
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
          'REGISTER_NUMBER',
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

  static TextLine? _findTableValueLine({
    required List<TextLine> lines,
    required TextLine labelLine,
    required String labelType,
  }) {
    final labelRect = labelLine.boundingBox;
    final candidates = <_TableValueCandidate>[];

    for (final candidate in lines) {
      if (candidate == labelLine) continue;

      final rect = candidate.boundingBox;
      final text = candidate.text.trim();
      if (text.isEmpty) continue;
      if (_isFieldLabelOnly(text)) continue;
      if (_isTitleOrSectionHeader(text)) continue;
      if (_isTableHeader(text)) continue;

      // 표가 기울어진 사진에서는 같은 행의 값이 라벨보다 위/아래로 20~40px 정도 어긋난다.
      // 기존 sameRow < 18 조건은 김지은 같은 담당자 값을 놓쳤으므로,
      // 라벨 오른쪽에 있고 세로 중심이 가까운 후보를 점수화해서 선택한다.
      final isRightSide = rect.left > labelRect.right + 20;
      if (!isRightSide) continue;

      final dx = rect.left - labelRect.right;
      if (dx > 460) continue;

      final dy = (rect.center.dy - labelRect.center.dy).abs();
      if (dy > 55) continue;

      if (!_looksValidValueForLabel(labelType, text)) continue;

      // 같은 행에 가까울수록 우선, 너무 먼 오른쪽 값보다 바로 옆 값을 우선.
      final score = dy + (dx * 0.08);
      candidates.add(_TableValueCandidate(line: candidate, score: score));
    }

    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => a.score.compareTo(b.score));
    return candidates.first.line;
  }

  static bool _looksValidValueForLabel(String labelType, String text) {
    final compact = text.trim();
    if (compact.isEmpty) return false;

    switch (labelType) {
      case 'NAME':
        if (_extractWaybillNameSpan(
          compact,
          isWaybillContext: _isWaybillContext(compact),
        ) !=
            null) {
          return true;
        }
        return _extractNameSpans(compact, allowPlainName: true).isNotEmpty;

      case 'COMPANY':
        return _extractCompanySpan(compact) != null;

      case 'DEPARTMENT':
        return _extractDepartmentSpan(compact) != null;

      case 'POSITION':
        return _extractPositionSpan(compact) != null;

      case 'PHONE':
        return _phoneRegex.hasMatch(compact);

      case 'EMAIL':
        return _emailRegex.hasMatch(compact);

      case 'ADDRESS':
        return _extractAddressSpan(compact) != null;

      case 'RRN':
        return _rrnRegex.hasMatch(compact) || _partialRrnRegex.hasMatch(compact);

      case 'ACCOUNT_NUMBER':
        return _accountRegex.hasMatch(compact);

      case 'BIRTH_DATE':
        return _dateRegex.hasMatch(compact);

      default:
        return true;
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
        'WAYBILL_CODE',
        'WAYBILL_ORDER_NUMBER',
        'REGISTER_NUMBER',
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
      '성과분석',
      '주간보고',
      '월간보고',
      '광고운영',
      '콘텐츠제작',
      'SNS운영',
      '업무내용',
      '지급조건',
      '계약개요',
      '위탁업무내용',
    ];

    return labels.contains(compact);
  }

  static String? _labelType(String text) {
    final compact = text.replaceAll(' ', '');

    // OCR이 표 라벨을 한 글자씩 분리하는 경우 보완.
    // 예: '성' + '명:' 이 각각 다른 TextLine으로 분리되면 기존 '성명' 라벨 탐지가 실패한다.
    // 이때 값 영역 오른쪽의 이름을 찾기 위해 '명:' 단독 라인도 NAME 라벨로 인정한다.
    if (compact == '이름' ||
        compact == '성명' ||
        compact == '명:' ||
        compact == '명：' ||
        compact == '서명인' ||
        compact == '담당자' ||
        compact.contains('주문인') ||
        compact.contains('구문인') ||
        compact.contains('주문처') ||
        compact.contains('수령인') ||
        compact.contains('받는분') ||
        compact.contains('받는사람')) {
      return 'NAME';
    }

    if (compact.contains('회사명')) return 'COMPANY';
    if (compact == '소속' || compact == '속:' || compact == '속：') {
      return 'DEPARTMENT';
    }
    if (compact == '직책' || compact == '책:' || compact == '책：') {
      return 'POSITION';
    }

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

  static bool _hasRegisterNumberContext(String text) {
    final compact = text.replaceAll(' ', '');

    return compact.contains('등기번호') ||
        compact.contains('등기') ||
        compact.contains('송장번호') ||
        compact.contains('운송장번호');
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

  static bool _hasAddressCoreToken(String compact) {
    if (compact.isEmpty) return false;

    // 실제 주소를 구성하는 핵심 토큰만 허용한다.
    // 일반 문서 용어(성과분석, 월간보고 등)가 주소로 잡히는 것을 방지하기 위한 화이트리스트다.
    return RegExp(
      r'(특별시|광역시|[가-힣]{1,10}시|[가-힣]{1,10}군|[가-힣]{1,10}구|[가-힣]{1,10}읍|[가-힣]{1,10}면|[가-힣]{1,10}동|[가-힣]{1,10}리|[0-9]+로|[0-9]+길|[0-9]+번길|[0-9]+가길|[0-9]+번지|[0-9]+층|[0-9]+호|아파트|빌라|오피스텔|빌딩|주택|맨션|타운|하우스|마을|단지)',
    ).hasMatch(compact);
  }

  static String _normalizeAddressOcrCompact(String text) {
    var value = text.replaceAll(' ', '');

    // 행정구역명에서 자주 발생하는 OCR 오인식 보정.
    // 특정 샘플 값에만 의존하지 않고, 주소 판단용 문자열에만 적용한다.
    value = value.replaceFirst(RegExp(r'^1안시'), '천안시');
    value = value.replaceFirst(RegExp(r'^치안시'), '천안시');
    value = value.replaceFirst(RegExp(r'^전안시'), '천안시');
    value = value.replaceAll('동남구', '동남구');

    return value;
  }

  static _TextSpanResult? _extractAddressSpan(String text) {
    final compact = _normalizeAddressOcrCompact(text);

    if (_isNonAddressSentence(compact)) return null;

    // 주소 탐지 화이트리스트 강화:
    // 주소 핵심 토큰이 전혀 없으면 주소 후보에서 제외한다.
    // 단, 괄호형 상세주소는 아래 별도 정규식에서 다시 검사한다.
    final bool hasAddressCoreToken = _hasAddressCoreToken(compact);

    // 운송장/주소에서 보조 주소가 "(당주동 15-7)" 또는
    // "| (당주동 15-7)"처럼 별도 라인으로 인식되는 경우를 주소로 탐지한다.
    final parenthesizedDongDetailRegex = RegExp(
      r'^[\|\s]*\(?[가-힣]{1,10}(동|읍|면|리)\s*[0-9]{1,5}[-]?[0-9]{0,5}\)?$',
    );

    if (parenthesizedDongDetailRegex.hasMatch(compact)) {
      final cleaned = text.replaceAll('|', '').trim();
      final start = text.indexOf(cleaned);

      return _TextSpanResult(
        value: cleaned,
        start: start < 0 ? 0 : start,
        end: start < 0 ? text.length : start + cleaned.length,
      );
    }

    if (!hasAddressCoreToken) return null;

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

    // 예: OCR이 '천안시'를 '1안시'로 읽거나,
    // '동남구 병천면 가전 14'처럼 읍/면/구 + 마을/번지 형태만 남는 상세 주소 보완.
    final hasAdminAddressUnit = RegExp(
      r'([가-힣0-9]{1,10}시|[가-힣0-9]{1,10}군|[가-힣0-9]{1,10}구|[가-힣0-9]{1,10}읍|[가-힣0-9]{1,10}면|[가-힣0-9]{1,10}동|[가-힣0-9]{1,10}리)',
    ).allMatches(compact).length >= 2;

    final hasVillageLikeDetail = RegExp(
      r'[가-힣]{1,12}[0-9]{1,5}([,-]?[0-9]{1,5})?',
    ).hasMatch(compact);

    if (hasAdminAddressUnit && hasDigit && hasVillageLikeDetail) {
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

    final inlineDetailAddressRegex = RegExp(
      r'^[0-9]{1,5}\s*\([가-힣0-9]{1,12}(동|읍|면|리|가)\)\s*[0-9]{0,4}\s*(층|호)?[가-힣A-Za-z0-9\s]*$',
    );

    final parenthesizedDetailInsideLineRegex = RegExp(
      r'\([가-힣0-9]{1,12}(동|읍|면|리|가)\)',
    );

    if (inlineDetailAddressRegex.hasMatch(compact) ||
        (parenthesizedDetailInsideLineRegex.hasMatch(compact) &&
            RegExp(r'[0-9]').hasMatch(compact) &&
            RegExp(r'(층|호|빌딩|오토|센터|타워|상가|아파트|오피스텔)').hasMatch(compact))) {
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

  static List<_TextSpanResult> _extractNameSpans(
      String text, {
        bool allowPlainName = false,
      }) {
    final List<_TextSpanResult> results = [];
    final compact = text.trim();

    if (_isTitleOrSectionHeader(compact)) return results;
    if (_isTableHeader(compact)) return results;
    if (_isFieldLabelOnly(compact)) return results;
    if (_extractDepartmentSpan(compact) != null) return results;
    if (_extractCompanySpan(compact) != null) return results;
    if (_isGeneralDocumentTerm(compact)) return results;

    final patterns = [
      RegExp(r'(?:주문인|구문인|고객\s*주문처|주문처|수령인|받는\s*분|받는\s*사람|고객명|고객)\s*[:：]\s*([가-힣]{2,4}[\*＊xX]?)'),
      RegExp(r'대표이사\s*([가-힣]{2,4})'),
      RegExp(r'대표\s*([가-힣]{2,4})'),
      RegExp(r'본인\s*([가-힣]{2,4})'),
      RegExp(r'신청인\s*([가-힣]{2,4})'),
      RegExp(r'고객(?:명)?\s*[:：]\s*([가-힣]{2,4})'),
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

    if (allowPlainName || _hasNameHonorific(compact)) {
      final plainName = _extractPlainKoreanName(compact);
      if (plainName != null) {
        results.add(plainName);
      }
    }

    return results;
  }

  static bool _hasNameHonorific(String text) {
    final compact = text.trim();
    return RegExp(r'(님|씨|귀하|\(인\)|\(서명\))$').hasMatch(compact);
  }

  static _TextSpanResult? _extractPlainKoreanName(String text) {
    final original = text.trim();

    if (_isFieldLabelOnly(original)) return null;
    if (_extractDepartmentSpan(original) != null) return null;
    if (_extractPositionSpan(original) != null) return null;
    if (_extractCompanySpan(original) != null) return null;
    if (_isGeneralDocumentTerm(original)) return null;
    if (_looksLikeBuildingOrHousingName(original.replaceAll(' ', ''))) {
      return null;
    }

    // OCR이 운송장 이름을 "홍 길동님", "김 철수 님"처럼
    // 이름 내부 공백 포함 형태로 인식하는 경우를 보완한다.
    final spacedNameRegex = RegExp(
      r'^(([가-힣]\s*){2,4})(님|씨|귀하|\(인\)|\(서명\))?$',
    );

    final match = spacedNameRegex.firstMatch(original);
    if (match == null) return null;

    final rawNameWithSpaces = match.group(1);
    if (rawNameWithSpaces == null) return null;

    final normalizedName = rawNameWithSpaces.replaceAll(RegExp(r'\s+'), '');

    if (!_isLikelyKoreanName(normalizedName)) return null;

    final start = original.indexOf(rawNameWithSpaces);
    final end = start + rawNameWithSpaces.length;

    return _TextSpanResult(
      value: normalizedName,
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
      '성과분석',
      '주간보고',
      '월간보고',
      '광고운영',
      '콘텐츠제작',
      'SNS운영',
      '업무내용',
      '지급조건',
      '계약개요',
      '위탁업무내용',
    ];

    if (terms.contains(compact)) return true;

    if (compact.endsWith('요건')) return true;
    if (compact.endsWith('업무')) return true;
    if (compact.endsWith('분야')) return true;
    if (compact.endsWith('보고')) return true;
    if (compact.endsWith('분석')) return true;
    if (compact.endsWith('운영')) return true;
    if (compact.endsWith('제작')) return true;
    if (compact.endsWith('조건')) return true;

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
      '성과분석',
      '주간보고',
      '월간보고',
      '광고운영',
      '콘텐츠제작',
      'SNS운영',
      '업무내용',
      '지급조건',
      '계약개요',
      '위탁업무내용',
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

    final cleaned = text.replaceAll(RegExp(r'[\*＊xXoO0ㅇ○●•]'), '');
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

    final first = cleaned[0];
    if (surnames.contains(first)) return true;

    // OCR에서 성씨 한 글자가 형태가 비슷한 다른 음절로 깨지는 경우를 보완한다.
    // 예: 임 -> 얌/일/입/림, 김 -> 긷/깁, 이 -> 1/ㅣ처럼 일부 모델에서 오인식.
    // 여기서는 실제 표시 텍스트를 고치지 않고, 이름 후보 판정에만 보정값을 사용한다.
    final correctedFirst = _correctOcrSurname(first);
    if (correctedFirst == null) return false;

    return surnames.contains(correctedFirst);
  }

  static String? _correctOcrSurname(String char) {
    const corrections = {
      // 임씨 OCR 오인식 보정
      '얌': '임',
      '일': '임',
      '입': '임',
      '림': '임',

      // 김씨 OCR 오인식 보정
      '긷': '김',
      '깁': '김',
      '킴': '김',

      // 이씨 OCR 오인식 보정
      'ㅣ': '이',
      'l': '이',
      'I': '이',
      '1': '이',

      // 박/백 계열 오인식 보정
      '밖': '박',
      '빅': '박',
      '팩': '박',
      '맥': '백',

      // 최/쵀 계열 오인식 보정
      '쵀': '최',
      '체': '최',

      // 정/전/천 계열 오인식 보정
      '청': '정',
      '징': '정',
      '천': '전',

      // 홍/황 계열 오인식 보정
      '흥': '홍',
      '횽': '홍',
      '왕': '황',
    };

    return corrections[char];
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

  static final RegExp _registerNumberRegex = RegExp(
    r'[0-9]{2,6}[-][0-9]{3,5}[-][0-9]{3,6}',
  );

  static final RegExp _waybillCodeRegex = RegExp(
    r'[0-9A-Za-z]{4}[-][0-9A-Za-z]{4}[-][0-9A-Za-z]{4}',
  );

  static final RegExp _passportRegex = RegExp(
    // 한국 여권번호는 영문 1~2자 + 숫자/영문 혼합 7~8자 형태가 많다.
    // 예: SM0893652, M123A4567
    // 기존 [A-Z]{1,2}[A-Z0-9]{6,7} 패턴은 M123A4567처럼
    // 첫 글자 뒤에 숫자가 바로 오는 9자리 값을 놓칠 수 있어 보완했다.
    // REPUBLIC, PMKORHONG 같은 영문 단어/MRZ 일부 오탐 방지를 위해
    // 전체 길이 8~9자 + 숫자 1개 이상 조건은 유지한다.
    r'\b(?=[A-Z0-9]{8,9}\b)(?=[A-Z0-9]*[0-9])[A-Z]{1,2}[A-Z0-9]{7,8}\b',
  );

  static final RegExp _mrzRegex = RegExp(
    r'^[A-Z0-9<]{20,}$',
  );

  static final RegExp _driverLicenseRegex = RegExp(
    r'[0-9]{2}[-]?[0-9]{2}[-]?[0-9]{6}[-]?[0-9]{2}',
  );

  static final RegExp _dateRegex = RegExp(
    r'(19|20)[0-9]{2}[-./][0-9]{1,2}[-./][0-9]{1,2}',
  );

  static List<PrivacyItem> _applyPriorityRules(List<PrivacyItem> items) {
    final rrnItems = items.where((item) => item.type == 'RRN').toList();
    final mrzItems = items.where((item) => item.type == 'PASSPORT_MRZ').toList();

    final concretePassportDateItems = items.where((item) {
      return item.type == 'BIRTH_DATE' ||
          item.type == 'PASSPORT_ISSUE_DATE' ||
          item.type == 'PASSPORT_EXPIRY_DATE';
    }).toList();

    return items.where((item) {
      final itemRect = item.rect;

      // 1) 주민번호와 면허번호가 같은 영역에서 겹치면 주민번호를 우선한다.
      if (item.type == 'DRIVER_LICENSE') {
        if (itemRect == null) return true;

        for (final rrn in rrnItems) {
          final rrnRect = rrn.rect;
          if (rrnRect == null) continue;

          final sameLine = (itemRect.center.dy - rrnRect.center.dy).abs() < 12;
          final visuallyOverlaps = _rectOverlapRatio(itemRect, rrnRect) >= 0.45;
          final centerInsideRrn = rrnRect.inflate(6).contains(itemRect.center);

          if (sameLine && (visuallyOverlaps || centerInsideRrn)) {
            return false;
          }
        }
      }

      // 2) 여권번호 오탐 제거: REPUBLIC 같은 국가명/기관명은 여권번호가 아니다.
      if (item.type == 'PASSPORT_NUMBER') {
        final normalized = _normalizePassportText(item.text);

        if (!_passportRegex.hasMatch(normalized)) return false;
        if (!RegExp(r'[0-9]').hasMatch(normalized)) return false;

        final passportNumberBlacklist = {
          'REPUBLIC',
          'REPUBLICOFKOREA',
          'PMKORHONG',
          'MINISTRY',
          'FOREIGNAFFAIRS',
        };

        if (passportNumberBlacklist.contains(normalized)) return false;
      }

      // 3) 여권 하단 코드(MRZ)는 넓은 전체 줄을 유지한다.
      //    같은 줄 내부에서 잘려 생성된 여권번호/이름/날짜 세부 박스는 제거한다.
      //    단, 여권 상단의 실제 여권번호/이름/날짜는 MRZ와 위치가 달라서 유지된다.
      if (item.type != 'PASSPORT_MRZ' && itemRect != null) {
        for (final mrz in mrzItems) {
          final mrzRect = mrz.rect;
          if (mrzRect == null) continue;

          final sameMrzLine = (itemRect.center.dy - mrzRect.center.dy).abs() < 10;
          final insideMrz = _rectOverlapRatio(itemRect, mrzRect) >= 0.60 ||
              mrzRect.inflate(4).contains(itemRect.center);

          if (sameMrzLine && insideMrz) {
            return false;
          }
        }
      }

      // 4) PASSPORT_DATE는 임시/포괄 타입이다.
      //    같은 영역에 생년월일/발급일/만료일처럼 구체 타입이 있으면 구체 타입만 남긴다.
      if (item.type == 'PASSPORT_DATE' && itemRect != null) {
        for (final concrete in concretePassportDateItems) {
          final concreteRect = concrete.rect;
          if (concreteRect == null) continue;

          final sameLine = (itemRect.center.dy - concreteRect.center.dy).abs() < 8;
          final overlaps = _rectOverlapRatio(itemRect, concreteRect) >= 0.80;

          if (sameLine && overlaps) {
            return false;
          }
        }
      }

      // 5) 발급기관은 MRZ가 아니다. OCR에서 긴 영문 대문자 라인이 MRZ로 오탐될 수 있어 제외한다.
      if (item.type == 'PASSPORT_MRZ') {
        final normalized = _normalizeMrzText(item.text);
        if (!_isPassportMrzLine(normalized)) return false;
      }

      return true;
    }).toList();
  }

  static double _rectOverlapRatio(Rect a, Rect b) {
    final left = a.left > b.left ? a.left : b.left;
    final top = a.top > b.top ? a.top : b.top;
    final right = a.right < b.right ? a.right : b.right;
    final bottom = a.bottom < b.bottom ? a.bottom : b.bottom;

    if (right <= left || bottom <= top) return 0.0;

    final intersection = (right - left) * (bottom - top);
    final smallerArea = a.width * a.height < b.width * b.height
        ? a.width * a.height
        : b.width * b.height;

    if (smallerArea <= 0) return 0.0;
    return intersection / smallerArea;
  }

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


class _TableValueCandidate {
  final TextLine line;
  final double score;

  const _TableValueCandidate({
    required this.line,
    required this.score,
  });
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