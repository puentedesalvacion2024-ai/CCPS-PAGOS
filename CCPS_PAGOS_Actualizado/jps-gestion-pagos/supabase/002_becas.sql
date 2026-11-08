-- Ejecutar DESPUÉS de schema.sql. No ejecutar sobre datos reales sin pruebas.
create table if not exists public.scholarships (
 id uuid primary key default gen_random_uuid(),
 student_id uuid not null references public.students(id),
 academic_year int not null,
 kind text not null check (kind in ('full','partial')),
 scope text not null check (scope in ('matricula','pension','both')),
 percent_matricula numeric(5,2) not null default 0 check(percent_matricula between 0 and 100),
 percent_pension numeric(5,2) not null default 0 check(percent_pension between 0 and 100),
 valid_from date not null, valid_until date not null,
 status text not null default 'active' check(status in ('active','suspended','cancelled')),
 reason text, approved_by uuid not null references public.profiles(id),
 approved_at timestamptz not null default now(),
 check(valid_until>=valid_from),
 check((scope='matricula' and percent_pension=0) or (scope='pension' and percent_matricula=0) or scope='both'),
 check(kind<>'full' or (scope='matricula' and percent_matricula=100) or (scope='pension' and percent_pension=100) or (scope='both' and percent_matricula=100 and percent_pension=100))
);
create unique index if not exists one_active_scholarship_per_student_year on public.scholarships(student_id,academic_year) where status='active';
alter table public.scholarships enable row level security;
create policy scholarships_read on public.scholarships for select to authenticated using(public.can_see_student(student_id));
-- No policies for INSERT/UPDATE/DELETE: changes only via secured administrator backend.

-- Calculate net payable on an obligation; scholarship applies to tuition or enrollment only.
-- Due date determines applicable scholarship; discounts do not apply to late fees.
create or replace function public.charge_net_amount(p_charge_id uuid, p_paid_at date)
returns numeric language plpgsql stable security definer set search_path=public as $$
declare c public.charges%rowtype; pct numeric:=0; gross numeric; 
begin
 select * into c from public.charges where id=p_charge_id;
 if not found then raise exception 'Obligación inexistente'; end if;
 if c.kind in ('pension','matricula') then
  select case when c.kind='pension' then s.percent_pension else s.percent_matricula end
    into pct from public.scholarships s
   where s.student_id=c.student_id and s.academic_year=c.academic_year
     and s.status='active' and coalesce(c.due_date,make_date(c.academic_year,1,1)) between s.valid_from and s.valid_until
   limit 1;
 end if;
 gross:=round(c.amount*(1-coalesce(pct,0)/100),2);
 -- Only charge mora if the discounted pension has a positive balance due.
 return gross + case when c.kind='pension' and gross>0 and c.due_date is not null and p_paid_at>c.due_date then 10000 else 0 end;
end $$;
revoke all on function public.charge_net_amount(uuid,date) from public,anon;
grant execute on function public.charge_net_amount(uuid,date) to authenticated,service_role;

create or replace function public.approve_payment_atomic(p_report_id uuid,p_admin_id uuid)
returns bigint language plpgsql security definer set search_path=public as $$
declare r public.payment_reports%rowtype; c public.charges%rowtype; n bigint; expected numeric;
begin
 if not exists(select 1 from public.profiles where id=p_admin_id and role='admin') then raise exception 'No autorizado';end if;
 select * into r from public.payment_reports where id=p_report_id for update;
 if not found or r.status<>'pending' then raise exception 'Reporte no pendiente';end if;
 select * into c from public.charges where id=r.charge_id for update;
 if not found or c.status<>'pending' or c.student_id<>r.student_id then raise exception 'Obligación no disponible';end if;
 expected:=public.charge_net_amount(c.id,r.paid_at);
 if expected=0 then raise exception 'Obligación cubierta totalmente por beca: no requiere consignación';end if;
 if r.reported_amount<expected then raise exception 'Valor inferior al exigido, incluidos beca y recargo';end if;
 if exists(select 1 from public.payment_reports where lower(reference)=lower(r.reference) and status='approved') then raise exception 'Referencia ya aprobada';end if;
 n:=nextval('public.receipt_seq');
 update public.payment_reports set status='approved',reviewed_by=p_admin_id,reviewed_at=now(),receipt_number=n where id=r.id;
 update public.charges set status='paid' where id=c.id;
 insert into public.audit_log(actor_id,action,entity_id,details) values(p_admin_id,'approve_payment',r.id,jsonb_build_object('receipt',n,'amount',r.reported_amount,'net_due',expected));
 return n;
end $$;
revoke all on function public.approve_payment_atomic(uuid,uuid) from public,anon,authenticated;
grant execute on function public.approve_payment_atomic(uuid,uuid) to service_role;
