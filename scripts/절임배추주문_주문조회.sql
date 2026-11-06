-- ══════════════════════════════════════════════════════════════
--  2026 절임배추 특별 주문 — 주문하신 분이 직접 「내 주문 확인」  (2026-11-06 더함)
--  화면: jjcoop.co.kr/2026절임배추주문/check.html
--
--  주문자 이름 + 주문자 연락처가 둘 다 맞아야 그 주문만 보여 준다.
--  보여 주는 것: 주문번호 · 주문일 · 상품·수량 · 발송일(바꾼 날짜 반영) · 배송지 전체 주소(바꾼 주소 반영)
--               · 입금 상태·입금일 · 금액   (전체 주소는 2026-11-06 은미님 요청)
--  가리는 것: 받는 분 이름은 가운데를 * 로.
--  같은 곳(IP)에서 10분에 10번 못 찾으면 잠깐 막는다 (남의 번호를 넣어 보는 것 막기).
--
--  ※ 「절임배추주문_입금일.sql」을 먼저 실행한 뒤에 실행한다.
--  ※ 두 번 실행해도 안전합니다.
-- ══════════════════════════════════════════════════════════════

-- 못 찾은 기록 (막기용, 하루 지나면 지움)
create table if not exists public.kimjang_lookup_fail (
  at timestamptz not null default now(),
  ip text
);
alter table public.kimjang_lookup_fail enable row level security;
revoke all on public.kimjang_lookup_fail from anon, authenticated;


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
  -- 요청한 곳 (홈페이지 → Supabase 가 붙여 주는 머리글)
  begin
    v_ip := split_part(coalesce(current_setting('request.headers', true)::json ->> 'x-forwarded-for', ''), ',', 1);
  exception when others then v_ip := '';
  end;

  -- 요청한 곳을 모르면(빈칸) 모두가 한 묶음이 되어 같이 막히므로, 그때는 이 검사를 건너뛴다
  if coalesce(v_ip,'') <> '' and (select count(*) from public.kimjang_lookup_fail
      where at > now() - interval '10 minutes' and ip = v_ip) >= 10 then
    return json_build_object('error', '여러 번 찾지 못해 잠시 막혔습니다. 10분 뒤에 다시 해 주세요.');
  end if;
  -- 전체적으로 쏟아붓는 것도 막기 (1분에 120번 못 찾으면)
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
      o.qty_baechu, coalesce(o.chg_date_baechu, o.date_baechu) as date_baechu,
      o.qty_sok,    coalesce(o.chg_date_sok,    o.date_sok)    as date_sok,
      o.qty_kit,    coalesce(o.chg_date_kit,    o.date_kit)    as date_kit,
      o.total_amount,
      o.paid, o.paid_date, o.canceled,
      -- 받는 곳: 매장이면 「매장수령 · ○○점」, 택배면 「택배 · (우편번호) 주소 상세주소」 — 바꾼 주소가 있으면 그것
      case when ad.a like '매장수령%'
           then ad.a
           else '택배 · ' || coalesce('(' || ad.z || ') ', '') || ad.a || coalesce(' ' || ad.d, '')
      end as place,
      -- 받는 분: 가운데를 * 로 (홍길동 → 홍*동, 김철 → 김*)
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
