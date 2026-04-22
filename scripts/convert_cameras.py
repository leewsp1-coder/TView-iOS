#!/usr/bin/env python3
"""
공공데이터포털 단속카메라 CSV → SpeedCameras.json 변환 스크립트

사용법:
  python3 convert_cameras.py [입력CSV파일] [출력JSON파일]
  python3 convert_cameras.py cameras.csv ../TView/Resources/SpeedCameras.json

데이터 다운로드:
  1. https://www.data.go.kr 접속
  2. "도로교통공단_고정식단속카메라" 검색
  3. CSV 또는 JSON 다운로드
  4. 이 스크립트로 변환 후 SpeedCameras.json 교체

지원 형식:
  - 도로교통공단 고정식단속카메라 CSV (위도/경도/제한속도 컬럼 포함)
  - 직접 제작한 CSV (lat,lng,limit,type 컬럼)
"""

import json
import csv
import sys
import os

# ──────────────────────────────────────────
# 컬럼 이름 후보 (공공데이터 포털마다 다름)
# ──────────────────────────────────────────
LAT_COLS   = ["위도", "lat", "latitude", "LAT", "위도(WGS84)"]
LNG_COLS   = ["경도", "lng", "longitude", "LNG", "경도(WGS84)"]
LIMIT_COLS = ["제한속도", "limit", "speed_limit", "제한속도(km/h)", "단속제한속도"]
TYPE_COLS  = ["단속유형", "type", "카메라유형", "설치유형", "단속카메라종류"]

def find_col(headers, candidates):
    """헤더 목록에서 후보 컬럼명을 찾아 반환"""
    for c in candidates:
        if c in headers:
            return c
    # 부분 일치
    for h in headers:
        for c in candidates:
            if c.lower() in h.lower():
                return h
    return None

def normalize_type(raw: str) -> str:
    """단속 유형 정규화"""
    if not raw:
        return "고정식"
    raw = raw.strip()
    if "구간" in raw:
        return "구간단속"
    if "이동" in raw:
        return "이동식"
    return "고정식"

def convert_csv(input_path: str, output_path: str):
    cameras = []
    skipped = 0

    # 인코딩 자동 감지 (CP949, UTF-8, UTF-8-BOM)
    for enc in ["utf-8-sig", "cp949", "utf-8", "euc-kr"]:
        try:
            with open(input_path, "r", encoding=enc) as f:
                reader = csv.DictReader(f)
                headers = reader.fieldnames or []

                lat_col   = find_col(headers, LAT_COLS)
                lng_col   = find_col(headers, LNG_COLS)
                limit_col = find_col(headers, LIMIT_COLS)
                type_col  = find_col(headers, TYPE_COLS)

                if not lat_col or not lng_col:
                    print(f"[{enc}] 위도/경도 컬럼을 찾지 못했습니다.")
                    print(f"  발견된 컬럼: {headers}")
                    continue

                print(f"인코딩: {enc}")
                print(f"위도 컬럼: {lat_col}")
                print(f"경도 컬럼: {lng_col}")
                print(f"제한속도: {limit_col or '없음 (기본 60km/h 사용)'}")
                print(f"단속유형: {type_col or '없음 (기본 고정식 사용)'}")

                for row in reader:
                    try:
                        lat = float(row[lat_col])
                        lng = float(row[lng_col])

                        # 한국 영역 필터 (위도 33~38, 경도 125~130)
                        if not (33.0 <= lat <= 38.5 and 124.5 <= lng <= 130.5):
                            skipped += 1
                            continue

                        limit = 60
                        if limit_col and row.get(limit_col):
                            try:
                                limit = int(float(row[limit_col]))
                            except ValueError:
                                pass

                        cam_type = "고정식"
                        if type_col and row.get(type_col):
                            cam_type = normalize_type(row[type_col])

                        cameras.append({
                            "lat":   round(lat, 6),
                            "lng":   round(lng, 6),
                            "limit": limit,
                            "type":  cam_type
                        })
                    except (ValueError, KeyError):
                        skipped += 1
                        continue

            break  # 성공한 인코딩으로 처리 완료
        except UnicodeDecodeError:
            cameras = []
            continue

    if not cameras:
        print("오류: 변환된 카메라 데이터가 없습니다.")
        print("CSV 파일 구조를 확인하고 컬럼명을 스크립트 상단의 후보 목록에 추가하세요.")
        sys.exit(1)

    # 중복 제거 (같은 좌표 0.001도 이내)
    unique = []
    for cam in cameras:
        is_dup = any(
            abs(cam["lat"] - u["lat"]) < 0.001 and abs(cam["lng"] - u["lng"]) < 0.001
            for u in unique
        )
        if not is_dup:
            unique.append(cam)

    output = {
        "_note": (
            f"총 {len(unique)}개 단속카메라 | "
            "data.go.kr 도로교통공단 데이터 기반 | "
            "format: lat(위도), lng(경도), limit(km/h), type(고정식|구간단속|이동식)"
        ),
        "cameras": unique
    }

    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    print(f"\n✅ 변환 완료")
    print(f"   총 카메라: {len(cameras)}개")
    print(f"   중복 제거 후: {len(unique)}개")
    print(f"   건너뜀: {skipped}개")
    print(f"   출력 파일: {output_path}")
    print(f"   파일 크기: {os.path.getsize(output_path) / 1024:.1f} KB")


def print_usage():
    print("사용법:")
    print("  python3 convert_cameras.py <입력CSV> <출력JSON>")
    print("")
    print("예시:")
    print("  python3 convert_cameras.py ~/Downloads/cameras.csv ../TView/Resources/SpeedCameras.json")
    print("")
    print("공공데이터 다운로드:")
    print("  https://www.data.go.kr → '도로교통공단 고정식단속카메라' 검색")


if __name__ == "__main__":
    if len(sys.argv) == 3:
        convert_csv(sys.argv[1], sys.argv[2])
    elif len(sys.argv) == 2:
        # 출력 파일 기본값
        convert_csv(sys.argv[1], "../TView/Resources/SpeedCameras.json")
    else:
        print_usage()
        sys.exit(1)
