-- Execute uma vez no Supabase existente antes de publicar a nova versão do Pauta.
-- Inclui o cadastro de apartamentos pelos próprios moradores no primeiro acesso.
create or replace function public.register_apartment(p_vote_code text,p_apartment_number text,p_block text,p_pin text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_session public.votes_sessions%rowtype; v_pattern text;
begin
  select * into v_session from public.votes_sessions where code=upper(trim(coalesce(p_vote_code,'')));
  if not found then raise exception 'vote_not_found'; end if;
  select identity_pattern into v_pattern from public.condos where id=v_session.condo_id;
  if length(trim(coalesce(p_apartment_number,''))) not between 1 and 20
    or (v_pattern='number_block' and length(trim(coalesce(p_block,''))) not between 1 and 20)
    or length(coalesce(p_pin,'')) not between 4 and 100 then
    raise exception 'invalid_apartment_fields';
  end if;
  perform pg_advisory_xact_lock(hashtext(v_session.condo_id::text));
  if exists(
    select 1 from public.apartments a
    where a.condo_id=v_session.condo_id
      and lower(trim(a.apartment_number))=lower(trim(p_apartment_number))
      and (v_pattern='number' or lower(trim(a.block))=lower(trim(coalesce(p_block,''))))
  ) then raise exception 'identity_already_exists'; end if;
  insert into public.apartments(condo_id,apartment_number,block,pin_hash)
  values(v_session.condo_id,trim(p_apartment_number),trim(coalesce(p_block,'')),extensions.crypt(p_pin,extensions.gen_salt('bf')));
end $$;
revoke all on function public.register_apartment(text,text,text,text) from public;
grant execute on function public.register_apartment(text,text,text,text) to anon,authenticated;

-- Novas pautas são bloqueadas no banco após o encerramento da votação.
create or replace function public.require_open_vote_for_new_topic() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (
    select 1 from public.votes_sessions s
    where s.id=new.session_id and s.status='open'
  ) then
    raise exception 'voting_closed';
  end if;
  return new;
end $$;

drop trigger if exists topics_require_open_vote on public.topics;
create trigger topics_require_open_vote before insert on public.topics
for each row execute function public.require_open_vote_for_new_topic();

create or replace function public.get_vote_tally(p_vote_code text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'title',s.title,
    'status',s.status,
    'vote_limit',s.vote_limit,
    'condo_name',c.name,
    'total_votes',(select count(*) from public.votes v where v.session_id=s.id),
    'apartments_voted',(select count(distinct v.apartment_id) from public.votes v where v.session_id=s.id),
    'topics',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',t.id,
        'title',t.title,
        'description',t.description,
        'votes',(select count(*) from public.votes v where v.session_id=s.id and v.topic_id=t.id)
      ) order by t.created_at,t.id)
      from public.topics t where t.session_id=s.id
    ),'[]'::jsonb)
  )
  from public.votes_sessions s
  join public.condos c on c.id=s.condo_id
  where s.code=upper(trim(coalesce(p_vote_code,'')));
$$;

revoke all on function public.get_vote_tally(text) from public;
revoke all on function public.require_open_vote_for_new_topic() from public;
grant execute on function public.get_vote_tally(text) to anon,authenticated;
