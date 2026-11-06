-- ══════════════════════════════════════════════════════════════
--  2026 절임배추 특별 주문 — 담당자가 수령일(발송일)·받는 곳(주소·매장) 바꾸기  (2026-11-06 더함)
--  화면: jjcoop.co.kr/2026절임배추주문/desk.html
--
--  주문하신 분이 처음 고른 날짜(date_baechu·date_sok·date_kit)는 그대로 둔다.
--  수정 요청을 받아 바꾼 날짜는 새 칸(chg_date_…)에 따로 적는다.
--  새 칸이 비어 있으면 처음 날짜대로, 차 있으면 바꾼 날짜대로 보낸다.
--
--  ※ 「절임배추주문_담당자화면.sql」을 먼저 실행한 뒤에 실행한다.
--  ※ 두 번 실행해도 안전합니다.
-- ══════════════════════════════════════════════════════════════

-- 바꾼 발송일 칸 + 언제 바꿨는지
alter table public.kimjang_orders add column if not exists chg_date_baechu date;
alter table public.kimjang_orders add column if not exists chg_date_sok    date;
alter table public.kimjang_orders add column if not exists chg_date_kit    date;
alter table public.kimjang_orders add column if not exists chg_at          timestamptz;

-- 바꾼 받는 곳(주소 또는 매장) 칸 — 처음 주소(zipcode·address·address_detail)는 그대로 둔다
--  매장 수령은 처음과 같은 모양으로 chg_address 에 「매장수령 · ○○점」을 적는다
alter table public.kimjang_orders add column if not exists chg_zipcode        text;
alter table public.kimjang_orders add column if not exists chg_address        text;
alter table public.kimjang_orders add column if not exists chg_address_detail text;
alter table public.kimjang_orders add column if not exists chg_addr_at        timestamptz;


-- ── 주문 목록 (바꾼 날짜도 함께 내보내도록 다시 만듦) ─────────
create or replace function public.kimjang_desk_list(p_pass text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare err text;
begin
  err := public.kimjang_desk_check(p_pass);
  if err is not null then return json_build_object('error', err); end if;
  return json_build_object('orders', coalesce((
    select json_agg(o order by o.id desc) from (
      select id, created_at, orderer_name, orderer_phone, recipient_name, recipient_phone,
             zipcode, address, address_detail,
             qty_baechu, date_baechu, qty_sok, date_sok, qty_kit, date_kit,
             chg_date_baechu, chg_date_sok, chg_date_kit, chg_at,
             chg_zipcode, chg_address, chg_address_detail, chg_addr_at,
             total_amount, memo, paid, canceled
      from public.kimjang_orders) o), '[]'::json));
end
$$;
revoke all on function public.kimjang_desk_list(text) from public;
grant execute on function public.kimjang_desk_list(text) to anon;


-- ── 수령일 바꾸기 ─────────────────────────────────────────────
--  p_item: 'baechu' | 'sok' | 'kit'
--  p_date: 새 발송일. null 이면 「처음 날짜로 되돌리기」
create or replace function public.kimjang_desk_set_date(p_pass text, p_id bigint, p_item text, p_date date)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  err text;
  ok_dates date[] := array[
    '2026-11-17','2026-11-18','2026-11-19','2026-11-20',
    '2026-11-24','2026-11-25','2026-11-26','2026-11-27',
    '2026-12-01','2026-12-02','2026-12-03','2026-12-04',
    '2026-12-08','2026-12-09','2026-12-10','2026-12-11',
    '2026-12-15','2026-12-16','2026-12-17','2026-12-18']::date[];
  kit_dates date[] := array['2026-12-15','2026-12-16','2026-12-17','2026-12-18']::date[];
  o public.kimjang_orders%rowtype;
begin
  err := public.kimjang_desk_check(p_pass);
  if err is not null then return json_build_object('error', err); end if;

  select * into o from public.kimjang_orders where id = p_id;
  if not found then return json_build_object('error', '그 주문을 찾지 못했습니다.'); end if;

  if p_date is not null then
    if (p_item = 'kit' and not (p_date = any(kit_dates)))
       or (p_item <> 'kit' and not (p_date = any(ok_dates))) then
      return json_build_object('error', '고를 수 없는 날짜입니다.');
    end if;
  end if;

  if p_item = 'baechu' then
    if o.qty_baechu = 0 then return json_build_object('error', '이 주문에는 절임배추가 없습니다.'); end if;
    update public.kimjang_orders
       set chg_date_baechu = case when p_date = o.date_baechu then null else p_date end, chg_at = now()
     where id = p_id;
  elsif p_item = 'sok' then
    if o.qty_sok = 0 then return json_build_object('error', '이 주문에는 김치속이 없습니다.'); end if;
    update public.kimjang_orders
       set chg_date_sok = case when p_date = o.date_sok then null else p_date end, chg_at = now()
     where id = p_id;
  elsif p_item = 'kit' then
    if o.qty_kit = 0 then return json_build_object('error', '이 주문에는 김장밀키트가 없습니다.'); end if;
    update public.kimjang_orders
       set chg_date_kit = case when p_date = o.date_kit then null else p_date end, chg_at = now()
     where id = p_id;
  else
    return json_build_object('error', '바꿀 수 없는 칸입니다.');
  end if;

  return json_build_object('ok', true);
end
$$;
revoke all on function public.kimjang_desk_set_date(text,bigint,text,date) from public;
grant execute on function public.kimjang_desk_set_date(text,bigint,text,date) to anon;


-- ── 받는 곳(주소 · 매장) 바꾸기 ───────────────────────────────
--  p_address: 새 주소, 또는 「매장수령 · 금산점/초전점/진양호점」
--             null 이면 「처음 주소로 되돌리기」
create or replace function public.kimjang_desk_set_addr(p_pass text, p_id bigint, p_zipcode text, p_address text, p_address_detail text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  err text;
  a text := nullif(btrim(coalesce(p_address,'')),'');
  z text := nullif(btrim(coalesce(p_zipcode,'')),'');
  d text := nullif(btrim(coalesce(p_address_detail,'')),'');
begin
  err := public.kimjang_desk_check(p_pass);
  if err is not null then return json_build_object('error', err); end if;

  if a is null then
    update public.kimjang_orders
       set chg_zipcode = null, chg_address = null, chg_address_detail = null, chg_addr_at = now()
     where id = p_id;
  else
    if a like '매장수령%' then
      if a not in ('매장수령 · 금산점','매장수령 · 초전점','매장수령 · 진양호점') then
        return json_build_object('error', '매장 이름을 확인해 주세요.');
      end if;
      z := null; d := null;
    elsif char_length(a) not between 5 and 200
       or char_length(coalesce(d,'')) > 100
       or char_length(coalesce(z,'')) > 10 then
      return json_build_object('error', '주소를 확인해 주세요.');
    end if;
    update public.kimjang_orders
       set chg_zipcode = z, chg_address = a, chg_address_detail = d, chg_addr_at = now()
     where id = p_id;
  end if;
  if not found then return json_build_object('error', '그 주문을 찾지 못했습니다.'); end if;
  return json_build_object('ok', true);
end
$$;
revoke all on function public.kimjang_desk_set_addr(text,bigint,text,text,text) from public;
grant execute on function public.kimjang_desk_set_addr(text,bigint,text,text,text) to anon;

notify pgrst, 'reload schema';
