-- Habilita o cadastro do apartamento pelo morador no primeiro acesso.
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
