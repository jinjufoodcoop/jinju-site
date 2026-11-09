-- ══════════════════════════════════════════════════════════════
--  2026 절임배추 특별 주문 — 담당자가 주문자 이름 고치기  (2026-11-09 더함)
--  화면: jjcoop.co.kr/2026절임배추주문/desk.html
--
--  주문하신 분이 이름을 잘못 적은 경우(오타) 담당자가 바로잡는다.
--  고친 이름은 orderer_name 에 바로 들어가서 목록·엑셀·입금 확인에 그대로 쓰인다.
--  처음 적은 이름은 orig_orderer_name 에 한 번만 남겨 둔다 (몇 번을 고쳐도 처음 것 그대로).
--  처음 이름으로 다시 고치면 「되돌리기」로 친다 → orig_orderer_name 을 비운다.
--
--  「내 주문 확인」(check.html)은 고친 이름으로도, 처음 적은 이름으로도 찾아진다.
--  받는 분 이름도 같은 방식으로 고친다 (orig_recipient_name). 고치는 것은 담당자 화면에서만 된다.
--
--  ※ 「절임배추주문_수량변경.sql」까지 실행한 뒤에 실행한다.
--  ※ 두 번 실행해도 안전합니다.
--  ※ 이 SQL을 먼저 실행하고 나서 desk.html을 올린다. (옛 화면도 그대로 돌아간다)
-- ══════════════════════════════════════════════════════════════

alter table public.kimjang_orders add column if not exists orig_orderer_name   text;
alter table public.kimjang_orders add column if not exists chg_name_at         timestamptz;
-- 받는 분 이름도 같은 방식 (2026-11-09 더함) — 담당자 화면에서만 고칠 수 있다
alter table public.kimjang_orders add column if not exists orig_recipient_name text;
alter table public.kimjang_orders add column if not exists chg_rname_at        timestamptz;


-- ── 주문 목록 (처음 적은 이름도 함께 내보내도록 다시 만듦) ────
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
             total_amount, memo, paid, paid_date, payer_name, canceled
      from public.kimjang_orders) o), '[]'::json));
end
$$;
revoke all on function public.kimjang_desk_list(text) from public;
grant execute on function public.kimjang_desk_list(text) to anon;


-- ── 주문자 이름 고치기 ────────────────────────────────────────
create or replace function public.kimjang_desk_set_name(p_pass text, p_id bigint, p_name text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  err text;
  nm text := btrim(coalesce(p_name, ''));
  o public.kimjang_orders%rowtype;
begin
  err := public.kimjang_desk_check(p_pass);
  if err is not null then return json_build_object('error', err); end if;

  if char_length(nm) not between 1 and 20 then
    return json_build_object('error', '주문자 이름은 1~20자로 적어 주세요.');
  end if;

  select * into o from public.kimjang_orders where id = p_id;
  if not found then return json_build_object('error', '그 주문을 찾지 못했습니다.'); end if;

  if nm = o.orderer_name then
    return json_build_object('ok', true, 'orig', o.orig_orderer_name);   -- 바뀐 것 없음
  end if;

  if nm = o.orig_orderer_name then
    -- 처음 적은 이름으로 되돌리기
    update public.kimjang_orders
       set orderer_name = nm, orig_orderer_name = null, chg_name_at = now()
     where id = p_id;
    return json_build_object('ok', true, 'orig', null);
  end if;

  update public.kimjang_orders
     set orig_orderer_name = coalesce(o.orig_orderer_name, o.orderer_name),
         orderer_name = nm, chg_name_at = now()
   where id = p_id;
  return json_build_object('ok', true, 'orig', coalesce(o.orig_orderer_name, o.orderer_name));
end
$$;
revoke all on function public.kimjang_desk_set_name(text,bigint,text) from public;
grant execute on function public.kimjang_desk_set_name(text,bigint,text) to anon;


-- ── 받는 분 이름 고치기 (담당자 화면에서만) ──────────────────
--  처음 적은 이름은 orig_recipient_name 에 한 번만 남긴다. 처음 이름으로 고치면 되돌리기.
--  「내 주문 확인」은 받는 분 이름으로 찾지 않으므로 그쪽은 손대지 않는다 (고친 이름이 가려져서 보인다).
create or replace function public.kimjang_desk_set_rname(p_pass text, p_id bigint, p_name text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  err text;
  nm text := btrim(coalesce(p_name, ''));
  o public.kimjang_orders%rowtype;
begin
  err := public.kimjang_desk_check(p_pass);
  if err is not null then return json_build_object('error', err); end if;

  if char_length(nm) not between 1 and 20 then
    return json_build_object('error', '받는 분 이름은 1~20자로 적어 주세요.');
  end if;

  select * into o from public.kimjang_orders where id = p_id;
  if not found then return json_build_object('error', '그 주문을 찾지 못했습니다.'); end if;

  if nm = o.recipient_name then
    return json_build_object('ok', true, 'orig', o.orig_recipient_name);
  end if;

  if nm = o.orig_recipient_name then
    update public.kimjang_orders
       set recipient_name = nm, orig_recipient_name = null, chg_rname_at = now()
     where id = p_id;
    return json_build_object('ok', true, 'orig', null);
  end if;

  update public.kimjang_orders
     set orig_recipient_name = coalesce(o.orig_recipient_name, o.recipient_name),
         recipient_name = nm, chg_rname_at = now()
   where id = p_id;
  return json_build_object('ok', true, 'orig', coalesce(o.orig_recipient_name, o.recipient_name));
end
$$;
revoke all on function public.kimjang_desk_set_rname(text,bigint,text) from public;
grant execute on function public.kimjang_desk_set_rname(text,bigint,text) to anon;


-- ── 내 주문 확인 (주문하신 분 화면) — 처음 적은 이름으로도 찾아지게 ──
--  「절임배추주문_수량변경.sql」의 함수와 같고, 맨 아래 이름 조건만 넓혔다.
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
