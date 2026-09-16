create function public.read_payment_details(person_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$declare info text;begin
 perform private.require_roles(array['super_admin','finance']);
 if not exists(select 1 from public.personnel where id=person_id) then raise exception 'Personnel not found.';end if;
 select payment_info into info from public.personnel_payment_details where personnel_id=person_id;
 perform private.audit('Personnel payment details viewed',person_id,null,null,null);
 return jsonb_build_object('payment_info',coalesce(info,''));
end$$;
revoke all on function public.read_payment_details(uuid) from public,anon;
grant execute on function public.read_payment_details(uuid) to authenticated;
