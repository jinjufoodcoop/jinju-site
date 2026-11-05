-- ══════════════════════════════════════════════════════════════
--  2026 절임배추 특별 주문 (4일 이벤트) — 주문 받는 자리 만들기
--  페이지: jjcoop.co.kr/2026절임배추주문/
--
--  【하는 법】
--   1. https://supabase.com 에 로그인 → 진주텃밭 프로젝트
--   2. 왼쪽 메뉴 「SQL Editor」
--   3. 이 파일 내용을 전부 복사해서 붙여넣기 → 오른쪽 아래 「Run」
--   4. 초록색 "Success" 가 뜨면 끝
--
--  ※ 두 번 실행해도 안전합니다.
--
--  【주문 보는 법】 왼쪽 「Table Editor」 → kimjang_orders 표
--   입금 확인되면 paid 칸을 true 로 바꿉니다.
--
--  【지키는 것】
--   - 홈페이지에서는 「주문 넣기」만 됩니다. 남의 주문(이름·전화·주소)은 아무도 못 봅니다.
--   - 가격·합계는 서버가 직접 계산합니다. 화면을 조작해도 금액을 못 바꿉니다.
--   - 2026년 11월 9일(월) 0시(한국 시각)가 지나면 서버가 주문을 받지 않습니다.
-- ══════════════════════════════════════════════════════════════


-- ── 1. 주문 표 ────────────────────────────────────────────────
create table if not exists public.kimjang_orders (
  id              bigint      generated always as identity primary key,
  created_at      timestamptz not null default now(),
  orderer_name    text        not null,  -- 주문자 (= 입금자명)
  orderer_phone   text        not null,
  recipient_name  text        not null,  -- 받는 분
  recipient_phone text        not null,
  zipcode         text,
  address         text        not null,
  address_detail  text,
  qty_baechu      int         not null default 0,  -- 불암플러스 절임배추 20kg
  date_baechu     date,                            -- 발송일
  qty_sok         int         not null default 0,  -- 김치속 7kg
  date_sok        date,
  qty_kit         int         not null default 0,  -- 김장밀키트
  date_kit        date,
  total_amount    int         not null,            -- 입금할 금액 (서버 계산)
  memo            text,                            -- 배송 요청사항
  paid            boolean     not null default false,  -- 입금 확인 (은미님이 표에서 체크)
  staff_note      text                                 -- 직원 메모
);

create index if not exists kimjang_orders_created_idx on public.kimjang_orders (created_at desc);


-- ── 2. 아무도 표를 직접 못 건드리게 ───────────────────────────
alter table public.kimjang_orders enable row level security;
revoke all on public.kimjang_orders from anon, authenticated;


