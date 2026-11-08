-- Ejecutar después de schema.sql y 002_becas.sql. Probar antes de producción.
-- Solo funciones SECURITY DEFINER verificadas contra rol administrativo.
create or replace function public.admin_assign_scholarship(
 p_student_id uuid, p_year int, p_matricula numeric, p_pension numeric, p_reason text default ''
) returns uuid language plpgsql security definer set search_path=public as $$
declare new_id uuid; scope_value text; kind_value text;
begin
 if auth.uid() is null or not public.is_admin() then raise exception 'No autorizado'; end if;
 if not exists(select 1 from public.students where id=p_student_id and academic_year=p_year) then raise exception 'Estudiante no pertenece al año seleccionado'; end if;
 if p_matricula is null or p_pension is null or p_matricula<0 or p_pension<0 or p_matricula>100 or p_pension>100 or p_matricula+p_pension=0 then raise exception 'Porcentajes inválidos'; end if;
 scope_value:=case when p_matricula>0 and p_pension>0 then 'both' when p_matricula>0 then 'matricula' else 'pension' end;
 kind_value:=case when (p_matricula=0 or p_matricula=100) and (p_pension=0 or p_pension=100) then 'full' else 'partial' end;
 update public.scholarships set status='cancelled' where student_id=p_student_id and academic_year=p_year and status='active';
 insert into public.scholarships(student_id,academic_year,kind,scope,percent_matricula,percent_pension,valid_from,valid_until,status,reason,approved_by)
 values(p_student_id,p_year,kind_value,scope_value,p_matricula,p_pension,make_date(p_year,1,1),make_date(p_year,12,31),'active',left(coalesce(p_reason,''),400),auth.uid()) returning id into new_id;
 insert into public.audit_log(actor_id,action,entity_id,details) values(auth.uid(),'admin_assign_scholarship',new_id,jsonb_build_object('student_id',p_student_id,'year',p_year,'matricula',p_matricula,'pension',p_pension));
 return new_id;
end $$;
create or replace function public.admin_create_charge(
 p_student_id uuid,p_kind text,p_description text,p_amount numeric,p_due_date date,p_year int
) returns uuid language plpgsql security definer set search_path=public as $$
declare new_id uuid;
begin
 if auth.uid() is null or not public.is_admin() then raise exception 'No autorizado'; end if;
 if not exists(select 1 from public.students where id=p_student_id and academic_year=p_year) then raise exception 'Estudiante no pertenece al año seleccionado'; end if;
 if p_kind not in ('pension','matricula','uniforme','grado','informe','otro') or p_amount is null or p_amount<=0 or p_due_date is null or length(trim(coalesce(p_description,'')))=0 then raise exception 'Datos de obligación inválidos'; end if;
 if p_kind='pension' and (extract(month from p_due_date)<2 or extract(month from p_due_date)>11 or extract(day from p_due_date)<>5 or extract(year from p_due_date)<>p_year) then raise exception 'Las pensiones vencen el día 5, de febrero a noviembre'; end if;
 insert into public.charges(student_id,kind,description,amount,due_date,academic_year)
 values(p_student_id,p_kind,left(trim(p_description),200),p_amount,p_due_date,p_year) returning id into new_id;
 insert into public.audit_log(actor_id,action,entity_id,details) values(auth.uid(),'admin_create_charge',new_id,jsonb_build_object('student_id',p_student_id,'amount',p_amount,'kind',p_kind));
 return new_id;
end $$;
revoke all on function public.admin_assign_scholarship(uuid,int,numeric,numeric,text) from public,anon;
revoke all on function public.admin_create_charge(uuid,text,text,numeric,date,int) from public,anon;
grant execute on function public.admin_assign_scholarship(uuid,int,numeric,numeric,text) to authenticated;
grant execute on function public.admin_create_charge(uuid,text,text,numeric,date,int) to authenticated;
