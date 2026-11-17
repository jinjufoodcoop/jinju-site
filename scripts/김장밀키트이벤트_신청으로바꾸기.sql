-- ══════════════════════════════════════════════════════════════
--  2026 진주엔 이벤트 — 「당첨자 배송지」를 「이벤트 신청」으로 바꾸기
--  (김장밀키트이벤트_만들기.sql 을 먼저 실행한 뒤에 실행합니다. 두 번 실행해도 안전합니다.)
--
--  바뀌는 것
--   - 후기 약속(당첨되면 후기 + @jinju_coop 태그 + 제공받음 표기) 동의를 함께 받는다
--   - 신청 건수 70건 제한을 없앤다 (1분에 60건까지만)
--   - 담당자 화면에서 「당첨」 표시를 할 수 있다
-- ══════════════════════════════════════════════════════════════

alter table public.event2026_winners add column if not exists agree_review boolean not null default false;
alter table public.event2026_winners add column if not exists picked       boolean not null default false;

drop function if exists public.place_event2026(text,text,text,text,text,text,text);

create or replace function public.place_event2026(
  p_name           text,
  p_phone          text,
  p_sns_id         text,
  p_zipcode        text,
  p_address        text,
  p_address_detail text,
  p_memo           text,
  p_agree_review   boolean
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
    raise exception '이벤트 신청을 마감했습니다. 문의는 사무국(055-763-1243)으로 주세요.' using errcode = '23514';
  end if;
  if char_length(btrim(coalesce(p_name,''))) not between 1 and 20 then
    raise exception '이름을 확인해 주세요.' using errcode = '23514';
  end if;
  if digits !~ '^0[0-9]{8,10}$' then
    raise exception '휴대폰 번호를 확인해 주세요.' using errcode = '23514';
  end if;
  if char_length(btrim(coalesce(p_sns_id,''))) not between 1 and 50 then
    raise exception '인스타그램 아이디를 적어 주세요.' using errcode = '23514';
  end if;
  if char_length(btrim(coalesce(p_address,''))) not between 5 and 200
     or char_length(coalesce(p_address_detail,'')) > 100
     or char_length(coalesce(p_zipcode,'')) > 10
     or char_length(coalesce(p_memo,'')) > 300 then
    raise exception '주소나 요청사항을 확인해 주세요.' using errcode = '23514';
  end if;
  if position('진주' in p_address) = 0 then
    raise exception '이번 이벤트는 진주시에 사시는 분만 신청하실 수 있습니다. 주소를 확인해 주세요.' using errcode = '23514';
  end if;
  if not coalesce(p_agree_review, false) then
    raise exception '후기 약속에 체크해 주세요.' using errcode = '23514';
  end if;
  if exists (select 1 from public.event2026_winners where phone_digits = digits) then
    raise exception '이 번호로 이미 신청하셨습니다. 바꾸실 내용은 사무국(055-763-1243)으로 알려 주세요.' using errcode = '23514';
  end if;
  if (select count(*) from public.event2026_winners where created_at > now() - interval '1 minute') >= 60 then
    raise exception '신청이 몰리고 있습니다. 잠시 뒤에 다시 눌러 주세요.' using errcode = '23514';
  end if;

  insert into public.event2026_winners (name, phone, phone_digits, sns_id, zipcode, address, address_detail, memo, agree_review)
  values (btrim(p_name), btrim(p_phone), digits, btrim(p_sns_id),
          nullif(btrim(coalesce(p_zipcode,'')),''), btrim(p_address),
          nullif(btrim(coalesce(p_address_detail,'')),''), nullif(btrim(coalesce(p_memo,'')),''), true)
  returning id into new_id;

  return json_build_object('no', new_id);
end
$$;
revoke all on function public.place_event2026(text,text,text,text,text,text,text,boolean) from public;
grant execute on function public.place_event2026(text,text,text,text,text,text,text,boolean) to anon;


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
               memo, agree_review, picked, shipped, canceled, staff_note
        from public.event2026_winners) w), '[]'::json));
end
$$;


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
  if p_field = 'picked' then
    update public.event2026_winners set picked = coalesce(p_value,false) where id = p_id;
  elsif p_field = 'shipped' then
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

notify pgrst, 'reload schema';
