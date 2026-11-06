-- ══════════════════════════════════════════════════════════════
--  2026 절임배추 특별 주문 — 입금 확인할 때 입금일 적기  (2026-11-06 더함)
--  화면: jjcoop.co.kr/2026절임배추주문/desk.html
--
--  회계팀이 나중에 통장과 맞춰 볼 수 있게, 입금 확인과 함께 입금일을 적는다.
--  입금 확인을 풀면 입금일도 지운다.
--
--  ※ 「절임배추주문_수령일변경.sql」을 먼저 실행한 뒤에 실행한다.
--  ※ 두 번 실행해도 안전합니다.
-- ══════════════════════════════════════════════════════════════

alter table public.kimjang_orders add column if not exists paid_date date;


-- ── 주문 목록 (입금일도 함께 내보내도록 다시 만듦) ────────────
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
             total_amount, memo, paid, paid_date, canceled
      from public.kimjang_orders) o), '[]'::json));
end
$$;
revoke all on function public.kimjang_desk_list(text) from public;
grant execute on function public.kimjang_desk_list(text) to anon;


-- ── 입금 확인 + 입금일 ────────────────────────────────────────
--  p_paid = true  → 입금 확인, 입금일 = p_date (꼭 있어야 함)
--  p_paid = false → 입금 확인 풀기, 입금일 지움
create or replace function public.kimjang_desk_pay(p_pass text, p_id bigint, p_paid boolean, p_date date)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare err text;
begin
  err := public.kimjang_desk_check(p_pass);
  if err is not null then return json_build_object('error', err); end if;

  if coalesce(p_paid, false) then
    if p_date is null then
      return json_build_object('error', '입금일을 골라 주세요.');
    end if;
    if p_date < date '2026-11-01' or p_date > (now() at time zone 'Asia/Seoul')::date then
      return json_build_object('error', '입금일을 확인해 주세요. (11월 1일부터 오늘까지)');
    end if;
    update public.kimjang_orders set paid = true, paid_date = p_date where id = p_id;
  else
    update public.kimjang_orders set paid = false, paid_date = null where id = p_id;
  end if;
  if not found then return json_build_object('error', '그 주문을 찾지 못했습니다.'); end if;
  return json_build_object('ok', true);
end
$$;
revoke all on function public.kimjang_desk_pay(text,bigint,boolean,date) from public;
grant execute on function public.kimjang_desk_pay(text,bigint,boolean,date) to anon;

notify pgrst, 'reload schema';
