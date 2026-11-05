-- ══════════════════════════════════════════════════════════════
--  2026 절임배추 특별 주문 — 담당자 취합 화면용
--  화면: jjcoop.co.kr/2026절임배추주문/desk.html
--
--  비밀번호를 아는 사람만 주문 목록을 보고, 입금확인·취소를 체크할 수 있다.
--  비밀번호는 암호화(해시)해서 저장한다. 표에도, 홈페이지에도 원래 글자는 남지 않는다.
--  10분 동안 10번 틀리면 잠깐 막힌다.
--
--  【비밀번호 정하기 · 바꾸기】 SQL Editor에서 아래 한 줄의 ' ' 안만 바꿔서 실행
--     select public.kimjang_desk_set_password('여기에 비밀번호');
--  ※ 두 번 실행해도 안전합니다.
-- ══════════════════════════════════════════════════════════════

create extension if not exists pgcrypto with schema extensions;

-- 취소 표시 칸 더하기
alter table public.kimjang_orders add column if not exists canceled boolean not null default false;

-- 비밀번호(해시) 보관 · 틀린 기록
create table if not exists public.kimjang_desk_secret (
  id int primary key default 1 check (id = 1),
  pass_hash text not null
);
create table if not exists public.kimjang_desk_fail (
  at timestamptz not null default now()
);
alter table public.kimjang_desk_secret enable row level security;
alter table public.kimjang_desk_fail   enable row level security;
revoke all on public.kimjang_desk_secret, public.kimjang_desk_fail from anon, authenticated;


-- ── 비밀번호 정하기 (SQL Editor에서만 됨) ─────────────────────
create or replace function public.kimjang_desk_set_password(p_pass text)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if char_length(coalesce(p_pass,'')) < 6 then
    raise exception '비밀번호는 6자 이상으로 해 주세요.';
  end if;
  insert into public.kimjang_desk_secret (id, pass_hash)
  values (1, extensions.crypt(p_pass, extensions.gen_salt('bf')))
  on conflict (id) do update set pass_hash = excluded.pass_hash;
  return '비밀번호를 정했습니다.';
end
$$;
revoke all on function public.kimjang_desk_set_password(text) from public, anon, authenticated;


-- ── 비밀번호 확인 (안에서만 씀) ───────────────────────────────
create or replace function public.kimjang_desk_check(p_pass text)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare h text;
begin
  if (select count(*) from public.kimjang_desk_fail where at > now() - interval '10 minutes') >= 10 then
    return '여러 번 틀려서 잠시 막혔습니다. 10분 뒤에 다시 해 주세요.';
  end if;
  select pass_hash into h from public.kimjang_desk_secret where id = 1;
  if h is null then
    return '아직 비밀번호가 정해지지 않았습니다.';
  end if;
  if extensions.crypt(coalesce(p_pass,''), h) <> h then
    insert into public.kimjang_desk_fail default values;
    delete from public.kimjang_desk_fail where at < now() - interval '1 day';
    return '비밀번호가 틀렸습니다.';
  end if;
  return null;  -- 맞음
end
$$;
revoke all on function public.kimjang_desk_check(text) from public, anon, authenticated;


-- ── 주문 목록 ─────────────────────────────────────────────────
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
             total_amount, memo, paid, canceled
      from public.kimjang_orders) o), '[]'::json));
end
$$;
revoke all on function public.kimjang_desk_list(text) from public;
grant execute on function public.kimjang_desk_list(text) to anon;


-- ── 입금확인 · 취소 체크 ──────────────────────────────────────
create or replace function public.kimjang_desk_mark(p_pass text, p_id bigint, p_field text, p_value boolean)
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
    update public.kimjang_orders set paid = coalesce(p_value,false) where id = p_id;
  elsif p_field = 'canceled' then
    update public.kimjang_orders set canceled = coalesce(p_value,false) where id = p_id;
  else
    return json_build_object('error', '바꿀 수 없는 칸입니다.');
  end if;
  if not found then return json_build_object('error', '그 주문을 찾지 못했습니다.'); end if;
  return json_build_object('ok', true);
end
$$;
revoke all on function public.kimjang_desk_mark(text,bigint,text,boolean) from public;
grant execute on function public.kimjang_desk_mark(text,bigint,text,boolean) to anon;

notify pgrst, 'reload schema';
