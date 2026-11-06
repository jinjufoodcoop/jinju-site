-- ══════════════════════════════════════════════════════════════
--  2026 절임배추 특별 주문 — 담당자가 수량(상자 수) 바꾸기  (2026-11-06 더함)
--  화면: jjcoop.co.kr/2026절임배추주문/desk.html
--
--  주문하신 분이 처음 고른 수량(qty_…)과 금액(total_amount)은 그대로 둔다.
--  바꾼 수량은 새 칸(chg_qty_…)에, 다시 계산한 금액은 chg_total_amount 에 따로 적는다.
--  새 칸이 비어 있으면 처음 수량·금액대로, 차 있으면 바꾼 수량·금액대로 본다.
--  처음에 안 고른 상품(0상자)을 새로 넣을 수도 있다 — 이때는 발송일도 함께 고른다.
--
--  ※ 「절임배추주문_입금자명.sql」까지 실행한 뒤에 실행한다.
--  ※ 두 번 실행해도 안전합니다.
--  ※ 이 SQL을 먼저 실행하고 나서 desk.html을 올린다. (옛 화면도 그대로 돌아간다)
-- ══════════════════════════════════════════════════════════════

alter table public.kimjang_orders add column if not exists chg_qty_baechu   int;
alter table public.kimjang_orders add column if not exists chg_qty_sok      int;
alter table public.kimjang_orders add column if not exists chg_qty_kit      int;
alter table public.kimjang_orders add column if not exists chg_total_amount int;
alter table public.kimjang_orders add column if not exists chg_qty_at       timestamptz;


-- ── 주문 목록 (바꾼 수량·금액도 함께 내보내도록 다시 만듦) ────
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
             chg_qty_baechu, chg_qty_sok, chg_qty_kit, chg_total_amount, chg_qty_at,
             chg_zipcode, chg_address, chg_address_detail, chg_addr_at,
             total_amount, memo, paid, paid_date, payer_name, canceled
      from public.kimjang_orders) o), '[]'::json));
end
$$;
revoke all on function public.kimjang_desk_list(text) from public;
grant execute on function public.kimjang_desk_list(text) to anon;


-- ── 상품 하나의 수량 + 발송일 바꾸기 ─────────────────────────
--  p_item: 'baechu' | 'sok' | 'kit'
--  p_qty : 새 수량 (0~29). 0 이면 그 상품을 뺀다.
--  p_date: 새 발송일. 수량이 1 이상이면 꼭 있어야 한다.
--  처음 수량·날짜와 같게 고르면 「처음대로 되돌리기」로 친다 (바꾼 칸을 비운다).
create or replace function public.kimjang_desk_set_item(p_pass text, p_id bigint, p_item text, p_qty int, p_date date)
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
  qb int; qs int; qk int;          -- 바꾼 뒤 실제 수량
  oq int; od date;                 -- 그 상품의 처음 수량·날짜
  prev_q int; prev_d date;         -- 그 상품의 지금(바꾸기 전) 수량·날짜
  new_cq int; new_cd date; total int;
begin
  err := public.kimjang_desk_check(p_pass);
  if err is not null then return json_build_object('error', err); end if;

  select * into o from public.kimjang_orders where id = p_id for update;
  if not found then return json_build_object('error', '그 주문을 찾지 못했습니다.'); end if;
  if p_item not in ('baechu','sok','kit') then return json_build_object('error', '바꿀 수 없는 칸입니다.'); end if;

  if p_qty is null or p_qty not between 0 and 29 then
    return json_build_object('error', '수량은 0~29상자 사이로 골라 주세요. (30상자 이상은 단체주문)');
  end if;
  if p_qty > 0 then
    if p_date is null then return json_build_object('error', '발송일을 골라 주세요.'); end if;
    if (p_item = 'kit' and not (p_date = any(kit_dates)))
       or (p_item <> 'kit' and not (p_date = any(ok_dates))) then
      return json_build_object('error', '고를 수 없는 날짜입니다.');
    end if;
  end if;

  qb := coalesce(o.chg_qty_baechu, o.qty_baechu);
  qs := coalesce(o.chg_qty_sok,    o.qty_sok);
  qk := coalesce(o.chg_qty_kit,    o.qty_kit);
  if p_item = 'baechu' then
    oq := o.qty_baechu; od := o.date_baechu; prev_q := qb; prev_d := coalesce(o.chg_date_baechu, o.date_baechu); qb := p_qty;
  elsif p_item = 'sok' then
    oq := o.qty_sok;    od := o.date_sok;    prev_q := qs; prev_d := coalesce(o.chg_date_sok, o.date_sok);       qs := p_qty;
  else
    oq := o.qty_kit;    od := o.date_kit;    prev_q := qk; prev_d := coalesce(o.chg_date_kit, o.date_kit);       qk := p_qty;
  end if;

  if qb + qs + qk = 0 then
    return json_build_object('error', '상품이 하나도 없게 됩니다. 주문을 없애려면 「취소」 버튼을 눌러 주세요.');
  end if;

  new_cq := case when p_qty = oq then null else p_qty end;
  new_cd := case when p_qty = 0 or p_date is not distinct from od then null else p_date end;

  -- 10% 할인가, 택배비 무료 (주문 만들 때와 같은 값)
  total := qb * 43200 + qs * 87300 + qk * 65700;

  update public.kimjang_orders set
    chg_qty_baechu  = case when p_item = 'baechu' then new_cq else chg_qty_baechu  end,
    chg_qty_sok     = case when p_item = 'sok'    then new_cq else chg_qty_sok     end,
    chg_qty_kit     = case when p_item = 'kit'    then new_cq else chg_qty_kit     end,
    chg_date_baechu = case when p_item = 'baechu' then new_cd else chg_date_baechu end,
    chg_date_sok    = case when p_item = 'sok'    then new_cd else chg_date_sok    end,
    chg_date_kit    = case when p_item = 'kit'    then new_cd else chg_date_kit    end,
    chg_total_amount = case when total = total_amount then null else total end,
    chg_qty_at = case when p_qty is distinct from prev_q then now() else chg_qty_at end,
    chg_at     = case when p_qty > 0 and p_date is distinct from prev_d then now() else chg_at end
  where id = p_id;

  return json_build_object('ok', true, 'total', total);
