-- Ejecutar DESPUÉS de 005. Requiere validar en un proyecto de pruebas.
-- Ventanas de cinco días CALENDARIO. Solo pagos de febrero a noviembre.
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check(role in ('guardian','admin','coordinator'));
create or replace function public.is_staff() returns boolean language sql stable security definer set search_path=public as $$select exists(select 1 from public.profiles where id=auth.uid() and role in ('admin','coordinator'))$$;
create table if not exists public.payment_calendars (
 id uuid primary key default gen_random_uuid(), student_id uuid not null references public.students(id),
 academic_year int not null check(academic_year between 2016 and 2100),
 mode text not null check(mode in ('general','personalizado')),
 start_day int not null check(start_day between 1 and 28),
 updated_by uuid not null references public.profiles(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(student_id,academic_year)
);
create table if not exists public.payment_calendar_audit (
 id bigint generated always as identity primary key, student_id uuid not null,academic_year int not null,
 old_value jsonb,new_value jsonb,changed_by uuid not null,changed_at timestamptz not null default now()
);
alter table public.payment_calendars enable row level security;
alter table public.payment_calendar_audit enable row level security;
create policy calendars_read on public.payment_calendars for select to authenticated using(public.is_staff() or public.can_see_student(student_id));
create policy calendar_audit_read on public.payment_calendar_audit for select to authenticated using(public.is_admin());
-- Para permitir al coordinador consultar estudiantes, obligaciones y comprobantes.
create policy coordinator_students_read on public.students for select to authenticated using(public.is_staff());
create policy coordinator_charges_read on public.charges for select to authenticated using(public.is_staff());
create policy coordinator_reports_read on public.payment_reports for select to authenticated using(public.is_staff());
create policy coordinator_guardian_links_read on public.guardian_students for select to authenticated using(public.is_staff());
create policy coordinator_profiles_read on public.profiles for select to authenticated using(public.is_staff());
create policy coordinator_scholarships_read on public.scholarships for select to authenticated using(public.is_staff());
-- NOTA: este MVP concede a coordinadores lectura de TODAS las sedes. Limitar por sede antes de producción.
create or replace function public.staff_set_payment_calendar(p_student_id uuid,p_year int,p_mode text,p_start_day int)
returns void language plpgsql security definer set search_path=public as $$
declare previous jsonb; updated jsonb;
begin
 if not public.is_staff() then raise exception 'Solo administración o coordinación'; end if;
 if p_mode not in ('general','personalizado') or p_year not between 2016 and 2100 then raise exception 'Parámetros inválidos';end if;
 if p_mode='personalizado' and (p_start_day is null or p_start_day not between 1 and 28) then raise exception 'Inicio entre 1 y 28';end if;
 if not exists(select 1 from public.students where id=p_student_id) then raise exception 'Estudiante inexistente';end if;
 select to_jsonb(c) into previous from public.payment_calendars c where student_id=p_student_id and academic_year=p_year for update;
 insert into public.payment_calendars(student_id,academic_year,mode,start_day,updated_by)
 values(p_student_id,p_year,p_mode,case when p_mode='general' then 1 else p_start_day end,auth.uid())
 on conflict(student_id,academic_year) do update set mode=excluded.mode,start_day=excluded.start_day,updated_by=excluded.updated_by,updated_at=now();
 select to_jsonb(c) into updated from public.payment_calendars c where student_id=p_student_id and academic_year=p_year;
 insert into public.payment_calendar_audit(student_id,academic_year,old_value,new_value,changed_by) values(p_student_id,p_year,previous,updated,auth.uid());
end $$;
revoke all on function public.staff_set_payment_calendar(uuid,int,text,int) from public,anon;
grant execute on function public.staff_set_payment_calendar(uuid,int,text,int) to authenticated;
-- Se calcula a partir del mes de la cuota; el calendario general conserva el día 5.
create or replace function public.pension_due_date(p_student_id uuid,p_year int,p_month int)
returns date language plpgsql stable security definer set search_path=public as $$
declare start_d int;
begin
 if p_month not between 2 and 11 then raise exception 'Pensión solo de febrero a noviembre';end if;
 select case when mode='personalizado' then start_day else 1 end into start_d from public.payment_calendars where student_id=p_student_id and academic_year=p_year;
 return make_date(p_year,p_month,coalesce(start_d,1))+4;
end $$;
-- La cuota debe estar vinculada a su mes de causación para evitar confundir meses al cruzar de mes.
alter table public.charges add column if not exists pension_month int check(pension_month between 2 and 11);
-- Recalcular fecha límite solo cuando el mes está explícitamente informado.
create or replace function public.effective_charge_due_date(p_charge_id uuid)
returns date language sql stable security definer set search_path=public as $$
 select case when c.kind='pension' and c.pension_month is not null
 then public.pension_due_date(c.student_id,c.academic_year,c.pension_month)
 else c.due_date end from public.charges c where c.id=p_charge_id
$$;
-- Medios de pago. Recibo obligatorio: proof_path NOT NULL ya existe.
alter table public.payment_reports add column if not exists payment_method text not null default 'transferencia' check(payment_method in ('efectivo','transferencia'));
alter table public.payment_reports add column if not exists payment_bank text;
-- Permitir que coordinadores reporten pagos, conservando el aprobador exclusivo administrador.
create policy coordinator_reports_insert on public.payment_reports for insert to authenticated with check(
 public.is_staff() and guardian_id=auth.uid() and status='pending' and proof_path<>'' and
 reviewed_by is null and reviewed_at is null and receipt_number is null and
 exists(select 1 from public.charges c where c.id=charge_id and c.student_id=student_id and c.status='pending')
);
-- Para el reporte de un coordinador, guardian_id actúa como usuario REPORTANTE.
-- Antes de producción separar reporter_id de guardian_id para evitar confusión en recibos.
-- La aprobación debe usar effective_charge_due_date y el monto exigible neto.
-- Se reemplaza la función original para validar la fecha de pago real.
create or replace function public.approve_payment_atomic(p_report_id uuid,p_admin_id uuid)
returns bigint language plpgsql security definer set search_path=public as $$
declare r public.payment_reports%rowtype;c public.charges%rowtype;n bigint;expected numeric;due_d date;
begin
 if not exists(select 1 from public.profiles where id=p_admin_id and role='admin') then raise exception 'Solo administrador';end if;
 select * into r from public.payment_reports where id=p_report_id for update;
 if not found or r.status<>'pending' then raise exception 'Reporte no pendiente';end if;
 select * into c from public.charges where id=r.charge_id for update;
 if not found or c.status<>'pending' or c.student_id<>r.student_id then raise exception 'Obligación no disponible';end if;
 due_d:=public.effective_charge_due_date(c.id);
 expected:=c.amount + case when c.kind='pension' and c.amount>0 and due_d is not null and r.paid_at>due_d then 10000 else 0 end;
 if r.reported_amount<expected then raise exception 'Valor inferior al exigido (incluido recargo)';end if;
 if exists(select 1 from public.payment_reports where lower(reference)=lower(r.reference) and status='approved') then raise exception 'Referencia ya aprobada';end if;
 n:=nextval('public.receipt_seq');
 update public.payment_reports set status='approved',reviewed_by=p_admin_id,reviewed_at=now(),receipt_number=n where id=r.id;
 update public.charges set status='paid' where id=c.id;
 insert into public.audit_log(actor_id,action,entity_id,details) values(p_admin_id,'approve_payment',r.id,jsonb_build_object('receipt',n,'amount',r.reported_amount,'method',r.payment_method));
 return n;
end $$;
revoke all on function public.approve_payment_atomic(uuid,uuid) from public,anon,authenticated;
grant execute on function public.approve_payment_atomic(uuid,uuid) to service_role;
