# 가림 (Garim)

> AI가 사진 속 개인정보를 찾아 보호해주는 앱

## 기능
- 얼굴 탐지 및 블러처리
- 차량 번호판 탐지 및 블러처리
- 카드 탐지 및 블러처리 (카드번호/이름/CVC 추출)
- 문서 탐지 및 개인정보 블러처리 (MRZ 파싱 포함)
- 블러 효과 3가지 선택 (흐림/모자이크/스티커)
- 블러 강도 슬라이더 조절
- 유형별 블러 ON/OFF 스위치
- 문서/카드 텍스트 탐지 후 부분 블러 선택

## 탐지 가능한 개인정보
- 주민등록번호
- 전화번호 (하이픈 있음/없음)
- 이메일
- 계좌번호
- 카드번호 / 유효기간 / CVC
- 여권번호 (MRZ 파싱)
- 운전면허번호
- 주소
- 이름 (국문/영문)
- 생년월일
- 운송장번호 / 주문번호

## 사용 모델
- 얼굴 탐지: ML Kit Face Detection
- 번호판 탐지: yolo_plate.tflite (YOLO11n)
- 카드 탐지: yolo_card.tflite
- 문서 탐지: yolo_document.tflite (YOLOv8s)
- OCR: ML Kit Text Recognition (한국어/영문)

## 개발 환경 세팅

### 필수 설치
- Flutter SDK 3.19 이상 (https://flutter.dev/docs/get-started/install/windows)
- Android Studio (https://developer.android.com/studio)
- Git (https://git-scm.com/download/win)
- Git LFS (https://git-lfs.com) ← 반드시 설치!

### 설치 확인
```bash
flutter --version
git --version
git lfs version
```

### 프로젝트 세팅
```bash
git lfs install
git clone https://github.com/PotatosUffy/garim.git
cd garim
git lfs pull
flutter pub get
flutter run
```

### 주의사항
- iOS 빌드 불가 (Mac에서만 가능)
- 첫 빌드 시 NDK 자동 설치로 시간 걸림
- git lfs pull 안하면 모델 파일 오류 발생

### 문제 발생 시
```bash
flutter clean
flutter pub get
flutter run
```

## 코드 업데이트 방법

### 내 수정사항 올리기
```bash
git add .
git commit -m "수정 내용 간단히 설명"
git push
```

### 팀원 수정사항 받아오기
```bash
git pull
```

### 전체 흐름
수정 전 → git pull (최신 코드 받기)
코드 수정
git add .
git commit -m "설명"
git push

### 주의사항
- 작업 전 항상 git pull 먼저 할 것
- 충돌(conflict) 발생 시 팀장에게 문의

## 업데이트 내역

### v1.1.0 (2026-05-05)
- 블러 효과 3가지 추가 (흐림/모자이크/스티커)
- 블러 강도 슬라이더 추가
- 카드 PII 추출 고도화 (카드번호/영문이름/CVC)
- 카드 영역 OCR 전처리 추가 (대비/선명도/샤프닝)
- 카드 출력 shape 자동 감지 ([1,5,8400] / [1,300,6])
- 운송장 개인정보 패턴 추가
- MRZ 파싱 개선 (이름/여권번호/생년월일 분리 표시)
- 탐지 우선순위 적용 (번호판 > 카드 > 문서)

### v1.0.0 (2026-05-04)
- 프로젝트 초기 생성
- 얼굴/번호판/문서/카드 탐지 구현
- 유형별 블러 ON/OFF 스위치
- 문서/카드 텍스트 탐지 및 부분 블러
- GitHub 배포
