create function public.project_report(input jsonb) returns jsonb language plpgsql security definer set search_path='' as $$begin
 perform private.require_roles(array['super_admin','finance']);
 return jsonb_build_object('rows',(select coalesce(jsonb_agg(t order by label,currency),'[]') from (select coalesce(p.name,'Unassigned') label,r.currency,sum(round(case when w.calculation='fixed' then w.fixed_amount else w.quantity*w.rate end,private.scale(r.currency)))::text amount from public.work_items w join public.monthly_records r on r.id=w.record_id left join public.projects p on p.id=w.project_id where r.status in ('approved','awaiting_payment','paid','archived') and r.period between (input->>'from')::date and (input->>'to')::date group by p.name,r.currency) t));
end$$;
revoke all on function public.project_report(jsonb) from public,anon;
grant execute on function public.project_report(jsonb) to authenticated;
