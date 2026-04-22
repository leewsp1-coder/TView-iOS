#!/usr/bin/env python3
"""
전국무인교통단속카메라 데이터 로컬 수집 스크립트
실행: python3 scripts/fetch_cameras.py <API_KEY>
"""

import sys, json, requests

BASE_URL = "https://api.data.go.kr/openapi/tn_pubr_public_unmanned_traffic_camera_api"
OUTPUT   = "TView/Resources/SpeedCameras.json"
PAGE_SIZE = 1000

def main():
    if len(sys.argv) < 2:
        print("사용법: python3 scripts/fetch_cameras.py <공공데이터_API_KEY>")
        sys.exit(1)

    key = sys.argv[1].strip()
    cameras = []
    page = 1

    while True:
        params = {"serviceKey": key, "pageNo": page, "numOfRows": PAGE_SIZE, "type": "json"}
        print(f"  [{page}페이지] 요청 중...", end=" ", flush=True)

        try:
            r = requests.get(BASE_URL, params=params, timeout=60)
            r.raise_for_status()
        except Exception as e:
            print(f"❌ 실패: {e}")
            sys.exit(1)

        data = r.json()
        header = data.get("response", {}).get("header", {})
        if header.get("resultCode") != "00":
            print(f"❌ API 오류: {header.get('resultMsg')}")
            sys.exit(1)

        body       = data["response"]["body"]
        total      = int(body.get("totalCount", 0))
        items_raw  = body.get("items", {}).get("item", [])
        if isinstance(items_raw, dict):
            items_raw = [items_raw]

        for it in items_raw:
            try:
                lat = float(it.get("위도") or 0)
                lng = float(it.get("경도") or 0)
                if not (33.0 <= lat <= 38.5 and 124.5 <= lng <= 130.5):
                    continue

                limit_raw = it.get("제한속도") or "60"
                try:
                    limit = int(float(str(limit_raw).strip()))
                except Exception:
                    limit = 60

                dan_type    = str(it.get("단속구분") or "").strip()
                section_pos = str(it.get("단속구간위치구분") or "").strip()

                if "과속" in dan_type:
                    cam_type = "구간단속" if section_pos in ("구간시작", "구간끝", "구간") else "고정식"
                elif "구간" in dan_type:
                    cam_type = "구간단속"
                else:
                    continue  # 신호위반·주정차 등 제외

                cameras.append({"lat": round(lat, 6), "lng": round(lng, 6),
                                 "limit": limit, "type": cam_type})
            except Exception:
                continue

        print(f"수집 {len(items_raw)}건 → 누적 과속카메라 {len(cameras)}개")

        if page * PAGE_SIZE >= total:
            break
        page += 1

    if not cameras:
        print("⚠️  수집된 데이터 없음")
        sys.exit(1)

    output = {
        "_note": f"총 {len(cameras)}개 과속단속카메라 | data.go.kr 전국무인교통단속카메라표준데이터",
        "cameras": cameras
    }
    with open(OUTPUT, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    print(f"\n✅ {len(cameras)}개 카메라 저장 완료 → {OUTPUT}")
    print("다음 단계: git add TView/Resources/SpeedCameras.json && git commit -m 'chore: 카메라 데이터 업데이트' && git push")

if __name__ == "__main__":
    main()