-- ── 3. 주문 넣기 (홈페이지는 이것만 부를 수 있다) ─────────────
create or replace function public.place_kimjang_order(
  p_orderer_name    text,
  p_orderer_phone   text,
  p_recipient_name  text,
  p_recipient_phone text,
  p_zipcode         text,
  p_address         text,
  p_address_detail  text,
  p_qty_baechu      int,
  p_date_baechu     date,
  p_qty_sok         int,
  p_date_sok        date,
  p_qty_kit         int,
  p_date_kit        date,
  p_memo            text
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  -- 출고(발송) 가능한 날 — 보내주신 출고희망일 표 그대로
  ok_dates date[] := array[
    '2026-11-17','2026-11-18','2026-11-19','2026-11-20',
    '2026-11-24','2026-11-25','2026-11-26','2026-11-27',
    '2026-12-01','2026-12-02','2026-12-03','2026-12-04',
    '2026-12-08','2026-12-09','2026-12-10','2026-12-11',
    '2026-12-15','2026-12-16','2026-12-17','2026-12-18']::date[];
  -- 김장밀키트는 12/16~19 수령 → 12/15~18 발송만
  kit_dates date[] := array['2026-12-15','2026-12-16','2026-12-17','2026-12-18']::date[];
  qb int := coalesce(p_qty_baechu, 0);
  qs int := coalesce(p_qty_sok, 0);
  qk int := coalesce(p_qty_kit, 0);
  total int;
  new_id bigint;
begin
  if now() >= timestamptz '2026-11-09 00:00:00+09' then
    raise exception '주문 기간이 끝났습니다.' using errcode = '23514';
  end if;

  if char_length(btrim(coalesce(p_orderer_name,''))) not between 1 and 20
     or char_length(btrim(coalesce(p_recipient_name,''))) not between 1 and 20 then
    raise exception '이름을 확인해 주세요.' using errcode = '23514';
  end if;
  if regexp_replace(coalesce(p_orderer_phone,''),   '[^0-9]', '', 'g') !~ '^0[0-9]{8,10}$'
     or regexp_replace(coalesce(p_recipient_phone,''), '[^0-9]', '', 'g') !~ '^0[0-9]{8,10}$' then
    raise exception '전화번호를 확인해 주세요.' using errcode = '23514';
  end if;
  if char_length(btrim(coalesce(p_address,''))) not between 5 and 200
     or char_length(coalesce(p_address_detail,'')) > 100
     or char_length(coalesce(p_zipcode,'')) > 10
     or char_length(coalesce(p_memo,'')) > 300 then
    raise exception '주소나 요청사항을 확인해 주세요.' using errcode = '23514';
  end if;

  if qb not between 0 and 29 or qs not between 0 and 29 or qk not between 0 and 29 then
    raise exception '30상자 이상은 단체주문으로 사무국(055-763-1243)에 문의해 주세요.' using errcode = '23514';
  end if;
  if qb + qs + qk = 0 then
    raise exception '상품을 1개 이상 골라 주세요.' using errcode = '23514';
  end if;
  if (qb > 0 and not (p_date_baechu = any(ok_dates)))
     or (qs > 0 and not (p_date_sok = any(ok_dates)))
     or (qk > 0 and not (p_date_kit = any(kit_dates))) then
    raise exception '출고희망일을 골라 주세요.' using errcode = '23514';
  end if;

  -- 같은 시각에 쏟아붓는 것 막기 (1분에 20건까지)
  if (select count(*) from public.kimjang_orders
      where created_at > now() - interval '1 minute') >= 20 then
    raise exception '잠시 뒤에 다시 눌러 주세요.' using errcode = '23514';
  end if;

  -- 10% 할인가, 택배비 무료
  total := qb * 43200 + qs * 87300 + qk * 65700;

  insert into public.kimjang_orders (
    orderer_name, orderer_phone, recipient_name, recipient_phone,
    zipcode, address, address_detail,
    qty_baechu, date_baechu, qty_sok, date_sok, qty_kit, date_kit,
    total_amount, memo)
  values (
    btrim(p_orderer_name), btrim(p_orderer_phone), btrim(p_recipient_name), btrim(p_recipient_phone),
    nullif(btrim(coalesce(p_zipcode,'')),''), btrim(p_address), nullif(btrim(coalesce(p_address_detail,'')),''),
    qb, case when qb > 0 then p_date_baechu end,
    qs, case when qs > 0 then p_date_sok end,
    qk, case when qk > 0 then p_date_kit end,
    total, nullif(btrim(coalesce(p_memo,'')),''))
  returning id into new_id;

  return json_build_object('order_no', new_id, 'total', total);
end
$$;

revoke all on function public.place_kimjang_order(text,text,text,text,text,text,text,int,date,int,date,int,date,text) from public;
grant execute on function public.place_kimjang_order(text,text,text,text,text,text,text,int,date,int,date,int,date,text) to anon;


-- ── 4. 홈페이지가 바로 알아보게 ───────────────────────────────
notify pgrst, 'reload schema';

-- 확인: 아래 한 줄을 실행해 빈 표가 나오면 정상입니다.
--   select * from public.kimjang_orders;
