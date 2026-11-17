-- ══════════════════════════════════════════════════════════════
--  2026 진주엔 이벤트 — 김장밀키트 당첨자 배송지 받기
--  당첨자 페이지: jjcoop.co.kr/2026이벤트/   (짧은 주소 jjcoop.co.kr/event)
--  담당자 화면 : jjcoop.co.kr/2026이벤트/desk.html
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
--   - 홈페이지에서는 「적어 보내기」만 됩니다. 남이 적은 이름·전화·주소는 아무도 못 봅니다.
--   - 진주시 주소만 받습니다. 같은 전화번호는 한 번만 받습니다.
--   - 당첨자는 50가구이므로, 혹시 링크가 퍼져도 70건이 차면 더 받지 않습니다.
--   - 담당자 화면 비밀번호는 절임배추 담당자 화면과 같은 것을 씁니다 (kimjang_desk_check).
-- ══════════════════════════════════════════════════════════════


-- ── 1. 당첨자 표 ──────────────────────────────────────────────
create table if not exists public.event2026_winners (
  id             bigint      generated always as identity primary key,
  created_at     timestamptz not null default now(),
  name           text        not null,
  phone          text        not null,
  phone_digits   text        not null,   -- 같은 번호 두 번 막기용 (숫자만)
  sns_id         text        not null,   -- 이벤트에 참여한 인스타·페이스북·카페 아이디 (당첨자 맞는지 확인용)
  zipcode        text,
  address        text        not null,
  address_detail text,
  memo           text,                   -- 배송 요청사항
  shipped        boolean     not null default false,
  canceled       boolean     not null default false,
  staff_note     text
);
create unique index if not exists event2026_winners_phone_uq on public.event2026_winners (phone_digits);
create index if not exists event2026_winners_created_idx on public.event2026_winners (created_at desc);

alter table public.event2026_winners enable row level security;
revoke all on public.event2026_winners from anon, authenticated;


-- ── 2. 받기 열림/닫힘 ─────────────────────────────────────────
create table if not exists public.event2026_setting (
  id   int     primary key default 1 check (id = 1),
  open boolean not null default true
);
insert into public.event2026_setting (id, open) values (1, true) on conflict (id) do nothing;
alter table public.event2026_setting enable row level security;
revoke all on public.event2026_setting from anon, authenticated;

create or replace function public.event2026_status()
returns json
language sql
security definer
set search_path = public
as $$
  select json_build_object('open', coalesce((select open from public.event2026_setting where id = 1), true));
$$;
revoke all on function public.event2026_status() from public;
grant execute on function public.event2026_status() to anon;


