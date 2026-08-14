#!/usr/bin/env python3
"""진주텃밭 가격태그 목록 굽기 — Supabase v_price_tag → tags-data.json

가격표 화면이 DB를 직접 읽지 않는 이유:
  ① 대상이 '정가가 고정된 상품'이라 실시간 조회가 필요 없다
  ② 브라우저에 Supabase 키를 심지 않아도 된다
  ③ 매장 인터넷이 느려도 즉시 열린다

가격이 바뀌거나 매출이 새로 적재되면 이 스크립트를 다시 돌린다.

  python3 scripts/build_tag_data.py            # 굽기
  python3 scripts/build_tag_data.py --dry-run  # 파일 안 쓰고 결과만 보기

.env 필요: JINJU_SUPABASE_URL, JINJU_SUPABASE_SECRET_KEY
"""
import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone, timedelta

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'tags-data.json')
ENV = os.path.expanduser('~/poomasi/.env')
KST = timezone(timedelta(hours=9))

# 태그에 실제로 찍히는 것만 내보낸다. 나머지 열은 화면이 쓰지 않는다.
# sale_count는 내보내지 않는다 — 화면이 안 쓰고, public 레포라 품목별 판매량(내부 영업 데이터)이 영구 공개된다
COLUMNS = 'barcode,product_name,farmer_name,unit,price,item_category'


def load_env():
    if not os.path.exists(ENV):
        sys.exit(f'.env 없음: {ENV}')
    env = {}
    with open(ENV, encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#') or '=' not in line:
                continue
            k, v = line.split('=', 1)
            env[k.strip()] = v.strip().strip('"').strip("'")
    url = env.get('JINJU_SUPABASE_URL')
    key = env.get('JINJU_SUPABASE_SECRET_KEY')
    if not url or not key:
        sys.exit('.env에 JINJU_SUPABASE_URL / JINJU_SUPABASE_SECRET_KEY 가 필요하다')
    return url.rstrip('/'), key


def fetch(url, key):
    """1000행 제한이 있으니 끝까지 페이지를 넘긴다."""
    rows, offset = [], 0
    while True:
        endpoint = (f'{url}/rest/v1/v_price_tag?select={COLUMNS}'
                    f'&order=item_category.asc,product_name.asc&limit=1000&offset={offset}')
        out = subprocess.run(
            ['curl', '-sS', '-f', endpoint,
             '-H', f'apikey: {key}', '-H', f'Authorization: Bearer {key}'],
            capture_output=True, text=True)
        if out.returncode != 0:
            sys.exit(f'조회 실패(offset={offset}): {out.stderr.strip()[:300]}')
        page = json.loads(out.stdout)
        rows += page
        if len(page) < 1000:
            return rows
        offset += 1000


def check(rows):
    """구운 결과가 태그로 쓸 만한지 검산. 하나라도 걸리면 멈춘다."""
    problems = []
    if not rows:
        problems.append('행이 0개다')
    for r in rows:
        if not r.get('product_name'):
            problems.append(f'상품명 없음: {r}')
        if not isinstance(r.get('price'), int) or r['price'] <= 0:
            problems.append(f'가격 이상: {r.get("product_name")} = {r.get("price")}')
        if '�' in json.dumps(r, ensure_ascii=False):
            problems.append(f'깨진 글자: {r.get("product_name")}')
    names = [r['product_name'] for r in rows]
    if len(names) != len(set(names)):
        problems.append('상품명 중복 있음')
    return problems


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true', help='파일을 쓰지 않는다')
    args = ap.parse_args()

    url, key = load_env()
    rows = fetch(url, key)

    problems = check(rows)
    if problems:
        print(f'검산 실패 {len(problems)}건 — 파일을 쓰지 않았다', file=sys.stderr)
        for p in problems[:10]:
            print(' -', p, file=sys.stderr)
        sys.exit(1)

    data = {
        'built_at': datetime.now(KST).strftime('%Y-%m-%d %H:%M'),
        'count': len(rows),
        'note': '전자저울(벌크) 제외 · 최근 6개월 거래 · 최빈단가 점유율 95% 이상. '
                'price는 정가가 아니라 실판매 최빈단가다.',
        'products': rows,
    }

    cats = {}
    for r in rows:
        cats[r.get('item_category') or '(분류없음)'] = cats.get(r.get('item_category') or '(분류없음)', 0) + 1
    print(f'{len(rows)}개 · A4 {-(-len(rows)//18)}장')
    for c, n in sorted(cats.items(), key=lambda x: -x[1])[:8]:
        print(f'  {c}: {n}')

    if args.dry_run:
        print('(dry-run — 파일 안 씀)')
        return
    with open(OUT, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, separators=(',', ':'))
    print(f'→ {OUT} ({os.path.getsize(OUT)//1024}KB)')


if __name__ == '__main__':
    main()
