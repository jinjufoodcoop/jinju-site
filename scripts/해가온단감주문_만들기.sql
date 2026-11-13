-- ══════════════════════════════════════════════════════════════
--  2026 해가온 못난이 단감 주문 — 주문 받는 자리 + 담당자 화면
--  주문 페이지: jjcoop.co.kr/2026해가온단감/
--  담당자 화면: jjcoop.co.kr/2026해가온단감/desk.html
--
--  【하는 법】
--   1. https://supabase.com 에 로그인 → 진주텃밭 프로젝트
--   2. 왼쪽 메뉴 「SQL Editor」
--   3. 이 파일 내용을 전부 복사해서 붙여넣기 → 오른쪽 아래 「Run」
--      (「잠재적 문제 감지」 창이 뜨면 한 번 더 눌러 실행)
--   4. 초록색 "Success" 가 뜨면 끝
--
--  ※ 두 번 실행해도 안전합니다.
--
--  【지키는 것】
--   - 홈페이지에서는 「주문 넣기」만 됩니다. 남의 주문(이름·전화·주소)은 아무도 못 봅니다.
--   - 금액은 서버가 직접 계산합니다 (10kg 1상자 35,000원, 택배비 포함).
--   - 담당자 화면 비밀번호는 절임배추 담당자 화면과 같은 것을 씁니다 (kimjang_desk_check).
--   - 마감 날짜는 정하지 않았습니다. 담당자 화면의 「주문 받기 멈추기」 단추로 닫고 엽니다.
-- ══════════════════════════════════════════════════════════════


-- ── 1. 주문 표 ────────────────────────────────────────────────
create table if not exists public.dangam_orders (
  id              bigint      generated always as identity primary key,
  created_at      timestamptz not null default now(),
  orderer_name    text        not null,  -- 주문자 (= 입금자명)
  orderer_phone   text        not null,
  recipient_name  text        not null,  -- 받는 분
  recipient_phone text        not null,
  zipcode         text,
  address         text        not null,
  address_detail  text,
  qty             int         not null,  -- 10kg 상자 수
  total_amount    int         not null,  -- 입금할 금액 (서버 계산)
  memo            text,                  -- 배송 요청사항
  paid            boolean     not null default false,  -- 입금 확인
  paid_date       date,                                -- 입금일
  payer_name      text,                                -- 입금자명 (주문자와 다를 때만)
  shipped         boolean     not null default false,  -- 발송함
  canceled        boolean     not null default false,  -- 취소
  staff_note      text                                 -- 직원 메모
);
create index if not exists dangam_orders_created_idx on public.dangam_orders (created_at desc);

alter table public.dangam_orders enable row level security;
revoke all on public.dangam_orders from anon, authenticated;


-- ── 2. 주문 받기 열림/닫힘 ────────────────────────────────────
create table if not exists public.dangam_setting (
  id   int     primary key default 1 check (id = 1),
  open boolean not null default true
);
insert into public.dangam_setting (id, open) values (1, true) on conflict (id) do nothing;
alter table public.dangam_setting enable row level security;
revoke all on public.dangam_setting from anon, authenticated;

-- 주문 페이지가 열릴 때 「지금 주문 받는 중인가」만 묻는다
create or replace function public.dangam_status()
returns json
language sql
security definer
set search_path = public
as $$
  select json_build_object('open', coalesce((select open from public.dangam_setting where id = 1), true));
$$;
revoke all on function public.dangam_status() from public;
grant execute on function public.dangam_status() to anon;