end
$$;
revoke all on function public.kimjang_desk_set_item(text,bigint,text,int,date) from public;
grant execute on function public.kimjang_desk_set_item(text,bigint,text,int,date) to anon;


-- ── 내 주문 확인 (주문하신 분 화면) — 바꾼 수량·금액도 반영 ────
--  「절임배추주문_주문조회.sql」의 함수를 그대로 두고, 수량·금액만 바꾼 값으로 보여 준다.
create or replace function public.kimjang_lookup(p_name text, p_phone text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  nm text := btrim(coalesce(p_name,''));
  ph text := regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g');
  v_ip text;
  res json;
begin
  begin
    v_ip := split_part(coalesce(current_setting('request.headers', true)::json ->> 'x-forwarded-for', ''), ',', 1);
  exception when others then v_ip := '';
  end;

  if coalesce(v_ip,'') <> '' and (select count(*) from public.kimjang_lookup_fail
      where at > now() - interval '10 minutes' and ip = v_ip) >= 10 then
    return json_build_object('error', '여러 번 찾지 못해 잠시 막혔습니다. 10분 뒤에 다시 해 주세요.');
  end if;
  if (select count(*) from public.kimjang_lookup_fail where at > now() - interval '1 minute') >= 120 then
    return json_build_object('error', '잠시 뒤에 다시 해 주세요.');
  end if;

  if char_length(nm) not between 1 and 20 or ph !~ '^0[0-9]{8,10}$' then
    return json_build_object('error', '이름과 전화번호를 확인해 주세요.');
  end if;

  select json_agg(x order by x.id desc) into res from (
    select
      o.id,
      o.created_at,
      coalesce(o.chg_qty_baechu, o.qty_baechu) as qty_baechu, coalesce(o.chg_date_baechu, o.date_baechu) as date_baechu,
      coalesce(o.chg_qty_sok,    o.qty_sok)    as qty_sok,    coalesce(o.chg_date_sok,    o.date_sok)    as date_sok,
      coalesce(o.chg_qty_kit,    o.qty_kit)    as qty_kit,    coalesce(o.chg_date_kit,    o.date_kit)    as date_kit,
      coalesce(o.chg_total_amount, o.total_amount) as total_amount,
      o.paid, o.paid_date, o.canceled,
      case when ad.a like '매장수령%'
           then ad.a
           else '택배 · ' || coalesce('(' || ad.z || ') ', '') || ad.a || coalesce(' ' || ad.d, '')
      end as place,
      case when char_length(o.recipient_name) <= 2
           then left(o.recipient_name, 1) || '*'
           else left(o.recipient_name, 1) || repeat('*', char_length(o.recipient_name) - 2) || right(o.recipient_name, 1)
      end as recipient
    from public.kimjang_orders o
    cross join lateral (select
        case when o.chg_address is not null then o.chg_zipcode        else o.zipcode        end as z,
        coalesce(o.chg_address, o.address)                                                      as a,
        case when o.chg_address is not null then o.chg_address_detail else o.address_detail end as d) ad
    where o.orderer_name = nm
      and regexp_replace(o.orderer_phone, '[^0-9]', '', 'g') = ph
  ) x;

  if res is null then
    insert into public.kimjang_lookup_fail (ip) values (v_ip);
    delete from public.kimjang_lookup_fail where at < now() - interval '1 day';
    return json_build_object('orders', '[]'::json);
  end if;
  return json_build_object('orders', res);
end
$$;
revoke all on function public.kimjang_lookup(text,text) from public;
grant execute on function public.kimjang_lookup(text,text) to anon;

notify pgrst, 'reload schema';
