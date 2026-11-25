-- ══════════════════════════════════════════════════════════════
--  2026 소비자의날(12/3) 가치소비 응원판
--  참여·응원판 : jjcoop.co.kr/2026소비자의날/   (짧은 주소 jjcoop.co.kr/cheer)
--  담당자 화면 : jjcoop.co.kr/2026소비자의날/desk.html
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
--   - 응원판에는 「응원 글 · 이용 매장 · 가운데를 가린 이름(전*미)」만 나갑니다.
--     전화번호와 이름 전체는 홈페이지에서 아무도 못 봅니다 (담당자 화면만).
--   - 링크(http, www, .com 등)가 든 글은 받지 않습니다 (광고 막기).
--   - 같은 전화번호로는 3번까지만 남길 수 있습니다.
--   - 담당자가 「숨기기」 한 글은 응원판에서 빠집니다.
--   - 좋아요는 한 글에 한 번, 다른 글에는 각각 한 번씩 누를 수 있습니다 (서버가 지킴).
--     로그인 없이 누르므로 「기기(휴대폰·브라우저)마다 한 번」입니다.
--     같은 휴대폰이라도 다른 브라우저로 열거나 방문 기록을 지우면 또 누를 수 있습니다.
--   - 담당자 화면 비밀번호는 절임배추 담당자 화면과 같은 것을 씁니다 (kimjang_desk_check).
-- ══════════════════════════════════════════════════════════════


-- ── 1. 응원 글 표 ─────────────────────────────────────────────
create table if not exists public.cday2026_cheers (
  id           bigint      generated always as identity primary key,
  created_at   timestamptz not null default now(),
  name         text        not null,
  phone        text        not null,
  phone_digits text        not null,
  stores       text[]      not null,     -- 금산점 / 초전점 / 진양호점 (여럿 고를 수 있음)
  topic        text        not null,     -- 어떤 이야기인지 (아래 3가지 중 하나)
  message      text        not null,
  likes        int         not null default 0,
  hidden       boolean     not null default false,
  staff_note   text
);
create index if not exists cday2026_cheers_phone_idx   on public.cday2026_cheers (phone_digits);
create index if not exists cday2026_cheers_created_idx on public.cday2026_cheers (created_at desc);

alter table public.cday2026_cheers enable row level security;
revoke all on public.cday2026_cheers from anon, authenticated;

-- 좋아요 누른 기록 — 「한 기기는 한 글에 한 번」을 서버가 지킨다
--   device = 응원판을 연 휴대폰·브라우저마다 저절로 만들어지는 무작위 번호 (개인정보 아님)
create table if not exists public.cday2026_likes (
  id        bigint      generated always as identity primary key,
  cheer_id  bigint      not null references public.cday2026_cheers(id) on delete cascade,
  device    text        not null,
  liked_at  timestamptz not null default now(),
  unique (cheer_id, device)
);
create index if not exists cday2026_likes_time_idx   on public.cday2026_likes (liked_at desc);
create index if not exists cday2026_likes_device_idx on public.cday2026_likes (device);
alter table public.cday2026_likes enable row level security;
revoke all on public.cday2026_likes from anon, authenticated;


-- ── 2. 받기 열림/닫힘 ─────────────────────────────────────────
create table if not exists public.cday2026_setting (
  id   int     primary key default 1 check (id = 1),
  open boolean not null default true
);
insert into public.cday2026_setting (id, open) values (1, true) on conflict (id) do nothing;
alter table public.cday2026_setting enable row level security;
revoke all on public.cday2026_setting from anon, authenticated;


-- ── 3. 이름 가운데 가리기: 전은미 → 전*미, 김철 → 김*, 남궁민수 → 남**수 ──
create or replace function public.cday2026_mask(p text)
returns text
language sql
immutable
as $$
  select case
    when char_length(p) <= 1 then p
    when char_length(p) = 2 then left(p,1) || '*'
    else left(p,1) || repeat('*', char_length(p) - 2) || right(p,1)
  end;
$$;


