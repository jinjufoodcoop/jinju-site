-- ══════════════════════════════════════════════════════════════
--  2026 절임배추 특별 주문 — 택배 송장번호 (로젠택배)  (2026-11-13 더함)
--  담당자 화면(desk.html)에서 상품마다 송장번호를 적으면,
--  「내 주문 확인」(check.html)에 송장번호와 로젠택배 배송조회 단추가 나온다.
--
--  상품마다 따로 적는다 (절임배추·김치속·김장밀키트는 발송일이 다를 수 있어서).
--  한 상품에 상자가 여러 개면 송장번호도 여러 개 → 쉼표로 이어서 한 칸에 둔다.
--  숫자만 남기고(하이픈·띄어쓰기 지움) 같은 번호는 한 번만 둔다. 비우면 지운다.
--
--  ※ 「절임배추주문_주문자명.sql」까지 실행한 뒤에 실행한다.
--  ※ 두 번 실행해도 안전합니다.
--  ※ 이 SQL을 먼저 실행하고 나서 desk.html · check.html 을 올린다.
-- ══════════════════════════════════════════════════════════════

alter table public.kimjang_orders add column if not exists track_baechu text;
alter table public.kimjang_orders add column if not exists track_sok    text;
alter table public.kimjang_orders add column if not exists track_kit    text;
alter table public.kimjang_orders add column if not exists track_at     timestamptz;


-- ── 송장번호 적기 (담당자 화면에서만) ────────────────────────
create or replace function public.kimjang_desk_set_track(p_pass text, p_id bigint, p_item text, p_nums text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  err text;
  nums text[];
  bad text;
  v text;
begin
  err := public.kimjang_desk_check(p_pass);
  if err is not null then return json_build_object('error', err); end if;

  if p_item not in ('baechu','sok','kit') then
    return json_build_object('error', '상품을 확인해 주세요.');
  end if;
  if not exists (select 1 from public.kimjang_orders where id = p_id) then
    return json_build_object('error', '그 주문을 찾지 못했습니다.');
  end if;

  -- 쉼표·띄어쓰기·줄바꿈으로 나누고, 하이픈 등은 지워 숫자만 남긴다 (적은 순서 그대로, 같은 번호는 한 번만)
  select array_agg(n order by first_pos) into nums from (
    select n, min(pos) as first_pos from (
      select regexp_replace(t, '[^0-9]', '', 'g') as n, pos
      from regexp_split_to_table(coalesce(p_nums, ''), '[,\s/]+') with ordinality as s(t, pos)
    ) a where n <> '' group by n
  ) b;

  if nums is not null then
    if array_length(nums, 1) > 30 then
      return json_build_object('error', '송장번호는 한 상품에 30개까지 적을 수 있습니다.');
    end if;
    select x into bad from unnest(nums) x where char_length(x) not between 9 and 14 limit 1;
    if bad is not null then
      return json_build_object('error', '송장번호 「' || bad || '」를 확인해 주세요. (숫자 9~14자리)');
    end if;
    v := array_to_string(nums, ',');
  end if;

  execute format('update public.kimjang_orders set track_%s = $1, track_at = now() where id = $2', p_item)
    using v, p_id;
  return json_build_object('ok', true, 'nums', v);
end
$$;
revoke all on function public.kimjang_desk_set_track(text,bigint,text,text) from public;
grant execute on function public.kimjang_desk_set_track(text,bigint,text,text) to anon;


-- ── 주문 목록 (송장번호도 함께 내보내도록 다시 만듦) ────────
--  「절임배추주문_주문자명.sql」의 함수와 같고, 맨 끝에 track_ 칸만 더했다.
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
             orig_orderer_name, chg_name_at, orig_recipient_name, chg_rname_at,
             total_amount, memo, paid, paid_date, payer_name, canceled,
             track_baechu, track_sok, track_kit, track_at
      from public.kimjang_orders) o), '[]'::json));
end
$$;
revoke all on function public.kimjang_desk_list(text) from public;
grant execute on function public.kimjang_desk_list(text) to anon;


-- ── 내 주문 확인 (주문하신 분 화면) — 송장번호도 보여 주기 ──
--  「절임배추주문_주문자명.sql」의 함수와 같고, track_ 칸만 더했다. 취소된 주문은 송장번호를 내보내지 않는다.
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
      case when o.canceled then null else o.track_baechu end as track_baechu,
      case when o.canceled then null else o.track_sok    end as track_sok,
      case when o.canceled then null else o.track_kit    end as track_kit,
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
    where (o.orderer_name = nm or o.orig_orderer_name = nm)
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
