-- Pauta v2 — execute uma vez em um projeto Supabase novo no SQL Editor.
-- O admin inicial cria a conta em Authentication > Users e cria o condomínio pelo app.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.condos (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 140),
  identity_pattern text not null default 'number_block' check (identity_pattern in ('number_block','number')),
  created_at timestamptz not null default now()
);

create table if not exists public.root_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.admins (
  condo_id uuid not null references public.condos(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  admin_number text not null,
  admin_block text not null,
  phone text not null default '',
  created_at timestamptz not null default now(),
  primary key (condo_id,user_id)
);

create table if not exists public.apartments (
  id uuid primary key default gen_random_uuid(),
  condo_id uuid not null references public.condos(id) on delete cascade,
  apartment_number text not null check (length(trim(apartment_number)) between 1 and 20),
  block text not null check (length(trim(block)) between 1 and 20),
  phone text not null default '',
  pin_hash text not null,
  created_at timestamptz not null default now()
);
create unique index if not exists apartments_identity_unique on public.apartments(condo_id,lower(trim(apartment_number)),lower(trim(block)));

create table if not exists public.votes_sessions (
  id uuid primary key default gen_random_uuid(),
  condo_id uuid not null references public.condos(id) on delete cascade,
  title text not null check (length(trim(title)) between 1 and 140),
  code text not null unique check (code ~ '^[A-Z0-9]{8}$'),
  vote_limit integer not null check (vote_limit between 1 and 50),
  status text not null default 'open' check (status in ('open','closed')),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.topics (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.votes_sessions(id) on delete cascade,
  title text not null check (length(trim(title)) between 1 and 160),
  description text not null default '' check (length(description) <= 1000),
  votes integer not null default 0 check (votes >= 0),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

-- Uma votação encerrada não aceita novos itens, mesmo por chamadas diretas à API.
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

create table if not exists public.votes (
  apartment_id uuid not null references public.apartments(id) on delete cascade,
  session_id uuid not null references public.votes_sessions(id) on delete cascade,
  topic_id uuid not null references public.topics(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(apartment_id,topic_id)
);
create index if not exists votes_session_apartment on public.votes(session_id,apartment_id);

alter table public.condos enable row level security;
alter table public.root_admins enable row level security;
alter table public.admins enable row level security;
alter table public.apartments enable row level security;
alter table public.votes_sessions enable row level security;
alter table public.topics enable row level security;
alter table public.votes enable row level security;

create or replace function public.is_root_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.root_admins r where r.user_id=auth.uid());
$$;

create or replace function public.is_condo_admin(p_condo_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.admins a where a.condo_id=p_condo_id and a.user_id=auth.uid());
$$;

drop policy if exists "root admin sees own membership" on public.root_admins;
create policy "root admin sees own membership" on public.root_admins for select to authenticated using (user_id=auth.uid());
drop policy if exists "admin sees own memberships" on public.admins;
create policy "admin sees own memberships" on public.admins for select to authenticated using (user_id=auth.uid());
drop policy if exists "admin sees own condos" on public.condos;
create policy "admin sees own condos" on public.condos for select to authenticated using (public.is_condo_admin(id));
drop policy if exists "public reads condo identity settings" on public.condos;
create policy "public reads condo identity settings" on public.condos for select to anon,authenticated using (true);
drop policy if exists "public reads vote links" on public.votes_sessions;
create policy "public reads vote links" on public.votes_sessions for select to anon,authenticated using (true);
drop policy if exists "admin manages condo votings" on public.votes_sessions;
create policy "admin manages condo votings" on public.votes_sessions for all to authenticated
  using (public.is_condo_admin(condo_id)) with check (public.is_condo_admin(condo_id));
drop policy if exists "public reads topics" on public.topics;
create policy "public reads topics" on public.topics for select to anon,authenticated using (true);
drop policy if exists "admin manages topics" on public.topics;
create policy "admin manages topics" on public.topics for all to authenticated
  using (exists(select 1 from public.votes_sessions s where s.id=session_id and public.is_condo_admin(s.condo_id)))
  with check (exists(select 1 from public.votes_sessions s where s.id=session_id and public.is_condo_admin(s.condo_id)));
drop policy if exists "admin reads condo apartments" on public.apartments;
create policy "admin reads condo apartments" on public.apartments for select to authenticated using (public.is_condo_admin(condo_id));
-- Apartamentos e votos não ficam públicos. A verificação e o registro passam pelas funções seguras abaixo.

create or replace function public.create_condo(p_name text,p_identity_pattern text,p_admin_number text,p_admin_block text,p_phone text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_condo_id uuid;
begin
  if auth.uid() is null then raise exception 'login_required'; end if;
  if not public.is_root_admin() then raise exception 'root_admin_required'; end if;
  if length(trim(coalesce(p_name,'')))=0 or length(trim(coalesce(p_admin_number,'')))=0 then raise exception 'required_fields'; end if;
  if p_identity_pattern not in ('number_block','number') then raise exception 'invalid_identity_pattern'; end if;
  if p_identity_pattern='number_block' and length(trim(coalesce(p_admin_block,'')))=0 then raise exception 'block_required'; end if;
  insert into public.condos(name,identity_pattern) values(trim(p_name),p_identity_pattern) returning id into v_condo_id;
  insert into public.admins(condo_id,user_id,admin_number,admin_block,phone) values(v_condo_id,auth.uid(),trim(p_admin_number),trim(p_admin_block),coalesce(trim(p_phone),''));
  return v_condo_id;
end $$;

create or replace function public.create_vote_session(p_condo_id uuid,p_title text,p_vote_limit integer)
returns text language plpgsql security definer set search_path = '' as $$
declare v_code text; v_attempt integer:=0;
begin
  if not public.is_condo_admin(p_condo_id) then raise exception 'admin_required'; end if;
  if length(trim(coalesce(p_title,'')))=0 or p_vote_limit<1 or p_vote_limit>50 then raise exception 'invalid_vote_settings'; end if;
  loop
    v_code:=upper(substr(encode(extensions.gen_random_bytes(8),'hex'),1,8));
    begin
      insert into public.votes_sessions(condo_id,title,code,vote_limit,created_by) values(p_condo_id,trim(p_title),v_code,p_vote_limit,auth.uid());
      return v_code;
    exception when unique_violation then v_attempt:=v_attempt+1; if v_attempt>5 then raise; end if;
    end;
  end loop;
end $$;

create or replace function public.admin_add_apartment(p_condo_id uuid,p_apartment_number text,p_block text,p_phone text,p_pin text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_pattern text;
begin
  if not public.is_condo_admin(p_condo_id) then raise exception 'admin_required'; end if;
  select identity_pattern into v_pattern from public.condos where id=p_condo_id;
  if length(trim(coalesce(p_apartment_number,'')))=0 or (v_pattern='number_block' and length(trim(coalesce(p_block,'')))=0) or length(coalesce(p_pin,''))<4 then raise exception 'invalid_apartment_fields'; end if;
  perform pg_advisory_xact_lock(hashtext(p_condo_id::text));
  if exists(select 1 from public.apartments a where a.condo_id=p_condo_id and lower(trim(a.apartment_number))=lower(trim(p_apartment_number)) and (v_pattern='number' or lower(trim(a.block))=lower(trim(coalesce(p_block,''))))) then raise exception 'identity_already_exists'; end if;
  insert into public.apartments(condo_id,apartment_number,block,phone,pin_hash)
  values(p_condo_id,trim(p_apartment_number),trim(p_block),coalesce(trim(p_phone),''),extensions.crypt(p_pin,extensions.gen_salt('bf')));
end $$;

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

create or replace function public.verify_apartment(p_vote_code text,p_apartment_number text,p_block text,p_pin text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_ok boolean;
begin
  select a.pin_hash=extensions.crypt(p_pin,a.pin_hash) into v_ok
  from public.apartments a join public.votes_sessions s on s.condo_id=a.condo_id
  join public.condos c on c.id=s.condo_id
  where s.code=upper(trim(p_vote_code)) and lower(trim(a.apartment_number))=lower(trim(p_apartment_number)) and (c.identity_pattern='number' or lower(trim(a.block))=lower(trim(p_block)));
  return coalesce(v_ok,false);
end $$;

create or replace function public.toggle_vote(p_vote_code text,p_apartment_number text,p_block text,p_pin text,p_topic_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_session public.votes_sessions%rowtype; v_apartment public.apartments%rowtype;
begin
  select * into v_session from public.votes_sessions where code=upper(trim(p_vote_code));
  if not found then raise exception 'vote_not_found'; end if;
  select * into v_apartment from public.apartments a where a.condo_id=v_session.condo_id and lower(trim(a.apartment_number))=lower(trim(p_apartment_number)) and ((select c.identity_pattern from public.condos c where c.id=a.condo_id)='number' or lower(trim(a.block))=lower(trim(p_block))) for update;
  if not found or v_apartment.pin_hash<>extensions.crypt(p_pin,v_apartment.pin_hash) then raise exception 'invalid_credentials'; end if;
  if v_session.status<>'open' then raise exception 'voting_closed'; end if;
  if not exists(select 1 from public.topics t where t.id=p_topic_id and t.session_id=v_session.id) then raise exception 'topic_not_found'; end if;
  if exists(select 1 from public.votes where apartment_id=v_apartment.id and topic_id=p_topic_id) then
    delete from public.votes where apartment_id=v_apartment.id and topic_id=p_topic_id;
  else
    if (select count(*) from public.votes where apartment_id=v_apartment.id and session_id=v_session.id)>=v_session.vote_limit then raise exception 'vote_limit'; end if;
    insert into public.votes(apartment_id,session_id,topic_id) values(v_apartment.id,v_session.id,p_topic_id);
  end if;
end $$;

create or replace function public.my_votes(p_vote_code text,p_apartment_number text,p_block text,p_pin text)
returns setof uuid language plpgsql security definer set search_path = '' as $$
declare v_apartment_id uuid; v_session_id uuid;
begin
  select s.id,a.id into v_session_id,v_apartment_id from public.votes_sessions s join public.apartments a on a.condo_id=s.condo_id
  join public.condos c on c.id=s.condo_id
  where s.code=upper(trim(p_vote_code)) and lower(trim(a.apartment_number))=lower(trim(p_apartment_number)) and (c.identity_pattern='number' or lower(trim(a.block))=lower(trim(p_block))) and a.pin_hash=extensions.crypt(p_pin,a.pin_hash);
  if v_apartment_id is null then raise exception 'invalid_credentials'; end if;
  return query select v.topic_id from public.votes v where v.session_id=v_session_id and v.apartment_id=v_apartment_id;
end $$;

-- Publica apenas totais agregados para a página de apuração, sem expor apartamentos.
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

create or replace function public.update_topic_vote_count() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op='INSERT' then update public.topics set votes=votes+1 where id=new.topic_id; return new; end if;
  update public.topics set votes=greatest(0,votes-1) where id=old.topic_id; return old;
end $$;
drop trigger if exists votes_update_topic_count on public.votes;
create trigger votes_update_topic_count after insert or delete on public.votes for each row execute function public.update_topic_vote_count();

revoke all on function public.is_root_admin() from public;
revoke all on function public.is_condo_admin(uuid) from public;
revoke all on function public.create_condo(text,text,text,text,text) from public;
revoke all on function public.create_vote_session(uuid,text,integer) from public;
revoke all on function public.admin_add_apartment(uuid,text,text,text,text) from public;
revoke all on function public.register_apartment(text,text,text,text) from public;
revoke all on function public.verify_apartment(text,text,text,text) from public;
revoke all on function public.toggle_vote(text,text,text,text,uuid) from public;
revoke all on function public.my_votes(text,text,text,text) from public;
revoke all on function public.get_vote_tally(text) from public;
revoke all on function public.require_open_vote_for_new_topic() from public;
grant execute on function public.is_root_admin() to authenticated;
grant execute on function public.is_condo_admin(uuid) to authenticated;
grant execute on function public.create_condo(text,text,text,text,text) to authenticated;
grant execute on function public.create_vote_session(uuid,text,integer) to authenticated;
grant execute on function public.admin_add_apartment(uuid,text,text,text,text) to authenticated;
grant execute on function public.register_apartment(text,text,text,text) to anon,authenticated;
grant execute on function public.verify_apartment(text,text,text,text) to anon,authenticated;
grant execute on function public.toggle_vote(text,text,text,text,uuid) to anon,authenticated;
grant execute on function public.my_votes(text,text,text,text) to anon,authenticated;
grant execute on function public.get_vote_tally(text) to anon,authenticated;
grant select on public.condos,public.votes_sessions,public.topics to anon,authenticated;
grant insert,update,delete on public.votes_sessions,public.topics to authenticated;
grant select on public.root_admins,public.admins,public.condos,public.apartments to authenticated;