-- ── 3. 주문 넣기 (홈페이지는 이것만 부를 수 있다) ─────────────
create or replace function public.place_dangam_order(
  p_orderer_name    text,
  p_orderer_phone   text,
  p_recipient_name  text,
  p_recipient_phone text,
  p_zipcode         text,
  p_address         text,
  p_address_detail  text,
  p_qty             int,
  p_memo            text
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  q int := coalesce(p_qty, 0);
  total int;
  new_id bigint;
begin
  if not coalesce((select open from public.dangam_setting where id = 1), true) then
    raise exception '주문을 마감했습니다. 고맙습니다.' using errcode = '23514';
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
  if q not between 1 and 20 then
    raise exception '20상자가 넘는 주문은 사무국(055-763-1243)으로 연락 주세요.' using errcode = '23514';
  end if;

  -- 같은 시각에 쏟아붓는 것 막기 (1분에 20건까지)
  if (select count(*) from public.dangam_orders where created_at > now() - interval '1 minute') >= 20 then
    raise exception '잠시 뒤에 다시 눌러 주세요.' using errcode = '23514';
  end if;

  total := q * 35000;   -- 택배비 포함

  insert into public.dangam_orders (
    orderer_name, orderer_phone, recipient_name, recipient_phone,
    zipcode, address, address_detail, qty, total_amount, memo)
  values (
    btrim(p_orderer_name), btrim(p_orderer_phone), btrim(p_recipient_name), btrim(p_recipient_phone),
    nullif(btrim(coalesce(p_zipcode,'')),''), btrim(p_address), nullif(btrim(coalesce(p_address_detail,'')),''),
    q, total, nullif(btrim(coalesce(p_memo,'')),''))
  returning id into new_id;

  return json_build_object('order_no', new_id, 'total', total);
end
$$;
revoke all on function public.place_dangam_order(text,text,text,text,text,text,text,int,text) from public;
grant execute on function public.place_dangam_order(text,text,text,text,text,text,text,int,text) to anon;


-- ── 4. 담당자: 주문 목록 (비밀번호는 절임배추 담당자 화면과 같음) ──
create or replace function public.dangam_desk_list(p_pass text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare err text;
begin
  err := public.kimjang_desk_check(p_pass);
  if err is not null then return json_build_object('error', err); end if;
  return json_build_object(
    'open', coalesce((select open from public.dangam_setting where id = 1), true),
    'orders', coalesce((
      select json_agg(o order by o.id desc) from (
        select id, created_at, orderer_name, orderer_phone, recipient_name, recipient_phone,
               zipcode, address, address_detail, qty, total_amount, memo,
               paid, paid_date, payer_name, shipped, canceled, staff_note
        from public.dangam_orders) o), '[]'::json));
end
$$;
revoke all on function public.dangam_desk_list(text) from public;
grant execute on function public.dangam_desk_list(text) to anon;


-- ── 5. 담당자: 입금확인 · 발송 · 취소 · 메모 ──────────────────
create or replace function public.dangam_desk_mark(
  p_pass text, p_id bigint, p_field text, p_value boolean,
  p_date date default null, p_text text default null)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare err text;
begin
  err := public.kimjang_desk_check(p_pass);
  if err is not null then return json_build_object('error', err); end if;
  if p_field = 'paid' then
    update public.dangam_orders
       set paid = coalesce(p_value,false),
           paid_date  = case when coalesce(p_value,false) then coalesce(p_date, (now() at time zone 'Asia/Seoul')::date) end,
           payer_name = case when coalesce(p_value,false) then nullif(btrim(coalesce(p_text,'')),'') end
     where id = p_id;
  elsif p_field = 'shipped' then
    update public.dangam_orders set shipped = coalesce(p_value,false) where id = p_id;
  elsif p_field = 'canceled' then
    update public.dangam_orders set canceled = coalesce(p_value,false) where id = p_id;
  elsif p_field = 'note' then
    update public.dangam_orders set staff_note = nullif(left(btrim(coalesce(p_text,'')),300),'') where id = p_id;
  else
    return json_build_object('error', '바꿀 수 없는 칸입니다.');
  end if;
  if not found then return json_build_object('error', '그 주문을 찾지 못했습니다.'); end if;
  return json_build_object('ok', true);
end
$$;
revoke all on function public.dangam_desk_mark(text,bigint,text,boolean,date,text) from public;
grant execute on function public.dangam_desk_mark(text,bigint,text,boolean,date,text) to anon;


-- ── 6. 담당자: 주문 받기 멈추기 / 다시 열기 ───────────────────
create or replace function public.dangam_desk_set_open(p_pass text, p_open boolean)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare err text;
begin
  err := public.kimjang_desk_check(p_pass);
  if err is not null then return json_build_object('error', err); end if;
  update public.dangam_setting set open = coalesce(p_open, true) where id = 1;
  return json_build_object('ok', true, 'open', coalesce(p_open, true));
end
$$;
revoke all on function public.dangam_desk_set_open(text,boolean) from public;
grant execute on function public.dangam_desk_set_open(text,boolean) to anon;


-- ── 7. 홈페이지가 바로 알아보게 ───────────────────────────────
notify pgrst, 'reload schema';

-- 확인: 아래 한 줄을 실행해 {"open" : true} 가 나오면 정상입니다.
--   select public.dangam_status();
