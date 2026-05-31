import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/privacy_item.dart';

enum _IdCardType { none, resident, driver, student }

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

    // 졸업장/증명서류는 일반 문장보다 성명, 생년월일, 전공, 학교명, 총장명처럼
    // 라벨이 작게 찍히거나 OCR이 '성 명', '명 :홍 길동', '공 : 기계공학부'처럼
    // 분리되는 경우가 많으므로 문서 전체 문맥을 먼저 판단한다.
    final bool globalDiplomaContext = _isDiplomaContext(lines);

    // 주민등록증/운전면허증/학생증은 양식상 정보 위치가 비교적 고정적이다.
    // 먼저 신분증 종류를 문서 전체 OCR로 판별한 뒤, 라벨/정규식 탐지에 위치 보정을 더한다.
    final _IdCardType idCardType = _classifyIdCard(lines);

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
        avoidOverlapTypes: {
          'RRN',
          'PARTIAL_RRN',
        },
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

      if (globalDiplomaContext || _looksLikeDiplomaLine(rawText)) {
        _addDiplomaSpecificSpans(
          spans: spans,
          line: line,
          isGlobalDiplomaContext: globalDiplomaContext,
        );
      }

      if (idCardType != _IdCardType.none || _looksLikeIdCardLine(rawText)) {
        _addIdCardSpecificSpans(
          spans: spans,
          line: line,
          idCardType: idCardType,
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

      // 발급번호는 계좌번호와 유사한 하이픈 숫자 구조이지만,
      // 증명서/공문에서는 문서 식별번호이므로 계좌번호보다 먼저 분리한다.
      // 예: 발급번호 8553-345-3660-056
      if (_hasIssueNumberContext(rawText)) {
        _addRegexMatches(
          spans: spans,
          line: line,
          regex: _certificateIssueNumberRegex,
          type: 'CERTIFICATE_ISSUE_NUMBER',
          confidence: 'MEDIUM',
          avoidOverlapTypes: {
            'ACCOUNT_NUMBER',
            'PHONE',
            'CARD_NUMBER',
            'DRIVER_LICENSE',
            'RRN',
            'PARTIAL_RRN',
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
            'CERTIFICATE_ISSUE_NUMBER',
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
    _addCertificateIssueNumberFragments(spans: spans, lines: lines);

    if (idCardType != _IdCardType.none) {
      _addIdCardLayoutSpans(
        spans: spans,
        lines: lines,
        idCardType: idCardType,
      );
      _addBrokenIdCardAddressLayoutSpans(
        spans: spans,
        lines: lines,
        idCardType: idCardType,
      );
    }

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


  static void _addCertificateIssueNumberFragments({
    required List<_DetectedSpan> spans,
    required List<TextLine> lines,
  }) {
    for (final labelLine in lines) {
      final labelText = labelLine.text.trim();
      if (!_hasIssueNumberContext(labelText)) continue;

      final labelRect = labelLine.boundingBox;

      for (final candidateLine in lines) {
        if (candidateLine == labelLine) continue;

        final text = candidateLine.text.trim();
        if (text.isEmpty) continue;

        final rect = candidateLine.boundingBox;
        final dy = (rect.center.dy - labelRect.center.dy).abs();
        final dx = (rect.center.dx - labelRect.center.dx).abs();

        // 표 양식에서 라벨 아래 또는 바로 오른쪽에 발급번호가 위치하는 경우를 허용한다.
        final nearBelow = rect.top > labelRect.bottom && rect.top - labelRect.bottom < 120 && dx < 420;
        final nearRight = rect.left > labelRect.right && dx < 640 && dy < 80;
        if (!nearBelow && !nearRight) continue;

        for (final match in _certificateIssueNumberRegex.allMatches(text)) {
          final value = text.substring(match.start, match.end);

          final candidate = _DetectedSpan(
            type: 'CERTIFICATE_ISSUE_NUMBER',
            text: value,
            rect: _rectForTextSpan(
              line: candidateLine,
              start: match.start,
              end: match.end,
            ),
            polygon: _polygonForTextSpan(
              line: candidateLine,
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
              'ACCOUNT_NUMBER',
              'PHONE',
              'CARD_NUMBER',
              'DRIVER_LICENSE',
              'RRN',
              'PARTIAL_RRN',
            },
          )) {
            continue;
          }

          spans.add(candidate);
        }
      }
    }
  }





  static bool _looksLikeResidentCardTitleOcr(String compact) {
    final value = compact.replaceAll(RegExp(r'[^가-힣]'), '');
    if (value.contains('주민등록증')) return true;

    // 주민등록증 제목은 기울어지거나 흐리면 "주민등목증", "주민등륵증"처럼
    // 중간 글자가 틀어지는 경우가 많다. 제목 판별에만 쓰고 개인정보 값에는 쓰지 않는다.
    return RegExp(r'주민[가-힣]{1,3}증').hasMatch(value) &&
        (value.contains('등') || value.contains('등록') || value.contains('목') || value.contains('록'));
  }

  static String _cleanKoreanNameCandidate(String text) {
    var value = text.trim();
    value = value.replaceAll(RegExp(r'\([^)]*\)'), '');
    value = value.replaceAll(RegExp(r'[\[\]{}<>:：,\.·ㆍ\-_/\\|0-9A-Za-z]'), '');
    value = value.replaceAll(RegExp(r'\s+'), '');
    return value;
  }

  static _IdCardType _classifyIdCard(List<TextLine> lines) {
    int residentScore = 0;
    int driverScore = 0;
    int studentScore = 0;

    for (final line in lines) {
      final compact = line.text.replaceAll(RegExp(r'\s+'), '').toUpperCase();

      if (_looksLikeResidentCardTitleOcr(compact)) residentScore += 6;
      if (compact.contains('주민등록번호') || compact.contains('주민번호')) residentScore += 2;
      if (compact.contains('행정안전부') || compact.contains('정부24')) residentScore += 2;
      if (compact.contains('대한민국')) residentScore += 1;
      if (compact.contains('발급일') || compact.contains('주소')) residentScore += 1;

      // 운전면허증 제목은 촬영 각도/흔들림 때문에
      // "자동차운전면허종", "Divers Licse"처럼 깨지는 경우가 많다.
      // 따라서 정확한 "운전면허증"뿐 아니라 "운전면허" 핵심어와
      // 영문 Driver/License OCR 오인식까지 함께 사용해 유형을 판별한다.
      if (compact.contains('운전면허증') || compact.contains('자동차운전면허증')) driverScore += 6;
      if (compact.contains('운전면허') || compact.contains('자동차운전면허')) driverScore += 5;
      if (compact.contains('운전면허번호') || compact.contains('면허번호')) driverScore += 3;
      if (compact.contains('DRIVER') || compact.contains('DIVERS') || compact.contains('LICENSE') || compact.contains('LICENCE') || compact.contains('LICSE')) driverScore += 2;
      if (_driverLicenseRegex.hasMatch(line.text)) driverScore += 4;
      if (compact.contains('적성검사') || compact.contains('갱신기간')) driverScore += 2;
      if (compact.contains('경찰청') || compact.contains('도로교통공단')) driverScore += 2;
      if (RegExp(r'^[12]종').hasMatch(compact)) driverScore += 2;

      if (compact.contains('학생증')) studentScore += 6;
      if (compact.contains('학번')) studentScore += 3;
      if (compact.contains('학과') || compact.contains('전공') || compact.contains('소속')) studentScore += 2;
      if (compact.contains('대학교') || compact.contains('대학')) studentScore += 2;
      if (compact.contains('한국기술교육대학교') || compact.contains('KOREAUNIVERSITYOFTECHNOLOGYANDEDUCATION')) studentScore += 4;
      if (compact.contains('SHINHANCARD') || compact.contains('CHECK&DEBIT') || compact.contains('C20')) studentScore += 1;
      if (compact.contains('전자') || compact.contains('통신공학부') || compact.contains('공학부')) studentScore += 1;
      if (compact.contains('유효기간') || compact.contains('VALIDTHRU')) studentScore += 1;
    }

    if (driverScore >= 6 && driverScore >= residentScore && driverScore >= studentScore) {
      return _IdCardType.driver;
    }
    if (residentScore >= 6 && residentScore >= studentScore) {
      return _IdCardType.resident;
    }
    if (studentScore >= 6) {
      return _IdCardType.student;
    }

    return _IdCardType.none;
  }

  static bool _looksLikeIdCardLine(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), '').toUpperCase();

    return _looksLikeResidentCardTitleOcr(compact) ||
        compact.contains('주민등록번호') ||
        compact.contains('주민번호') ||
        compact.contains('운전면허증') ||
        compact.contains('운전면허') ||
        compact.contains('자동차운전면허') ||
        compact.contains('DRIVER') ||
        compact.contains('DIVERS') ||
        compact.contains('LICENSE') ||
        compact.contains('LICSE') ||
        compact.contains('운전면허번호') ||
        compact.contains('면허번호') ||
        compact.contains('적성검사') ||
        compact.contains('갱신기간') ||
        compact.contains('학생증') ||
        compact.contains('학번') ||
        compact.contains('학과') ||
        compact.contains('전공') ||
        compact.contains('한국기술교육대학교') ||
        compact.contains('SHINHANCARD') ||
        compact.contains('VALIDTHRU') ||
        compact.contains('통신공학부') ||
        compact.contains('성명') ||
        compact.contains('이름') ||
        compact == '주소' ||
        compact.startsWith('주소') ||
        compact == '주소:' ||
        compact.contains('발급일');
  }

  static void _addIdCardSpecificSpans({
    required List<_DetectedSpan> spans,
    required TextLine line,
    required _IdCardType idCardType,
  }) {
    final text = line.text.trim();
    if (text.isEmpty) return;

    final name = _extractIdCardNameSpan(text);
    if (name != null) {
      _addManualSpan(
        spans: spans,
        line: line,
        span: name,
        type: 'NAME',
        confidence: idCardType == _IdCardType.none ? 'MEDIUM' : 'HIGH',
      );
    }

    final address = _extractIdCardAddressSpan(text);
    if (address != null) {
      _addManualSpan(
        spans: spans,
        line: line,
        span: address,
        type: 'ADDRESS',
        confidence: idCardType == _IdCardType.none ? 'MEDIUM' : 'HIGH',
      );
    }

    if (idCardType == _IdCardType.driver || _hasDriverLicenseContext(text)) {
      _addRegexMatches(
        spans: spans,
        line: line,
        regex: _driverLicenseRegex,
        type: 'DRIVER_LICENSE',
        confidence: 'HIGH',
        avoidOverlapTypes: {'RRN', 'PARTIAL_RRN'},
      );
    }

    if (idCardType == _IdCardType.student || _hasStudentIdContext(text)) {
      _addRegexMatches(
        spans: spans,
        line: line,
        regex: _studentIdRegex,
        type: 'STUDENT_ID',
        confidence: 'HIGH',
        avoidOverlapTypes: {'RRN', 'PHONE', 'ACCOUNT_NUMBER', 'CARD_NUMBER'},
      );

      final major = _extractStudentMajorSpan(text);
      if (major != null) {
        _addManualSpan(
          spans: spans,
          line: line,
          span: major,
          type: 'MAJOR',
          confidence: 'MEDIUM',
        );
      }

      final school = _extractStudentSchoolSpan(text);
      if (school != null) {
        _addManualSpan(
          spans: spans,
          line: line,
          span: school,
          type: 'SCHOOL',
          confidence: 'MEDIUM',
        );
      }
    }

    if (_hasIdIssueDateContext(text)) {
      _addRegexMatches(
        spans: spans,
        line: line,
        regex: _dateRegex,
        type: 'ID_ISSUE_DATE',
        confidence: 'MEDIUM',
        avoidOverlapTypes: {'BIRTH_DATE'},
      );
    }
  }

  static void _addIdCardLayoutSpans({
    required List<_DetectedSpan> spans,
    required List<TextLine> lines,
    required _IdCardType idCardType,
  }) {
    final docRect = _documentBounds(lines);
    if (docRect == null || docRect.width <= 0 || docRect.height <= 0) return;

    for (final line in lines) {
      final text = line.text.trim();
      if (text.isEmpty) continue;
      if (_isTitleOrSectionHeader(text) || _isTableHeader(text)) continue;

      final rect = line.boundingBox;
      final x = (rect.center.dx - docRect.left) / docRect.width;
      final y = (rect.center.dy - docRect.top) / docRect.height;
      final compact = text.replaceAll(RegExp(r'\s+'), '');
      final nameCandidate = _cleanKoreanNameCandidate(text);

      if (idCardType == _IdCardType.resident || idCardType == _IdCardType.driver) {
        if (_rrnRegex.hasMatch(text)) {
          _addRegexMatches(
            spans: spans,
            line: line,
            regex: _rrnRegex,
            type: 'RRN',
            confidence: 'HIGH',
          );
        }

        if (idCardType == _IdCardType.driver && _driverLicenseRegex.hasMatch(text)) {
          _addRegexMatches(
            spans: spans,
            line: line,
            regex: _driverLicenseRegex,
            type: 'DRIVER_LICENSE',
            confidence: 'HIGH',
            avoidOverlapTypes: {'RRN', 'PARTIAL_RRN'},
          );
        }

        // 한국 주민등록증/면허증의 이름은 보통 상단부에 배치된다.
        // 위치만으로 오탐하지 않도록 한글 이름 후보 + 성씨 검증을 반드시 통과시킨다.
        final hasEmptyParenName = RegExp(r'^[가-힣]{2,4}\s*[\(（][^\)）]*[\)）]$').hasMatch(text.trim());
        final bool driverPureNameZone = idCardType == _IdCardType.driver &&
            x > 0.12 && x < 0.88 && y > 0.12 && y < 0.78 &&
            RegExp(r'^[가-힣]{2,4}$').hasMatch(nameCandidate);
        if (((x > 0.18 && x < 0.85 && y > 0.10 && y < 0.62) || hasEmptyParenName || driverPureNameZone) && _isLikelyKoreanName(nameCandidate)) {
          final start = text.indexOf(nameCandidate);
          _addManualSpan(
            spans: spans,
            line: line,
            span: _TextSpanResult(value: nameCandidate, start: start < 0 ? 0 : start, end: start < 0 ? text.length : start + nameCandidate.length),
            type: 'NAME',
            confidence: 'MEDIUM',
          );
        }

        // 주소는 중하단에 길게 들어가는 경우가 많다. 라벨 없이 값만 잡힌 경우를 보완한다.
        if (y > 0.35 && y < 0.88) {
          final address = _extractIdCardAddressSpan(text) ?? _extractAddressSpan(text);
          if (address != null) {
            _addManualSpan(
              spans: spans,
              line: line,
              span: address,
              type: 'ADDRESS',
              confidence: 'MEDIUM',
            );
          }
        }
      }

      if (idCardType == _IdCardType.student) {
        if (_studentIdRegex.hasMatch(text)) {
          _addRegexMatches(
            spans: spans,
            line: line,
            regex: _studentIdRegex,
            type: 'STUDENT_ID',
            confidence: 'HIGH',
            avoidOverlapTypes: {'RRN', 'PHONE', 'ACCOUNT_NUMBER', 'CARD_NUMBER'},
          );
        }

        if (x > 0.20 && x < 0.85 && y > 0.20 && y < 0.75 && _isLikelyKoreanName(nameCandidate)) {
          final start = text.indexOf(nameCandidate);
          _addManualSpan(
            spans: spans,
            line: line,
            span: _TextSpanResult(value: nameCandidate, start: start < 0 ? 0 : start, end: start < 0 ? text.length : start + nameCandidate.length),
            type: 'NAME',
            confidence: 'MEDIUM',
          );
        }

        final major = _extractStudentMajorSpan(text) ?? _extractStudentStandaloneMajorSpan(text);
        if (major != null) {
          _addManualSpan(
            spans: spans,
            line: line,
            span: major,
            type: 'MAJOR',
            confidence: 'MEDIUM',
          );
        }

        final school = _extractStudentSchoolSpan(text);
        if (school != null) {
          _addManualSpan(
            spans: spans,
            line: line,
            span: school,
            type: 'SCHOOL',
            confidence: 'MEDIUM',
          );
        }
      }
    }
  }


  static void _addBrokenIdCardAddressLayoutSpans({
    required List<_DetectedSpan> spans,
    required List<TextLine> lines,
    required _IdCardType idCardType,
  }) {
    if (idCardType != _IdCardType.resident && idCardType != _IdCardType.driver) return;

    final sorted = [...lines]..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    for (int i = 0; i < sorted.length; i++) {
      final first = sorted[i];
      final firstText = first.text.trim();
      if (firstText.isEmpty) continue;

      if (!_looksLikeBrokenAddressStart(firstText)) continue;

      final selected = <TextLine>[first];
      Rect mergedRect = first.boundingBox;

      for (int j = i + 1; j < sorted.length && selected.length < 3; j++) {
        final next = sorted[j];
        final nextText = next.text.trim();
        if (nextText.isEmpty) continue;

        final verticalGap = next.boundingBox.top - mergedRect.bottom;
        final horizontalNear = next.boundingBox.left < mergedRect.right + 360 &&
            next.boundingBox.right > mergedRect.left - 360;

        if (verticalGap < -40 || verticalGap > 140 || !horizontalNear) continue;
        if (!_looksLikeBrokenAddressContinuation(nextText)) continue;

        selected.add(next);
        mergedRect = mergedRect.expandToInclude(next.boundingBox);
      }

      if (selected.length < 2) continue;

      final joined = selected.map((e) => e.text.trim()).join(' ');
      final compact = joined.replaceAll(RegExp(r'\s+'), '');

      // 최소한 행정구역 후보 + 숫자 상세주소가 함께 있어야 주소로 인정한다.
      final hasRegionLike = RegExp(r'(서울|부산|대구|인천|광주|대전|대진|울산|세종|경기|강원|충북|충남|전북|전남|경북|경남|제주|광역|광역시|광역처|특별시|[가-힣]{1,6}시|[가-힣]{1,6}구)').hasMatch(compact);
      final hasDetailNumber = RegExp(r'[0-9]{1,5}').hasMatch(compact);
      final hasAddressUnit = RegExp(r'(구|동|읍|면|리|로|길|번길|번|동|호|아파트|빌라|슈빌|마을|단지)').hasMatch(compact);
      if (!hasRegionLike || !hasDetailNumber || !hasAddressUnit) continue;

      final alreadyAddress = spans.any((span) {
        return span.type == 'ADDRESS' && span.rect.overlaps(mergedRect.inflate(12));
      });
      if (alreadyAddress) continue;

      spans.add(
        _DetectedSpan(
          type: 'ADDRESS',
          text: joined,
          rect: mergedRect.inflate(2),
          polygon: [
            Offset(mergedRect.left, mergedRect.top),
            Offset(mergedRect.right, mergedRect.top),
            Offset(mergedRect.right, mergedRect.bottom),
            Offset(mergedRect.left, mergedRect.bottom),
          ],
          confidence: 'MEDIUM',
          lineText: joined,
          start: 0,
          end: joined.length,
        ),
      );
    }
  }

  static bool _looksLikeBrokenAddressStart(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), '');
    if (compact.isEmpty) return false;

    // 정상 주소뿐 아니라 주민등록증 OCR에서 자주 깨지는 "대전광역시 → 대진광역처" 형태까지 허용한다.
    final hasRegionStart = RegExp(
      r'(서울|부산|대구|인천|광주|대전|대진|울산|세종|경기|강원|충북|충남|전북|전남|경북|경남|제주|광역|광역시|광역처|특별시)',
    ).hasMatch(compact);
    final hasDistrictOrRoad = RegExp(r'([가-힣]{1,6}구|[가-힣]{1,8}동|[가-힣]{1,8}로|[가-힣]{1,8}길|으브갈|동으)').hasMatch(compact);

    return hasRegionStart && hasDistrictOrRoad;
  }

  static bool _looksLikeBrokenAddressContinuation(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), '');
    if (compact.isEmpty) return false;

    if (RegExp(r'^\(?[가-힣]{1,12}(동|읍|면|리)[,，]?.{0,20}\)?$').hasMatch(compact)) return true;
    if (RegExp(r'[0-9]{1,5}(동|호|층)?').hasMatch(compact) && RegExp(r'(동|호|층|[0-9])').hasMatch(compact)) return true;
    if (compact.startsWith('(') && compact.endsWith(')')) return true;

    return false;
  }

  static Rect? _documentBounds(List<TextLine> lines) {
    Rect? result;
    for (final line in lines) {
      final text = line.text.trim();
      if (text.isEmpty) continue;
      final rect = line.boundingBox;
      result = result == null ? rect : result.expandToInclude(rect);
    }
    return result;
  }

  static _TextSpanResult? _extractIdCardNameSpan(String text) {
    final original = text.trim();

    // 주민등록증/면허증 OCR에서 이름 뒤의 한자/영문 병기 괄호가 비어 있거나 깨지는 경우.
    // 예: "이상혁()" → "이상혁"
    final parenOnlyMatch = RegExp(
      r'^\s*([가-힣]{2,4})\s*[\(（][^\)）]*[\)）]\s*$',
    ).firstMatch(original);
    if (parenOnlyMatch != null) {
      final rawName = parenOnlyMatch.group(1);
      if (rawName != null) {
        final normalized = _cleanKoreanNameCandidate(rawName);
        if (_isLikelyKoreanName(normalized)) {
          final start = original.indexOf(rawName);
          return _TextSpanResult(
            value: normalized,
            start: start < 0 ? 0 : start,
            end: start < 0 ? normalized.length : start + rawName.length,
          );
        }
      }
    }

    // 예: 성명 홍길동, 성 명 : 홍 길 동, 이름: 김철수
    final match = RegExp(
      r'(?:성\s*명|이\s*름|성명|이름)\s*[:：]?\s*((?:[가-힣]\s*){2,4})',
    ).firstMatch(original);

    if (match == null) return null;

    final rawName = match.group(1);
    if (rawName == null) return null;

    final normalized = _cleanKoreanNameCandidate(rawName);
    if (!_isLikelyKoreanName(normalized)) return null;

    final start = original.indexOf(rawName);
    if (start < 0) return null;

    return _TextSpanResult(value: normalized, start: start, end: start + rawName.length);
  }

  static _TextSpanResult? _extractIdCardAddressSpan(String text) {
    final original = text.trim();
    if (original.isEmpty) return null;

    final compact = original.replaceAll(RegExp(r'\s+'), '');
    final hasAddressLabel = RegExp(r'^주\s*소\s*[:：]?').hasMatch(original);
    final hasAddressValue = _hasAddressCoreToken(_normalizeAddressOcrCompact(original));
    if (!hasAddressLabel && !hasAddressValue) {
      return null;
    }

    // 라벨이 포함된 경우 라벨은 제외하고 실제 주소 값만 표시한다.
    final labelMatch = RegExp(r'주\s*소\s*[:：]?\s*').firstMatch(original);
    final source = labelMatch == null ? original : original.substring(labelMatch.end).trim();
    if (source.isEmpty) return null;

    final span = _extractAddressSpan(source);
    if (span == null) return null;

    final sourceStart = labelMatch == null ? 0 : original.indexOf(source);
    return _TextSpanResult(
      value: span.value,
      start: sourceStart + span.start,
      end: sourceStart + span.end,
    );
  }

  static bool _hasDriverLicenseContext(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), '');
    return compact.contains('운전면허') || compact.contains('면허번호') || compact.contains('면허증');
  }

  static bool _hasStudentIdContext(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    return compact.contains('학번') ||
        compact.contains('학생번호') ||
        compact.contains('학생증') ||
        compact.contains('한국기술교육대학교') ||
        compact.contains('SHINHANCARD') ||
        compact.contains('VALIDTHRU') ||
        compact.contains('통신공학부') ||
        compact.contains('공학부');
  }

  static bool _hasIdIssueDateContext(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), '');
    return compact.contains('발급일') || compact.contains('발행일') || compact.contains('교부일');
  }

  static _TextSpanResult? _extractStudentMajorSpan(String text) {
    final original = text.trim();
    final match = RegExp(
      r'(?:학\s*과|전\s*공|소\s*속)\s*[:：]?\s*([가-힣A-Za-z0-9\s]{2,30}(?:학과|학부|전공|과|부|대학))',
    ).firstMatch(original);
    if (match == null) return null;

    final value = match.group(1)?.trim();
    if (value == null || value.isEmpty) return null;
    final start = original.indexOf(value);
    if (start < 0) return null;
    return _TextSpanResult(value: value, start: start, end: start + value.length);
  }

  static _TextSpanResult? _extractStudentStandaloneMajorSpan(String text) {
    final original = text.trim();
    if (original.isEmpty) return null;

    // 학생증에서는 전공/학과 라벨 없이 "전기·전자·통신공학부"처럼 값만 적히는 경우가 있다.
    // 단독 전공명은 학생증 문맥에서만 호출하므로 일반 문서 오탐을 줄일 수 있다.
    final normalized = original
        .replaceAll(RegExp(r'[ㆍ·•]'), '·')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final compact = normalized.replaceAll(RegExp(r'\s+'), '');
    if (compact.length < 3 || compact.length > 30) return null;

    final hasMajorSuffix = RegExp(r'(학과|학부|전공|공학부|공학과|과)$').hasMatch(compact);
    final hasStudentMajorKeyword = RegExp(r'(전자|전기|통신|컴퓨터|소프트웨어|기계|전산|정보|보안|경영|디자인|건축|화학|산업|메카트로닉스)').hasMatch(compact);
    final isNoise = RegExp(r'(학생증|카드|CARD|VALID|THRU|MONTH|YEAR|SHINHAN|CHECK|DEBIT|대한민국|주민등록증|운전면허)').hasMatch(compact.toUpperCase());

    if (!hasMajorSuffix || !hasStudentMajorKeyword || isNoise) return null;

    final start = original.indexOf(original.trim());
    return _TextSpanResult(
      value: normalized,
      start: start < 0 ? 0 : start,
      end: start < 0 ? original.length : start + original.trim().length,
    );
  }

  static _TextSpanResult? _extractStudentSchoolSpan(String text) {
    final original = text.trim();
    final compactLine = original.replaceAll(RegExp(r'\s+'), '');

    // 졸업장 본문 문장에 포함된 "우리 대학교"는 학교명 개인정보가 아니다.
    if (compactLine.contains('위사람은우리대학교') ||
        compactLine.contains('우리대학교소정의') ||
        compactLine.contains('소정의전과정') ||
        compactLine.contains('학사학위취득')) {
      return null;
    }

    final match = RegExp(r'([가-힣A-Za-z0-9]{2,25}\s*(?:대\s*학\s*교|대\s*학))').firstMatch(original);
    if (match == null) return null;
    final raw = match.group(1);
    if (raw == null) return null;
    final normalized = raw.replaceAll(RegExp(r'\s+'), '');
    if (normalized == '대학교' ||
        normalized == '대학' ||
        normalized == '우리대학교' ||
        normalized == '본대학교' ||
        normalized == '해당대학교') {
      return null;
    }
    final start = original.indexOf(raw);
    if (start < 0) return null;
    return _TextSpanResult(value: normalized, start: start, end: start + raw.length);
  }

  static bool _isDiplomaContext(List<TextLine> lines) {
    int score = 0;

    for (final line in lines) {
      final compact = line.text.replaceAll(RegExp(r'\s+'), '');

      if (compact.contains('졸업장')) score += 4;
      if (compact.contains('학사학위')) score += 3;
      if (compact.contains('대학교')) score += 2;
      if (compact.contains('총장')) score += 2;
      if (compact.contains('성명') || compact.contains('생년월일')) score += 2;
      if (compact.contains('전공') || compact == '전' || compact.startsWith('공:')) score += 1;
    }

    return score >= 5;
  }

  static bool _looksLikeDiplomaLine(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), '');

    return compact.contains('졸업장') ||
        compact.contains('학사학위') ||
        compact.contains('성명') ||
        compact.startsWith('명:') ||
        compact.contains('생년월일') ||
        compact.contains('전공') ||
        compact.startsWith('공:') ||
        compact.contains('대학교') ||
        compact.contains('총장');
  }

  static void _addDiplomaSpecificSpans({
    required List<_DetectedSpan> spans,
    required TextLine line,
    required bool isGlobalDiplomaContext,
  }) {
    if (!isGlobalDiplomaContext) return;

    final text = line.text.trim();
    if (text.isEmpty) return;

    final name = _extractDiplomaNameSpan(text);
    if (name != null) {
      _addManualSpan(
        spans: spans,
        line: line,
        span: name,
        type: 'NAME',
        confidence: 'MEDIUM',
      );
    }

    final major = _extractDiplomaMajorSpan(text);
    if (major != null) {
      _addManualSpan(
        spans: spans,
        line: line,
        span: major,
        type: 'MAJOR',
        confidence: 'MEDIUM',
      );
    }

    final school = _extractDiplomaSchoolSpan(text);
    if (school != null) {
      _addManualSpan(
        spans: spans,
        line: line,
        span: school,
        type: 'SCHOOL',
        confidence: 'MEDIUM',
      );
    }

    final president = _extractDiplomaPresidentNameSpan(text);
    if (president != null) {
      _addManualSpan(
        spans: spans,
        line: line,
        span: president,
        type: 'NAME',
        confidence: 'MEDIUM',
      );
    }
  }

  static _TextSpanResult? _extractDiplomaNameSpan(String text) {
    final original = text.trim();
    final compact = original.replaceAll(RegExp(r'\s+'), '');

    // 예: "성 명 : 홍 길 동", "명 :홍 길동", "성명:홍길동"
    final match = RegExp(
      r'(?:성\s*명|명)\s*[:：]\s*((?:[가-힣]\s*){2,4})',
    ).firstMatch(original);

    if (match == null) return null;

    final rawName = match.group(1);
    if (rawName == null) return null;

    final normalized = rawName.replaceAll(RegExp(r'\s+'), '');
    if (!_isLikelyKoreanName(normalized)) return null;

    // "생년월일" OCR 일부가 "성생"처럼 합쳐지는 경우까지 고려해
    // 이름 후보는 반드시 콜론 뒤쪽 값만 사용한다.
    if (compact.contains('생년월일') && !compact.contains('성명')) return null;

    final start = original.indexOf(rawName);
    if (start < 0) return null;

    return _TextSpanResult(
      value: normalized,
      start: start,
      end: start + rawName.length,
    );
  }

  static _TextSpanResult? _extractDiplomaMajorSpan(String text) {
    final original = text.trim();

    // 예: "전 공 : 기계공학부"가 OCR에서 "공 : 기계공학부"로 잘리는 경우 보완.
    final match = RegExp(
      r'(?:전\s*공|공)\s*[:：]\s*([가-힣A-Za-z0-9\s]{2,30}(?:학과|학부|전공|과|부))',
    ).firstMatch(original);

    if (match == null) return null;

    final value = match.group(1)?.trim();
    if (value == null || value.isEmpty) return null;

    final start = original.indexOf(value);
    if (start < 0) return null;

    return _TextSpanResult(
      value: value,
      start: start,
      end: start + value.length,
    );
  }

  static _TextSpanResult? _extractDiplomaSchoolSpan(String text) {
    final original = text.trim();
    final compactLine = original.replaceAll(RegExp(r'\s+'), '');

    // 본문 문장에 포함된 "우리 대학교"는 학교명 개인정보가 아니다.
    // 예: "위 사람은 우리 대학교 소정의 전 과정을..." 오탐 방지
    final sentenceBlockKeywords = [
      '위사람은',
      '우리대학교',
      '소정의',
      '전과정',
      '이수하여',
      '학사학위',
      '취득에',
      '필요한',
      '요건',
      '충족',
      '인정하여',
      '졸업장',
      '수여',
    ];

    if (sentenceBlockKeywords.any((word) => compactLine.contains(word))) {
      return null;
    }

    // 예: "한국기술교육대 학교 총장 유 길상"처럼 학교가 띄어져 OCR되는 경우 보완.
    // 단, 실제 학교명은 보통 "OO대 학교" 앞부분에 기관명이 있으므로
    // "우리 대학교", "본 대학교" 같은 일반 지시 표현은 제외한다.
    final match = RegExp(
      r'([가-힣A-Za-z0-9]{2,25}\s*대\s*학교)',
    ).firstMatch(original);

    if (match == null) return null;

    final rawValue = match.group(1);
    if (rawValue == null) return null;

    final normalized = rawValue.replaceAll(RegExp(r'\s+'), '');
    if (!normalized.endsWith('대학교')) return null;

    final schoolBlacklist = {
      '우리대학교',
      '본대학교',
      '해당대학교',
      '대학교',
    };

    if (schoolBlacklist.contains(normalized)) return null;

    final start = original.indexOf(rawValue);
    if (start < 0) return null;

    return _TextSpanResult(
      value: normalized,
      start: start,
      end: start + rawValue.length,
    );
  }

  static _TextSpanResult? _extractDiplomaPresidentNameSpan(String text) {
    final original = text.trim();

    // 예: "총장 유 길상" → 유길상
    final match = RegExp(
      r'총장\s*((?:[가-힣]\s*){2,4})',
    ).firstMatch(original);

    if (match == null) return null;

    final rawName = match.group(1);
    if (rawName == null) return null;

    final normalized = rawName.replaceAll(RegExp(r'\s+'), '');
    if (!_isLikelyKoreanName(normalized)) return null;

    final start = original.indexOf(rawName);
    if (start < 0) return null;

    return _TextSpanResult(
      value: normalized,
      start: start,
      end: start + rawName.length,
    );
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

    if (labelType == 'MAJOR') {
      final major = _extractDiplomaMajorSpan('전공: $valueText') ??
          _TextSpanResult(value: valueText, start: 0, end: valueText.length);
      _addManualSpan(
        spans: spans,
        line: valueLine,
        span: major,
        type: 'MAJOR',
        confidence: 'MEDIUM',
      );
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

    if (labelType == 'STUDENT_ID') {
      _addRegexMatches(
        spans: spans,
        line: valueLine,
        regex: _studentIdRegex,
        type: 'STUDENT_ID',
        confidence: 'HIGH',
        avoidOverlapTypes: {'RRN', 'PHONE', 'ACCOUNT_NUMBER', 'CARD_NUMBER'},
      );
      return;
    }

    if (labelType == 'ID_ISSUE_DATE') {
      _addRegexMatches(
        spans: spans,
        line: valueLine,
        regex: _dateRegex,
        type: 'ID_ISSUE_DATE',
        confidence: 'MEDIUM',
        avoidOverlapTypes: {'BIRTH_DATE'},
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

      case 'MAJOR':
        return RegExp(r'^[가-힣A-Za-z0-9\s]{2,30}(학과|학부|전공|과|부)$')
            .hasMatch(compact);

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


  static _TextSpanResult _normalizeManualSpanForType({
    required String lineText,
    required _TextSpanResult span,
    required String type,
  }) {
    if (type == 'MAJOR') {
      final original = lineText.trim();

      // 졸업장 OCR에서 "공 : 기계공학부"처럼 라벨과 값이 한 줄로 잡힌 경우
      // 화면 박스에는 실제 개인정보 값인 "기계공학부"만 남긴다.
      final labelMatch = RegExp(
        r'(?:전\s*공|공)\s*[:：]\s*([가-힣A-Za-z0-9\s]{2,30}(?:학과|학부|전공|과|부))',
      ).firstMatch(original);

      if (labelMatch != null) {
        final value = labelMatch.group(1)?.trim();
        if (value != null && value.isNotEmpty) {
          final start = original.indexOf(value);
          if (start >= 0) {
            return _TextSpanResult(
              value: value,
              start: start,
              end: start + value.length,
            );
          }
        }
      }

      if (span.value.contains(':') || span.value.contains('：')) {
        final parts = span.value.split(RegExp(r'[:：]'));
        final value = parts.last.trim();
        final start = original.indexOf(value);
        if (value.isNotEmpty && start >= 0) {
          return _TextSpanResult(
            value: value,
            start: start,
            end: start + value.length,
          );
        }
      }
    }

    if (type == 'SCHOOL') {
      final compactValue = span.value.replaceAll(RegExp(r'\s+'), '');
      final compactLine = lineText.replaceAll(RegExp(r'\s+'), '');

      // "위 사람은 우리 대학교..."의 "우리대학교"는 실제 학교명이 아니라 본문 지시어다.
      if (compactValue == '우리대학교' ||
          compactValue == '본대학교' ||
          compactValue == '해당대학교' ||
          compactLine.contains('위사람은우리대학교') ||
          compactLine.contains('우리대학교소정의')) {
        return _TextSpanResult(value: '', start: 0, end: 0);
      }
    }

    if (type == 'NAME') {
      final compactValue = span.value.replaceAll(RegExp(r'\s+'), '');

      // 졸업장 라벨 "성 명"이 OCR에서 "성생"으로 깨진 경우를 이름으로 오탐하지 않는다.
      if (compactValue == '성생' ||
          compactValue == '성명' ||
          compactValue == '생년' ||
          compactValue == '생년월') {
        return _TextSpanResult(value: '', start: 0, end: 0);
      }
    }

    return span;
  }

  static void _addManualSpan({
    required List<_DetectedSpan> spans,
    required TextLine line,
    required _TextSpanResult span,
    required String type,
    required String confidence,
  }) {
    final effectiveSpan = _normalizeManualSpanForType(
      lineText: line.text.trim(),
      span: span,
      type: type,
    );

    if (effectiveSpan.value.trim().isEmpty) return;

    final candidate = _DetectedSpan(
      type: type,
      text: effectiveSpan.value,
      rect: _rectForTextSpan(
        line: line,
        start: effectiveSpan.start,
        end: effectiveSpan.end,
      ),
      polygon: _polygonForTextSpan(
        line: line,
        start: effectiveSpan.start,
        end: effectiveSpan.end,
      ),
      confidence: confidence,
      lineText: line.text.trim(),
      start: effectiveSpan.start,
      end: effectiveSpan.end,
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
        'CERTIFICATE_ISSUE_NUMBER',
        'STUDENT_ID',
        'ID_ISSUE_DATE',
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
        compact == '성명:' ||
        compact == '성명：' ||
        compact == '명:' ||
        compact == '명：' ||
        compact.startsWith('명:') ||
        compact.startsWith('명：') ||
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

    if (compact == '전공' ||
        compact == '전공:' ||
        compact == '전공：' ||
        compact.startsWith('전공:') ||
        compact.startsWith('전공：') ||
        compact.startsWith('공:') ||
        compact.startsWith('공：')) {
      return 'MAJOR';
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
    if (compact.contains('학번') || compact.contains('학생번호')) return 'STUDENT_ID';
    if (compact.contains('발급일') || compact.contains('발행일') || compact.contains('교부일')) return 'ID_ISSUE_DATE';
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

  static bool _hasIssueNumberContext(String text) {
    final compact = text.replaceAll(' ', '');

    return compact.contains('발급번호') ||
        compact.contains('발행번호') ||
        compact.contains('증명번호') ||
        compact.contains('문서번호');
  }

  static bool _looksLikeAccountOnly(String text) {
    final compact = text.replaceAll(' ', '');

    if (_waybillCodeRegex.hasMatch(compact)) return false;
    if (_certificateIssueNumberRegex.hasMatch(compact)) return false;
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

    // "2024년 02월 26일"처럼 문서 발급일/작성일로 자주 쓰이는
    // 한글 날짜 단독 라인은 생년월일로 보지 않는다.
    // 생년월일 라벨이 있는 경우에는 _hasBirthContext(rawText)가 true라서
    // 위쪽 분기에서 정상적으로 BIRTH_DATE로 탐지된다.
    if (RegExp(r'^(19|20)[0-9]{2}년[0-9]{1,2}월[0-9]{1,2}일?$').hasMatch(compact)) {
      return false;
    }

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

    if (type == 'CERTIFICATE_ISSUE_NUMBER') return false;
    if (type == 'ID_ISSUE_DATE') return false;

    if (compactLine.contains('접수번호') ||
        compactLine.contains('신청번호') ||
        compactLine.contains('발급번호') ||
        compactLine.contains('발행번호') ||
        compactLine.contains('증명번호') ||
        compactLine.contains('문서번호') ||
        compactLine.contains('관리번호') ||
        compactLine.contains('공고제')) {
      return true;
    }

    if (type == 'BIRTH_DATE') return false;

    return false;
  }


  static bool _looksLikeCertificateDocumentNumber(String compact) {
    final value = compact.replaceAll(RegExp(r'\s+'), '');

    return RegExp(r'^제?[0-9]{4}[-–—]?[0-9]{3,8}호$').hasMatch(value) ||
        RegExp(r'^제[0-9]{3,8}호$').hasMatch(value);
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

    // 졸업장/증명서의 문서번호는 '호'가 붙어도 주소의 동/호수가 아니다.
    // 예: 제 2024-12345 호
    if (_looksLikeCertificateDocumentNumber(compact)) return null;

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
      return _addressSpanFromCleanedText(text);
    }

    final hasRegion = RegExp(
      r'(서울|부산|대구|인천|광주|대전|울산|세종|경기|강원|충북|충남|전북|전남|경북|경남|제주|천안|충청남도|충남)',
    ).hasMatch(compact);

    final hasAddressUnit = RegExp(
      r'(특별시|광역시|도|시|군|구|읍|면|동|리|로|길|번길|가길|층|호|빌딩|아파트|단지)',
    ).hasMatch(compact);

    final hasDigit = RegExp(r'[0-9]').hasMatch(compact);

    if (hasRegion && hasAddressUnit && hasDigit) {
      return _addressSpanFromCleanedText(text);
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
      return _addressSpanFromCleanedText(text);
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
      return _addressSpanFromCleanedText(text);
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
      return _addressSpanFromCleanedText(text);
    }

    if (_looksLikeBuildingOrHousingName(compact)) {
      return _addressSpanFromCleanedText(text);
    }

    return null;
  }

  static _TextSpanResult _addressSpanFromCleanedText(String text) {
    final original = text.trim();

    // 라벨과 값이 같은 줄에 붙은 경우 라벨은 개인정보 박스에서 제외한다.
    // 예: "주 소 대전광역시 ..." -> "대전광역시 ..."
    final leadingAddressLabelMatch = RegExp(
      r'^(?:주\s*소|주소)\s*[:：]?\s*(.+)$',
    ).firstMatch(original);

    if (leadingAddressLabelMatch != null) {
      final valueAfterLabel = leadingAddressLabelMatch.group(1)?.trim();
      if (valueAfterLabel != null && valueAfterLabel.isNotEmpty) {
        final valueStart = text.indexOf(valueAfterLabel);
        return _addressSpanFromCleanedTextValue(
          sourceText: text,
          candidateText: valueAfterLabel,
          fallbackStart: valueStart < 0 ? 0 : valueStart,
        );
      }
    }

    return _addressSpanFromCleanedTextValue(
      sourceText: text,
      candidateText: original,
      fallbackStart: text.indexOf(original),
    );
  }

  static _TextSpanResult _addressSpanFromCleanedTextValue({
    required String sourceText,
    required String candidateText,
    required int fallbackStart,
  }) {
    final original = candidateText.trim();

    // 주소가 일반 문장 안에 들어간 경우, 실제 주소 뒤에 붙는
    // 조사/서술어는 개인정보 주소 영역에서 제외한다.
    // 예: "서울시 강남구 테헤란로 123으로 등록되어 있습니다."
    //     -> "서울시 강남구 테헤란로 123"
    final trailingSentencePatterns = [
      RegExp(
        r'^(.*?[0-9]+(?:[-][0-9]+)?)(?:\s*(?:으로|로|에|에서))\s*(?:등록|기재|입력|사용|처리|되어|되었습니다|되어있습니다|있습니다|입니다|이며|이고|합니다|하였습니다).*$',
      ),
      RegExp(
        r'^(.*?[0-9]+(?:[-][0-9]+)?)(?:으로|로)\s*[\.,，。]*$',
      ),
      RegExp(
        r'^(.*?[0-9]+(?:[-][0-9]+)?)(?:입니다|이며|이고)\s*[\.,，。]*$',
      ),
    ];

    String value = original;

    for (final pattern in trailingSentencePatterns) {
      final match = pattern.firstMatch(original);
      final matchedValue = match?.group(1)?.trim();
      if (matchedValue != null && matchedValue.isNotEmpty) {
        value = matchedValue;
        break;
      }
    }

    final start = sourceText.indexOf(value);
    final resolvedStart = start < 0 ? fallbackStart : start;
    final safeStart = resolvedStart < 0 ? 0 : resolvedStart;

    return _TextSpanResult(
      value: value,
      start: safeStart,
      end: safeStart + value.length,
    );
  }

  static bool _isNonAddressSentence(String compact) {
    if (compact.isEmpty) return true;
    if (_looksLikeCertificateDocumentNumber(compact)) return true;

    if (compact.contains('서비스') ||
        compact.contains('고객센터') ||
        compact.contains('센터') ||
        compact.contains('상담') ||
        compact.contains('문의')) {
      return true;
    }

    // 세무/증명서 안내 문장의 '주택임대소득', '2천만원이하' 같은 표현이
    // 주소의 '주택', 숫자, '동' 등으로 오탐되는 것을 차단한다.
    if (compact.contains('소득') ||
        compact.contains('과세') ||
        compact.contains('결정세액') ||
        compact.contains('합계액') ||
        compact.contains('공제') ||
        compact.contains('금액') ||
        compact.contains('이월결손') ||
        compact.contains('주택임대') ||
        compact.contains('계약금') ||
        compact.contains('위약금') ||
        compact.contains('기타소득') ||
        compact.contains('종합소득세')) {
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
      RegExp(r'(?:성\s*명|명)\s*[:：]\s*((?:[가-힣]\s*){2,4})'),
      // 표 양식에서 "성명 임채진"처럼 콜론 없이 라벨과 이름이 같은 줄에 붙는 경우 보완.
      // "소 득 금 액 증 명" 같은 제목 오탐은 아래 _isLikelyKoreanName/일반문서어 필터로 차단한다.
      RegExp(r'(?:^|\s)성\s*명\s+((?:[가-힣]\s*){2,4})(?=$|\s)'),
      // OCR이 존칭 "님"을 "남"으로 잘못 읽는 경우 보완.
      // 예: "홍길동 님", "홍길동 남" → 앞의 이름 "홍길동"만 개인정보로 탐지한다.
      // 오탐 방지를 위해 "여/남자/여자"는 허용하지 않는다.
      // 주민등록증 촬영/회전 시 이름 뒤 빈 괄호가 붙는 경우. 예: "이상혁()" → "이상혁"
      RegExp(r'^([가-힣]{2,4})\s*[\(（][^\)）]*[\)）]$'),
      RegExp(r'^([가-힣]{2,4})\s*(님|남|넘|니)[\.\)\]】）]*$'),
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
    return RegExp(r'(님|남|넘|니|씨|귀하|\(인\)|\(서명\))[\.\)\]】）]*$').hasMatch(compact);
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
      '성생',
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
    // 주민등록번호: 생년월일 6자리 + 뒷자리 7자리로 고정한다.
    // 예: 901225-1234567, 9012251234567
    r'\b[0-9]{6}[-]?[1-4][0-9]{6}\b',
  );

  static final RegExp _partialRrnRegex = RegExp(
    r'[0-9]{6}',
  );

  static final RegExp _phoneRegex = RegExp(
    // 전화번호: 휴대전화 10~11자리, 대표 유선전화 형태만 허용한다.
    // 주민등록번호/운전면허번호 일부가 전화번호로 중복 탐지되는 것을 막기 위해
    // 숫자 개수와 하이픈 위치를 엄격하게 제한한다.
    // 예: 010-1234-5678, 01012345678, 02-1234-5678
    r'\b(?:01[016789][- ]?[0-9]{3,4}[- ]?[0-9]{4}|0(?:2|[3-6][1-5])[- ]?[0-9]{3,4}[- ]?[0-9]{4})\b',
  );

  static final RegExp _emailRegex = RegExp(
    r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
    caseSensitive: false,
  );

  static final RegExp _cardRegex = RegExp(
    r'(?:[0-9]{4}[-]?){3}[0-9]{4}',
  );

  static final RegExp _certificateIssueNumberRegex = RegExp(
    // 국세/민원 증명서 발급번호 예: 8553-345-3660-056
    // 계좌번호와 구분하기 위해 문맥 함수(_hasIssueNumberContext)와 함께 사용한다.
    r'[0-9]{4}[-][0-9]{3}[-][0-9]{4}[-][0-9]{3}',
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
    // 일반 문서/여권 이미지에서 모두 쓰는 여권번호 패턴.
    // 예: SM0893652(영문 2자+숫자 7자), M123A4567(영문/숫자 혼합 9자),
    //     M12345678(영문 1자+숫자 8자), M123456789(영문 1자+숫자 9자).
    // REPUBLIC, PASSPORT 같은 영문 단어 오탐을 막기 위해 숫자 1개 이상을 필수로 둔다.
    r'\b(?=[A-Z0-9]{8,10}\b)(?=[A-Z0-9]*[0-9])[A-Z]{1,2}[A-Z0-9]{7,9}\b',
    caseSensitive: false,
  );

  static final RegExp _mrzRegex = RegExp(
    r'^[A-Z0-9<]{20,}$',
  );

  static final RegExp _driverLicenseRegex = RegExp(
    // 운전면허번호: 2-2-6-2 숫자 구조로 고정한다.
    // 예: 25-20-006518-92
    // 하이픈 없는 숫자열이나 다른 특수기호 조합은 오탐 가능성이 커서 제외한다.
    r'\b[0-9]{2}-[0-9]{2}-[0-9]{6}-[0-9]{2}\b',
  );

  static final RegExp _studentIdRegex = RegExp(
    // 학번: 한국기술교육대학교 학생증 테스트 기준 20으로 시작하는 10자리 숫자로 고정한다.
    // 예: 2022161140
    r'\b20[0-9]{8}\b',
    caseSensitive: false,
  );

  static final RegExp _dateRegex = RegExp(
    r'((19|20)[0-9]{2}[-./년\s]+[0-9]{1,2}[-./월\s]+[0-9]{1,2}일?)',
  );

  static List<PrivacyItem> _applyPriorityRules(List<PrivacyItem> items) {
    final rrnItems = items.where((item) => item.type == 'RRN').toList();
    final driverLicenseItems = items.where((item) => item.type == 'DRIVER_LICENSE').toList();
    final passportNumberItems = items.where((item) => item.type == 'PASSPORT_NUMBER').toList();
    final studentIdItems = items.where((item) => item.type == 'STUDENT_ID').toList();
    final issueNumberItems = items.where((item) => item.type == 'CERTIFICATE_ISSUE_NUMBER').toList();
    final mrzItems = items.where((item) => item.type == 'PASSPORT_MRZ').toList();
    final idIssueDateItems = items.where((item) => item.type == 'ID_ISSUE_DATE').toList();

    final concretePassportDateItems = items.where((item) {
      return item.type == 'BIRTH_DATE' ||
          item.type == 'PASSPORT_ISSUE_DATE' ||
          item.type == 'PASSPORT_EXPIRY_DATE';
    }).toList();

    return items.where((item) {
      final itemRect = item.rect;

      // 0) 신분증 발급일과 생년월일이 같은 영역에서 겹치면 문맥이 명확한 발급일을 우선한다.
      if (item.type == 'BIRTH_DATE' && itemRect != null) {
        for (final issueDate in idIssueDateItems) {
          final issueRect = issueDate.rect;
          if (issueRect == null) continue;

          final sameLine = (itemRect.center.dy - issueRect.center.dy).abs() < 8;
          final overlaps = _rectOverlapRatio(itemRect, issueRect) >= 0.80;

          if (sameLine && overlaps) {
            return false;
          }
        }
      }

      // 0-1) 주민등록번호가 전화번호/부분 주민번호와 같은 영역에서 겹치면 주민등록번호만 남긴다.
      if ((item.type == 'PHONE' || item.type == 'PARTIAL_RRN' || item.type == 'ACCOUNT_NUMBER' || item.type == 'DRIVER_LICENSE') && itemRect != null) {
        for (final rrn in rrnItems) {
          final rrnRect = rrn.rect;
          if (rrnRect == null) continue;

          final sameLine = (itemRect.center.dy - rrnRect.center.dy).abs() < 18;
          final overlaps = _rectOverlapRatio(itemRect, rrnRect) >= 0.35 ||
              rrnRect.inflate(8).contains(itemRect.center);

          if (sameLine && overlaps && item.type != 'RRN') {
            return false;
          }
        }
      }

      // 0-2) 운전면허번호가 계좌번호/전화번호 등으로도 잡히면 운전면허번호를 우선한다.
      if ((item.type == 'ACCOUNT_NUMBER' || item.type == 'PHONE' || item.type == 'PARTIAL_RRN') && itemRect != null) {
        for (final license in driverLicenseItems) {
          final licenseRect = license.rect;
          if (licenseRect == null) continue;

          final sameLine = (itemRect.center.dy - licenseRect.center.dy).abs() < 18;
          final overlaps = _rectOverlapRatio(itemRect, licenseRect) >= 0.35 ||
              licenseRect.inflate(8).contains(itemRect.center);

          if (sameLine && overlaps) {
            return false;
          }
        }
      }

      // 0-3) 여권번호가 계좌번호/일반 코드로 겹치면 여권번호를 우선한다.
      if ((item.type == 'ACCOUNT_NUMBER' || item.type == 'WAYBILL_CODE' || item.type == 'REGISTER_NUMBER') && itemRect != null) {
        for (final passport in passportNumberItems) {
          final passportRect = passport.rect;
          if (passportRect == null) continue;

          final sameLine = (itemRect.center.dy - passportRect.center.dy).abs() < 18;
          final overlaps = _rectOverlapRatio(itemRect, passportRect) >= 0.45 ||
              passportRect.inflate(8).contains(itemRect.center);

          if (sameLine && overlaps) {
            return false;
          }
        }
      }

      // 0-4) 학번이 전화번호/계좌번호/일반 숫자로 겹치면 학번을 우선한다.
      if ((item.type == 'PHONE' || item.type == 'ACCOUNT_NUMBER' || item.type == 'WAYBILL_ORDER_NUMBER') && itemRect != null) {
        for (final studentId in studentIdItems) {
          final studentRect = studentId.rect;
          if (studentRect == null) continue;

          final sameLine = (itemRect.center.dy - studentRect.center.dy).abs() < 18;
          final overlaps = _rectOverlapRatio(itemRect, studentRect) >= 0.45 ||
              studentRect.inflate(8).contains(itemRect.center);

          if (sameLine && overlaps) {
            return false;
          }
        }
      }

      // 0-5) 발급번호가 계좌번호로도 잡힌 경우 발급번호를 우선한다.
      if (item.type == 'ACCOUNT_NUMBER' && itemRect != null) {
        for (final issue in issueNumberItems) {
          final issueRect = issue.rect;
          if (issueRect == null) continue;

          final sameLine = (itemRect.center.dy - issueRect.center.dy).abs() < 16;
          final overlaps = _rectOverlapRatio(itemRect, issueRect) >= 0.45 ||
              issueRect.inflate(8).contains(itemRect.center);

          if (sameLine && overlaps) {
            return false;
          }
        }
      }

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

  static int _privacyTypePriority(String type) {
    switch (type) {
      case 'RRN':
        return 100;
      case 'DRIVER_LICENSE':
        return 95;
      case 'PASSPORT_MRZ':
        return 92;
      case 'PASSPORT_NUMBER':
      case 'PASSPORT_PERSONAL_NUMBER':
        return 90;
      case 'STUDENT_ID':
        return 88;
      case 'CERTIFICATE_ISSUE_NUMBER':
        return 86;
      case 'CARD_NUMBER':
        return 84;
      case 'PHONE':
        return 82;
      case 'EMAIL':
        return 80;
      case 'ACCOUNT_NUMBER':
        return 70;
      case 'REGISTER_NUMBER':
        return 68;
      case 'WAYBILL_CODE':
      case 'WAYBILL_ORDER_NUMBER':
        return 66;
      case 'BIRTH_DATE':
      case 'ID_ISSUE_DATE':
      case 'PASSPORT_ISSUE_DATE':
      case 'PASSPORT_EXPIRY_DATE':
      case 'PASSPORT_DATE':
        return 64;
      case 'ADDRESS':
        return 60;
      case 'NAME':
      case 'PASSPORT_NAME':
        return 58;
      case 'SCHOOL':
      case 'MAJOR':
      case 'COMPANY':
      case 'DEPARTMENT':
      case 'POSITION':
        return 50;
      case 'PARTIAL_RRN':
        return 40;
      default:
        return 10;
    }
  }

  static bool _shouldSuppressAsDuplicate({
    required PrivacyItem candidate,
    required PrivacyItem selected,
  }) {
    final candidateRect = candidate.rect;
    final selectedRect = selected.rect;
    if (candidateRect == null || selectedRect == null) return false;

    final candidatePriority = _privacyTypePriority(candidate.type);
    final selectedPriority = _privacyTypePriority(selected.type);

    final overlap = _rectOverlapRatio(candidateRect, selectedRect);
    final sameLine = (candidateRect.center.dy - selectedRect.center.dy).abs() < 18;
    final centerInsideSelected = selectedRect.inflate(6).contains(candidateRect.center);

    // 같은 값/같은 타입이 거의 같은 위치에 반복 생성된 경우 제거한다.
    if (candidate.type == selected.type &&
        candidate.text == selected.text &&
        (overlap >= 0.70 || centerInsideSelected)) {
      return true;
    }

    // 같은 박스에 서로 다른 타입이 잡히면 우선순위가 높은 타입만 유지한다.
    if ((overlap >= 0.82 || (sameLine && overlap >= 0.55) || centerInsideSelected) &&
        selectedPriority >= candidatePriority) {
      return true;
    }

    // 넓은 여권 하단 코드, 주소처럼 의도적으로 넓게 잡는 타입은 세부 박스와 겹칠 수 있다.
    // 단, MRZ 내부 세부 박스는 앞의 우선순위 규칙에서 이미 제거되므로 여기서는 넓은 박스를 유지한다.
    if (candidate.type == 'PASSPORT_MRZ' || selected.type == 'PASSPORT_MRZ') {
      return selectedPriority >= candidatePriority && overlap >= 0.50;
    }

    return false;
  }

  static List<PrivacyItem> _removeDuplicates(List<PrivacyItem> items) {
    final exactSeen = <String>{};
    final unique = <PrivacyItem>[];

    final sorted = [...items];
    sorted.sort((a, b) {
      final priorityDiff = _privacyTypePriority(b.type).compareTo(_privacyTypePriority(a.type));
      if (priorityDiff != 0) return priorityDiff;

      final ar = a.rect;
      final br = b.rect;
      if (ar == null || br == null) return 0;
      final topDiff = ar.top.compareTo(br.top);
      if (topDiff != 0) return topDiff;
      return ar.left.compareTo(br.left);
    });

    for (final item in sorted) {
      final rect = item.rect;
      final key =
          '${item.type}_${item.text}_${rect?.left.toStringAsFixed(1)}_${rect?.top.toStringAsFixed(1)}_${rect?.right.toStringAsFixed(1)}_${rect?.bottom.toStringAsFixed(1)}';

      if (exactSeen.contains(key)) continue;
      exactSeen.add(key);

      final suppressed = unique.any((selected) {
        return _shouldSuppressAsDuplicate(
          candidate: item,
          selected: selected,
        );
      });

      if (!suppressed) {
        unique.add(item);
      }
    }

    unique.sort((a, b) {
      final ar = a.rect;
      final br = b.rect;
      if (ar == null || br == null) return 0;
      final topDiff = ar.top.compareTo(br.top);
      if (topDiff != 0) return topDiff;
      return ar.left.compareTo(br.left);
    });

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