-- Ejecutar después de 003_panel_administrativo.sql. Acceso exclusivo a administradores.
-- No modifica pagos existentes. Cálculo de recaudo sobre fecha bancaria reportada
-- y APROBADA; el pago no se cuenta por fecha de aprobación.
create or replace function public.admin_finance_dashboard(p_year int default 2026,p_campus text default 'todas')
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
 if auth.uid() is null or not public.is_admin() then raise exception 'Acceso exclusivo de administración'; end if;
 if p_year < 2016 or p_year > 2100 then raise exception 'Año inválido'; end if;
 if p_campus not in ('todas','Porfía','Campestre','Acacías','Restrepo') then raise exception 'Sede inválida'; end if;
 with filtered_students as (
  select id,name,campus from public.students where (p_campus='todas' or campus=p_campus)
 ), payments as (
  select r.id,r.reported_amount,r.paid_at,r.status
  from public.payment_reports r join filtered_students s on s.id=r.student_id
  where r.status='approved' and extract(year from r.paid_at)=p_year
 ), month_totals as (
  select g.m as month,coalesce(sum(p.reported_amount),0) as amount
  from generate_series(1,12) g(m) left join payments p on extract(month from p.paid_at)=g.m
  group by g.m
 ), overdue as (
  select c.id,c.student_id,c.amount,
    (c.amount+case when c.kind='pension' and c.amount>0 and current_date>c.due_date then 10000 else 0 end)::numeric as due_total
  from public.charges c join filtered_students s on s.id=c.student_id
  where c.academic_year=p_year and c.status='pending' and c.due_date<current_date and c.amount>0
 ), guardian_debts as (
  select gs.guardian_id,sum(o.due_total) as amount,count(distinct o.id) as overdue_charges,
   string_agg(distinct s.name,', ' order by s.name) as students
  from overdue o join public.guardian_students gs on gs.student_id=o.student_id
  join filtered_students s on s.id=o.student_id
  group by gs.guardian_id
 ), debtor_rows as (
  select p.full_name as guardian,p.cedula,d.students,d.amount,d.overdue_charges
  from guardian_debts d join public.profiles p on p.id=d.guardian_id
 ), pending_count as (
  select count(*) as n from public.payment_reports r join filtered_students s on s.id=r.student_id where r.status='pending'
 )
 select jsonb_build_object(
  'year',p_year,'campus',p_campus,
  'annual_income',(select coalesce(sum(reported_amount),0) from payments),
  'current_month_income',(select coalesce(sum(reported_amount),0) from payments where extract(month from paid_at)=extract(month from current_date) and extract(year from current_date)=p_year),
  'overdue_total',(select coalesce(sum(due_total),0) from overdue),
  'delinquent_guardians',(select count(*) from guardian_debts),
  'pending_reports',(select n from pending_count),
  'months',(select coalesce(jsonb_agg(jsonb_build_object('month',month,'amount',amount) order by month),'[]'::jsonb) from month_totals),
  'debtors',(select coalesce(jsonb_agg(jsonb_build_object('guardian',guardian,'cedula',cedula,'students',students,'amount',amount,'overdue_charges',overdue_charges) order by amount desc),'[]'::jsonb) from debtor_rows)
 ) into result;
 return result;
end $$;
revoke all on function public.admin_finance_dashboard(int,text) from public,anon;
grant execute on function public.admin_finance_dashboard(int,text) to authenticated;