-- ── 4. 응원판 보기 (누구나) — 이름은 가려서, 전화번호는 빼고 ──
--   p_device 를 주면 그 기기가 좋아요 누른 글 번호(mine)도 돌려준다
create or replace function public.cday2026_board(p_device text default null)
returns json
language sql
security definer
set search_path = public
as $$
  select json_build_object(
    'open',  coalesce((select open from public.cday2026_setting where id = 1), true),
    'count', (select count(*) from public.cday2026_cheers where not hidden),
    'mine',  coalesce((select json_agg(cheer_id) from public.cday2026_likes where device = p_device), '[]'::json),
    'rows',  coalesce((
      select json_agg(c order by c.id desc) from (
        select id, created_at, public.cday2026_mask(name) as name, stores, topic, message, likes
        from public.cday2026_cheers where not hidden) c), '[]'::json));
$$;
revoke all on function public.cday2026_board(text) from public;
grant execute on function public.cday2026_board(text) to anon;


-- ── 5. 응원 남기기 (홈페이지는 이것만 부를 수 있다) ───────────
create or replace function public.place_cday2026(
  p_name    text,
  p_phone   text,
  p_stores  text[],
  p_topic   text,
  p_message text
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  digits text := regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g');
  msg    text := btrim(coalesce(p_message,''));
  st     text[];
  new_id bigint;
begin
  if not coalesce((select open from public.cday2026_setting where id = 1), true) then
    raise exception '응원 남기기를 마감했습니다. 함께해 주셔서 고맙습니다.' using errcode = '23514';
  end if;

  if char_length(btrim(coalesce(p_name,''))) not between 1 and 20 then
    raise exception '이름을 확인해 주세요.' using errcode = '23514';
  end if;
  if digits !~ '^0[0-9]{8,10}$' then
    raise exception '연락처를 확인해 주세요.' using errcode = '23514';
  end if;

  select array_agg(distinct s order by s) into st
  from unnest(coalesce(p_stores, '{}'::text[])) s
  where s in ('금산점','초전점','진양호점');
  if st is null or cardinality(st) = 0 then
    raise exception '이용하시는 매장을 골라 주세요.' using errcode = '23514';
  end if;

  if coalesce(p_topic,'') not in ('가치소비를 느낀 순간','진주텃밭을 이용하는 이유','나의 가치소비 응원 한마디') then
    raise exception '어떤 이야기인지 골라 주세요.' using errcode = '23514';
  end if;

  if char_length(msg) not between 5 and 300 then
    raise exception '응원 글은 5자 이상 300자 이하로 적어 주세요.' using errcode = '23514';
  end if;
  if msg ~* '(https?://|www\.|\.com|\.kr|\.net|open\.kakao|bit\.ly)' then
    raise exception '응원 글에는 인터넷 주소를 넣을 수 없습니다.' using errcode = '23514';
  end if;

  if (select count(*) from public.cday2026_cheers where phone_digits = digits) >= 3 then
    raise exception '한 분이 3번까지 남기실 수 있습니다. 고맙습니다!' using errcode = '23514';
  end if;
  if (select count(*) from public.cday2026_cheers where created_at > now() - interval '1 minute') >= 20 then
    raise exception '잠시 뒤에 다시 눌러 주세요.' using errcode = '23514';
  end if;

  insert into public.cday2026_cheers (name, phone, phone_digits, stores, topic, message)
  values (btrim(p_name), btrim(p_phone), digits, st, p_topic, msg)
  returning id into new_id;

  return json_build_object('no', new_id);
end
$$;
revoke all on function public.place_cday2026(text,text,text[],text,text) from public;
grant execute on function public.place_cday2026(text,text,text[],text,text) to anon;


-- ── 6. 좋아요 누르기 / 취소하기 (누구나) ──────────────────────
--   한 기기는 한 글에 좋아요 한 번. 다른 글에는 각각 한 번씩 누를 수 있다.
--   잘못 눌렀으면 다시 눌러 취소할 수 있다.
create or replace function public.cday2026_like(p_id bigint, p_device text, p_on boolean default true)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  n   int;
  dev text := btrim(coalesce(p_device,''));
  cnt int;
begin
  if dev !~ '^[A-Za-z0-9-]{16,64}$' then
    raise exception '좋아요를 보내지 못했습니다. 새로고침한 뒤 다시 눌러 주세요.' using errcode = '23514';
  end if;
  if not exists (select 1 from public.cday2026_cheers where id = p_id and not hidden) then
    raise exception '그 글을 찾지 못했습니다.' using errcode = '23514';
  end if;
  if (select count(*) from public.cday2026_likes where liked_at > now() - interval '1 minute') >= 300
     or (select count(*) from public.cday2026_likes where device = dev and liked_at > now() - interval '1 minute') >= 30 then
    raise exception '잠시 뒤에 다시 눌러 주세요.' using errcode = '23514';
  end if;

  if coalesce(p_on, true) then
    insert into public.cday2026_likes (cheer_id, device) values (p_id, dev)
    on conflict (cheer_id, device) do nothing;
    get diagnostics cnt = row_count;
    if cnt = 0 then
      raise exception '이 응원에는 이미 좋아요를 누르셨어요.' using errcode = '23514';
    end if;
    update public.cday2026_cheers set likes = likes + 1 where id = p_id returning likes into n;
  else
    delete from public.cday2026_likes where cheer_id = p_id and device = dev;
    get diagnostics cnt = row_count;
    if cnt = 0 then
      select likes into n from public.cday2026_cheers where id = p_id;   -- 누른 적이 없으면 그대로
    else
      update public.cday2026_cheers set likes = greatest(likes - 1, 0) where id = p_id returning likes into n;
    end if;
  end if;

  return json_build_object('likes', n, 'on', coalesce(p_on, true));
end
$$;
revoke all on function public.cday2026_like(bigint,text,boolean) from public;
grant execute on function public.cday2026_like(bigint,text,boolean) to anon;


-- ── 7. 담당자: 목록 (이름·전화 다 보임) ───────────────────────
create or replace function public.cday2026_desk_list(p_pass text)
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
    'open', coalesce((select open from public.cday2026_setting where id = 1), true),
    'rows', coalesce((
      select json_agg(c order by c.id desc) from (
        select id, created_at, name, phone, stores, topic, message, likes, hidden, staff_note
        from public.cday2026_cheers) c), '[]'::json));
