-- ══════════════════════════════════════════════════════════════
--  2026 절임배추 특별 주문 — 입금 확인할 때 입금자명 적기  (2026-11-06 더함)
--  화면: jjcoop.co.kr/2026절임배추주문/desk.html
--
--  통장에 찍힌 입금자 이름이 주문자 이름과 다를 때(가족 이름, 회사 이름 등)
--  담당자가 입금자명을 적어 둔다. 같으면 비워 둔다.
--  입금 확인을 풀면 입금일과 함께 입금자명도 지운다.
--
--  ※ 「절임배추주문_입금일.sql」을 먼저 실행한 뒤에 실행한다.
--  ※ 두 번 실행해도 안전합니다.
--  ※ 이 SQL을 먼저 실행하고 나서 desk.html을 올린다. (옛 화면도 그대로 돌아간다)
-- ══════════════════════════════════════════════════════════════

alter table public.kimjang_orders add column if not exists payer_name text;


-- ── 주문 목록 (입금자명도 함께 내보내도록 다시 만듦) ──────────
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
             total_amount, memo, paid, paid_date, payer_name, canceled
      from public.kimjang_orders) o), '[]'::json));
end
$$;
revoke all on function public.kimjang_desk_list(text) from public;
grant execute on function public.kimjang_desk_list(text) to anon;


-- ── 입금 확인 + 입금일 + 입금자명 ─────────────────────────────
--  옛 함수(입금자명 없는 것)를 지우고, 입금자명을 더한 함수로 바꾼다.
--  p_payer 는 비워도 된다 → 옛 화면(입금자명 칸 없는 것)도 그대로 돌아간다.
drop function if exists public.kimjang_desk_pay(text,bigint,boolean,date);

create or replace function public.kimjang_desk_pay(p_pass text, p_id bigint, p_paid boolean, p_date date, p_payer text default null)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare err text; v_payer text;
begin
  err := public.kimjang_desk_check(p_pass);
  if err is not null then return json_build_object('error', err); end if;

  v_payer := nullif(btrim(coalesce(p_payer, '')), '');
  if v_payer is not null and char_length(v_payer) > 30 then
    return json_build_object('error', '입금자명은 30자까지 적을 수 있습니다.');
  end if;

  if coalesce(p_paid, false) then
    if p_date is null then
      return json_build_object('error', '입금일을 골라 주세요.');
    end if;
    if p_date < date '2026-11-01' or p_date > (now() at time zone 'Asia/Seoul')::date then
      return json_build_object('error', '입금일을 확인해 주세요. (11월 1일부터 오늘까지)');
    end if;
    update public.kimjang_orders set paid = true, paid_date = p_date, payer_name = v_payer where id = p_id;
  else
    update public.kimjang_orders set paid = false, paid_date = null, payer_name = null where id = p_id;
  end if;
  if not found then return json_build_object('error', '그 주문을 찾지 못했습니다.'); end if;
  return json_build_object('ok', true);
end
$$;
revoke all on function public.kimjang_desk_pay(text,bigint,boolean,date,text) from public;
grant execute on function public.kimjang_desk_pay(text,bigint,boolean,date,text) to anon;

notify pgrst, 'reload schema';
