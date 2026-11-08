-- JPS: retiros con trazabilidad y revisión jurídica previa.
create table if not exists public.enrollment_withdrawals (
 id uuid primary key default gen_random_uuid(),
 student_id uuid not null references public.students(id),
 academic_year int not null,
 reason text not null check(reason in ('retiro','traslado','no_pago','otro')),
 effective_date date not null,
 observations text not null default 'Sin observaciones',
 supporting_reference text,
 legal_review_note text,
 status text not null default 'draft' check(status in ('draft','pending_review','completed','rejected')),
 requested_by uuid not null references public.profiles(id),
 finalized_by uuid references public.profiles(id),
 finalized_at timestamptz,
 created_at timestamptz not null default now(),
 check (status <> 'completed' or (finalized_by is not null and finalized_at is not null)),
 check (reason <> 'no_pago' or status <> 'completed' or (nullif(trim(legal_review_note),'') is not null and nullif(trim(supporting_reference),'') is not null))
);
create unique index if not exists withdrawals_one_completed_per_enrollment on public.enrollment_withdrawals(student_id,academic_year) where status='completed';
create table if not exists public.enrollment_status (
 student_id uuid not null references public.students(id),
 academic_year int not null,
 status text not null default 'active' check(status in ('active','withdrawn')),
 effective_date date,
 withdrawal_id uuid references public.enrollment_withdrawals(id),
 primary key(student_id,academic_year)
);
alter table public.enrollment_withdrawals enable row level security;
alter table public.enrollment_status enable row level security;
drop policy if exists withdrawal_admin_read on public.enrollment_withdrawals;
create policy withdrawal_admin_read on public.enrollment_withdrawals for select to authenticated using(public.is_admin());
drop policy if exists enrollment_status_admin_read on public.enrollment_status;
create policy enrollment_status_admin_read on public.enrollment_status for select to authenticated using(public.is_admin());
-- No INSERT/UPDATE/DELETE directos a tablas: únicamente RPC con auth.uid() comprobado.
create or replace function public.admin_request_withdrawal(p_student_id uuid,p_year int,p_reason text,p_effective_date date,p_observations text default 'Sin observaciones',p_support text default null,p_legal_note text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
 if not public.is_admin() then raise exception 'Solo administrador'; end if;
 if not exists(select 1 from public.students where id=p_student_id) then raise exception 'Estudiante no encontrado'; end if;
 if p_reason not in ('retiro','traslado','no_pago','otro') then raise exception 'Motivo inválido'; end if;
 if p_year<2016 or p_year>2100 or extract(year from p_effective_date)::int<>p_year then raise exception 'Año y fecha inconsistentes'; end if;
 if exists(select 1 from public.enrollment_withdrawals where student_id=p_student_id and academic_year=p_year and status='completed') then raise exception 'Matrícula ya retirada'; end if;
 insert into public.enrollment_withdrawals(student_id,academic_year,reason,effective_date,observations,supporting_reference,legal_review_note,status,requested_by)
 values(p_student_id,p_year,p_reason,p_effective_date,coalesce(nullif(trim(p_observations),''),'Sin observaciones'),nullif(trim(p_support),''),nullif(trim(p_legal_note),''),'pending_review',auth.uid()) returning id into v_id;
 insert into public.audit_log(actor_id,action,entity_id,details) values(auth.uid(),'request_enrollment_withdrawal',v_id,jsonb_build_object('student_id',p_student_id,'year',p_year,'reason',p_reason));
 return v_id;
end $$;
create or replace function public.admin_finalize_withdrawal(p_withdrawal_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare w public.enrollment_withdrawals%rowtype;
begin
 if not public.is_admin() then raise exception 'Solo administrador'; end if;
 select * into w from public.enrollment_withdrawals where id=p_withdrawal_id for update;
 if not found or w.status<>'pending_review' then raise exception 'Solicitud no disponible'; end if;
 if w.reason='no_pago' and (nullif(trim(w.legal_review_note),'') is null or nullif(trim(w.supporting_reference),'') is null) then raise exception 'Se requiere revisión jurídica documentada y soporte'; end if;
 if exists(select 1 from public.enrollment_withdrawals where student_id=w.student_id and academic_year=w.academic_year and status='completed') then raise exception 'Ya existe retiro efectivo'; end if;
 update public.enrollment_withdrawals set status='completed',finalized_by=auth.uid(),finalized_at=now() where id=w.id;
 insert into public.enrollment_status(student_id,academic_year,status,effective_date,withdrawal_id) values(w.student_id,w.academic_year,'withdrawn',w.effective_date,w.id)
 on conflict(student_id,academic_year) do update set status='withdrawn',effective_date=excluded.effective_date,withdrawal_id=excluded.withdrawal_id;
 insert into public.audit_log(actor_id,action,entity_id,details) values(auth.uid(),'finalize_enrollment_withdrawal',w.id,jsonb_build_object('student_id',w.student_id,'effective_date',w.effective_date));
 -- No eliminar cobros, comprobantes, becas, acuerdos ni pagos; obligaciones futuras requieren revisión separada.
end $$;
revoke all on function public.admin_request_withdrawal(uuid,int,text,date,text,text,text) from public,anon;
revoke all on function public.admin_finalize_withdrawal(uuid) from public,anon;
grant execute on function public.admin_request_withdrawal(uuid,int,text,date,text,text,text) to authenticated;
grant execute on function public.admin_finalize_withdrawal(uuid) to authenticated;