end
$$;
revoke all on function public.cday2026_desk_list(text) from public;
grant execute on function public.cday2026_desk_list(text) to anon;


-- ── 8. 담당자: 숨기기 · 메모 ──────────────────────────────────
create or replace function public.cday2026_desk_mark(
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
  if p_field = 'hidden' then
    update public.cday2026_cheers set hidden = coalesce(p_value,false) where id = p_id;
  elsif p_field = 'note' then
    update public.cday2026_cheers set staff_note = nullif(left(btrim(coalesce(p_text,'')),300),'') where id = p_id;
  else
    return json_build_object('error', '바꿀 수 없는 칸입니다.');
  end if;
  if not found then return json_build_object('error', '그 줄을 찾지 못했습니다.'); end if;
  return json_build_object('ok', true);
end
$$;
revoke all on function public.cday2026_desk_mark(text,bigint,text,boolean,text) from public;
grant execute on function public.cday2026_desk_mark(text,bigint,text,boolean,text) to anon;


-- ── 9. 담당자: 받기 멈추기 / 다시 열기 ────────────────────────
create or replace function public.cday2026_desk_set_open(p_pass text, p_open boolean)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare err text;
begin
  err := public.kimjang_desk_check(p_pass);
  if err is not null then return json_build_object('error', err); end if;
  update public.cday2026_setting set open = coalesce(p_open, true) where id = 1;
  return json_build_object('ok', true, 'open', coalesce(p_open, true));
end
$$;
revoke all on function public.cday2026_desk_set_open(text,boolean) from public;
grant execute on function public.cday2026_desk_set_open(text,boolean) to anon;


-- ── 10. 홈페이지가 바로 알아보게 ──────────────────────────────
notify pgrst, 'reload schema';

-- 확인: 아래 한 줄을 실행해 {"open" : true, "count" : 0, "mine" : [], "rows" : []} 가 나오면 정상입니다.
--   select public.cday2026_board();