-- ── 3. 배송지 적어 보내기 (홈페이지는 이것만 부를 수 있다) ────
create or replace function public.place_event2026(
  p_name           text,
  p_phone          text,
  p_sns_id         text,
  p_zipcode        text,
  p_address        text,
  p_address_detail text,
  p_memo           text
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  digits text := regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g');
  new_id bigint;
begin
  if not coalesce((select open from public.event2026_setting where id = 1), true) then
    raise exception '배송지 받기를 마감했습니다. 문의는 사무국(055-763-1243)으로 주세요.' using errcode = '23514';
  end if;

  if char_length(btrim(coalesce(p_name,''))) not between 1 and 20 then
    raise exception '이름을 확인해 주세요.' using errcode = '23514';
  end if;
  if digits !~ '^0[0-9]{8,10}$' then
    raise exception '휴대폰 번호를 확인해 주세요.' using errcode = '23514';
  end if;
  if char_length(btrim(coalesce(p_sns_id,''))) not between 1 and 50 then
    raise exception '이벤트에 참여하신 아이디를 적어 주세요.' using errcode = '23514';
  end if;
  if char_length(btrim(coalesce(p_address,''))) not between 5 and 200
     or char_length(coalesce(p_address_detail,'')) > 100
     or char_length(coalesce(p_zipcode,'')) > 10
     or char_length(coalesce(p_memo,'')) > 300 then
    raise exception '주소나 요청사항을 확인해 주세요.' using errcode = '23514';
  end if;
  if position('진주' in p_address) = 0 then
    raise exception '이번 이벤트는 진주시 주소로만 보내드립니다. 주소를 확인해 주세요.' using errcode = '23514';
  end if;

  if exists (select 1 from public.event2026_winners where phone_digits = digits) then
    raise exception '이 번호로 이미 접수되었습니다. 바꾸실 내용은 사무국(055-763-1243)으로 알려 주세요.' using errcode = '23514';
  end if;
  if (select count(*) from public.event2026_winners) >= 70 then
    raise exception '접수가 모두 찼습니다. 문의는 사무국(055-763-1243)으로 주세요.' using errcode = '23514';
  end if;
  if (select count(*) from public.event2026_winners where created_at > now() - interval '1 minute') >= 20 then
    raise exception '잠시 뒤에 다시 눌러 주세요.' using errcode = '23514';
  end if;

  insert into public.event2026_winners (name, phone, phone_digits, sns_id, zipcode, address, address_detail, memo)
  values (btrim(p_name), btrim(p_phone), digits, btrim(p_sns_id),
          nullif(btrim(coalesce(p_zipcode,'')),''), btrim(p_address),
          nullif(btrim(coalesce(p_address_detail,'')),''), nullif(btrim(coalesce(p_memo,'')),''))
  returning id into new_id;

  return json_build_object('no', new_id);
end
$$;
revoke all on function public.place_event2026(text,text,text,text,text,text,text) from public;
grant execute on function public.place_event2026(text,text,text,text,text,text,text) to anon;


-- ── 4. 담당자: 목록 ───────────────────────────────────────────
create or replace function public.event2026_desk_list(p_pass text)
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
    'open', coalesce((select open from public.event2026_setting where id = 1), true),
    'rows', coalesce((
      select json_agg(w order by w.id desc) from (
        select id, created_at, name, phone, sns_id, zipcode, address, address_detail,
               memo, shipped, canceled, staff_note
        from public.event2026_winners) w), '[]'::json));
end
$$;
revoke all on function public.event2026_desk_list(text) from public;
grant execute on function public.event2026_desk_list(text) to anon;


-- ── 5. 담당자: 발송 · 취소 · 메모 ─────────────────────────────
create or replace function public.event2026_desk_mark(
  p_pass text, p_id bigint, p_field text, p_value boolean, p_text text default null)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare err text;
begin
  err := public.kimjang_desk_check(p_pass);
  if err is not null then return json_build_object('error', err); end if;
  if p_field = 'shipped' then
    update public.event2026_winners set shipped = coalesce(p_value,false) where id = p_id;
  elsif p_field = 'canceled' then
    update public.event2026_winners set canceled = coalesce(p_value,false) where id = p_id;
  elsif p_field = 'note' then
    update public.event2026_winners set staff_note = nullif(left(btrim(coalesce(p_text,'')),300),'') where id = p_id;
  else
    return json_build_object('error', '바꿀 수 없는 칸입니다.');
  end if;
  if not found then return json_build_object('error', '그 줄을 찾지 못했습니다.'); end if;
  return json_build_object('ok', true);
end
$$;
revoke all on function public.event2026_desk_mark(text,bigint,text,boolean,text) from public;
grant execute on function public.event2026_desk_mark(text,bigint,text,boolean,text) to anon;


-- ── 6. 담당자: 받기 멈추기 / 다시 열기 ────────────────────────
create or replace function public.event2026_desk_set_open(p_pass text, p_open boolean)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare err text;
begin
  err := public.kimjang_desk_check(p_pass);
  if err is not null then return json_build_object('error', err); end if;
  update public.event2026_setting set open = coalesce(p_open, true) where id = 1;
  return json_build_object('ok', true, 'open', coalesce(p_open, true));
end
$$;
revoke all on function public.event2026_desk_set_open(text,boolean) from public;
grant execute on function public.event2026_desk_set_open(text,boolean) to anon;


-- ── 7. 홈페이지가 바로 알아보게 ───────────────────────────────
notify pgrst, 'reload schema';

-- 확인: 아래 한 줄을 실행해 {"open" : true} 가 나오면 정상입니다.
--   select public.event2026_status();
