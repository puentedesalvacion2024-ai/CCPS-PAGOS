-- JPS Gestión de Pagos: esquema inicial. Ejecutar en Supabase SQL Editor.
create extension if not exists pgcrypto;
create table public.profiles (id uuid primary key references auth.users(id) on delete cascade, cedula text unique not null, full_name text not null, role text not null default 'guardian' check(role in ('guardian','admin')), email text, created_at timestamptz default now());
create table public.students (id uuid primary key default gen_random_uuid(), document text unique, name text not null, grade text not null, campus text not null, academic_year int not null default 2027, created_at timestamptz default now());
create table public.guardian_students (guardian_id uuid not null references public.profiles(id) on delete cascade, student_id uuid not null references public.students(id) on delete cascade, primary key(guardian_id,student_id));
create table public.charges (id uuid primary key default gen_random_uuid(), student_id uuid not null references public.students(id), kind text not null check(kind in ('pension','matricula','uniforme','grado','informe','otro')), description text not null, amount numeric(12,2) not null check(amount>=0), due_date date, status text not null default 'pending' check(status in ('pending','paid','cancelled')), academic_year int not null default 2027, created_at timestamptz default now());
create table public.enrollment_agreements (id uuid primary key default gen_random_uuid(), student_id uuid not null references public.students(id), total_amount numeric(12,2) not null check(total_amount>0), approved_by uuid not null references public.profiles(id), approved_at timestamptz not null default now(), status text not null default 'active' check(status in ('active','completed','cancelled')), terms text);
create table public.agreement_installments (id uuid primary key default gen_random_uuid(), agreement_id uuid not null references public.enrollment_agreements(id) on delete cascade, installment_number int not null, amount numeric(12,2) not null check(amount>0), due_date date not null, charge_id uuid unique references public.charges(id), unique(agreement_id,installment_number));
create table public.uniform_catalog (id uuid primary key default gen_random_uuid(), name text unique not null, category text not null check(category in ('diario','educacion_fisica')), price numeric(12,2) not null default 0 check(price>=0), active boolean default true);
insert into public.uniform_catalog(name,category) values ('Camisa de diario','diario'),('Jean de diario','diario'),('Bermuda de diario','diario'),('Camisa de educación física','educacion_fisica'),('Pantaloneta de educación física','educacion_fisica'),('Sudadera de educación física','educacion_fisica') on conflict do nothing;
create table public.uniform_orders (id uuid primary key default gen_random_uuid(), student_id uuid not null references public.students(id), status text not null default 'pending' check(status in ('pending','partially_delivered','delivered','cancelled')), charge_id uuid references public.charges(id), created_at timestamptz default now());
create table public.uniform_order_items (id uuid primary key default gen_random_uuid(), order_id uuid not null references public.uniform_orders(id) on delete cascade, catalog_id uuid not null references public.uniform_catalog(id), size text, quantity int not null check(quantity>0), unit_price numeric(12,2) not null check(unit_price>=0));
create table public.payment_reports (id uuid primary key default gen_random_uuid(), student_id uuid not null references public.students(id), charge_id uuid not null references public.charges(id), guardian_id uuid not null references public.profiles(id), reported_amount numeric(12,2) not null check(reported_amount>0), paid_at date not null, reference text not null, proof_path text not null, status text not null default 'pending' check(status in ('pending','approved','rejected')), reviewed_by uuid references public.profiles(id), reviewed_at timestamptz, receipt_number bigint unique, rejection_reason text, created_at timestamptz default now());
create sequence public.receipt_seq start 1;
create unique index unique_approved_reference on public.payment_reports (lower(reference)) where status='approved';
create table public.audit_log (id bigint generated always as identity primary key, actor_id uuid, action text not null, entity_id uuid, details jsonb, created_at timestamptz default now());
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$select exists(select 1 from public.profiles where id=auth.uid() and role='admin')$$;
create or replace function public.can_see_student(sid uuid) returns boolean language sql stable security definer set search_path=public as $$select public.is_admin() or exists(select 1 from public.guardian_students where guardian_id=auth.uid() and student_id=sid)$$;
alter table public.profiles enable row level security;alter table public.students enable row level security;alter table public.guardian_students enable row level security;alter table public.charges enable row level security;alter table public.enrollment_agreements enable row level security;alter table public.agreement_installments enable row level security;alter table public.uniform_catalog enable row level security;alter table public.uniform_orders enable row level security;alter table public.uniform_order_items enable row level security;alter table public.payment_reports enable row level security;alter table public.audit_log enable row level security;
create policy profile_read on public.profiles for select to authenticated using(id=auth.uid() or public.is_admin());
create policy students_read on public.students for select to authenticated using(public.can_see_student(id));
create policy links_read on public.guardian_students for select to authenticated using(guardian_id=auth.uid() or public.is_admin());
create policy charges_read on public.charges for select to authenticated using(public.can_see_student(student_id));
create policy agreements_read on public.enrollment_agreements for select to authenticated using(public.can_see_student(student_id));
create policy installments_read on public.agreement_installments for select to authenticated using(exists(select 1 from public.enrollment_agreements a where a.id=agreement_id and public.can_see_student(a.student_id)));
create policy catalog_read on public.uniform_catalog for select to authenticated using(true);
create policy orders_read on public.uniform_orders for select to authenticated using(public.can_see_student(student_id));
create policy orderitems_read on public.uniform_order_items for select to authenticated using(exists(select 1 from public.uniform_orders o where o.id=order_id and public.can_see_student(o.student_id)));
create policy reports_read on public.payment_reports for select to authenticated using(public.is_admin() or guardian_id=auth.uid());
-- Acudiente solo puede insertar reporte pendiente, asociado a su hijo y su obligación.
create policy reports_insert on public.payment_reports for insert to authenticated with check(guardian_id=auth.uid() and status='pending' and reviewed_by is null and reviewed_at is null and receipt_number is null and public.can_see_student(student_id) and exists(select 1 from public.charges c where c.id=charge_id and c.student_id=student_id and c.status='pending'));
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values ('payment-proofs','payment-proofs',false,5242880,array['image/jpeg','image/png','application/pdf']) on conflict(id) do nothing;
create policy proof_upload on storage.objects for insert to authenticated with check(bucket_id='payment-proofs' and (storage.foldername(name))[1]=auth.uid()::text);
-- No lectura pública de comprobantes. Los administra el backend con service role.
-- Prohibir modificaciones directas: todas las aprobaciones y cobros se gestionan desde funciones seguras.
-- Aprobación transaccional; solo invocada con service role desde Netlify.
create or replace function public.approve_payment_atomic(p_report_id uuid,p_admin_id uuid) returns bigint language plpgsql security definer set search_path=public as $$
declare r public.payment_reports%rowtype; c public.charges%rowtype; n bigint; expected numeric;
begin
 if not exists(select 1 from public.profiles where id=p_admin_id and role='admin') then raise exception 'No autorizado';end if;
 select * into r from public.payment_reports where id=p_report_id for update;
 if not found or r.status<>'pending' then raise exception 'Reporte no pendiente';end if;
 select * into c from public.charges where id=r.charge_id for update;
 if not found or c.status<>'pending' or c.student_id<>r.student_id then raise exception 'Obligación no disponible';end if;
 expected:=c.amount + case when c.kind='pension' and c.due_date is not null and r.paid_at>c.due_date then 10000 else 0 end;
 if r.reported_amount<expected then raise exception 'Valor inferior al exigido, incluido recargo';end if;
 if exists(select 1 from public.payment_reports where lower(reference)=lower(r.reference) and status='approved') then raise exception 'Referencia ya aprobada';end if;
 n:=nextval('public.receipt_seq');
 update public.payment_reports set status='approved',reviewed_by=p_admin_id,reviewed_at=now(),receipt_number=n where id=r.id;
 update public.charges set status='paid' where id=c.id;
 insert into public.audit_log(actor_id,action,entity_id,details) values(p_admin_id,'approve_payment',r.id,jsonb_build_object('receipt',n,'amount',r.reported_amount));
 return n;
end $$;
revoke all on function public.approve_payment_atomic(uuid,uuid) from public,anon,authenticated;
grant execute on function public.approve_payment_atomic(uuid,uuid) to service_role;
