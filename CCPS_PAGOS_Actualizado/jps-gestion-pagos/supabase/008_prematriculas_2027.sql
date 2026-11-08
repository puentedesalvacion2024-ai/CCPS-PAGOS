-- Ejecutar después de 007. Prematrícula 2027: $150.000, activada.
-- Requiere esquema base, perfiles y políticas anteriores.
ALTER TABLE public.charges DROP CONSTRAINT IF EXISTS charges_kind_check;
ALTER TABLE public.charges ADD CONSTRAINT charges_kind_check CHECK (kind IN ('pension','matricula','uniforme','grado','informe','otro','prematricula'));
CREATE TABLE IF NOT EXISTS public.preenrollment_settings (
 academic_year integer PRIMARY KEY CHECK (academic_year BETWEEN 2016 AND 2100),
 enabled boolean NOT NULL DEFAULT false,
 amount numeric(12,2) NOT NULL CHECK (amount > 0),
 due_date date,
 updated_by uuid REFERENCES public.profiles(id),
 updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.preenrollment_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS preenrollment_settings_read ON public.preenrollment_settings;
CREATE POLICY preenrollment_settings_read ON public.preenrollment_settings FOR SELECT TO authenticated USING (true);
INSERT INTO public.preenrollment_settings(academic_year,enabled,amount,due_date)
VALUES (2027,true,150000,NULL) ON CONFLICT(academic_year) DO NOTHING;
CREATE UNIQUE INDEX IF NOT EXISTS unique_preenrollment_charge_per_student_year
 ON public.charges(student_id,academic_year) WHERE kind='prematricula' AND status<>'cancelled';
-- Solo administración puede activar/desactivar, cambiar monto y fecha.
CREATE OR REPLACE FUNCTION public.admin_set_preenrollment(p_year integer,p_enabled boolean,p_amount numeric,p_due_date date DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE before_state jsonb;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Solo el administrador puede configurar prematrículas'; END IF;
 IF p_year NOT BETWEEN 2016 AND 2100 OR p_amount IS NULL OR p_amount<=0 THEN RAISE EXCEPTION 'Año o valor inválido'; END IF;
 SELECT to_jsonb(s) INTO before_state FROM public.preenrollment_settings s WHERE academic_year=p_year;
 INSERT INTO public.preenrollment_settings(academic_year,enabled,amount,due_date,updated_by)
 VALUES(p_year,p_enabled,p_amount,p_due_date,auth.uid())
 ON CONFLICT(academic_year) DO UPDATE SET enabled=EXCLUDED.enabled,amount=EXCLUDED.amount,due_date=EXCLUDED.due_date,updated_by=auth.uid(),updated_at=now();
 INSERT INTO public.audit_log(actor_id,action,details) VALUES(auth.uid(),'preenrollment_settings_changed',jsonb_build_object('year',p_year,'previous',before_state,'enabled',p_enabled,'amount',p_amount,'due_date',p_due_date));
END $$;
REVOKE ALL ON FUNCTION public.admin_set_preenrollment(integer,boolean,numeric,date) FROM public,anon;
GRANT EXECUTE ON FUNCTION public.admin_set_preenrollment(integer,boolean,numeric,date) TO authenticated;
-- Crea un cobro por estudiante solo cuando la campaña está activa. No crea cobros masivos al activar.
CREATE OR REPLACE FUNCTION public.admin_assign_preenrollment(p_student_id uuid,p_year integer)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE setting_row public.preenrollment_settings%ROWTYPE; charge_id uuid;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Solo el administrador puede crear cobros'; END IF;
 SELECT * INTO setting_row FROM public.preenrollment_settings WHERE academic_year=p_year;
 IF NOT FOUND OR NOT setting_row.enabled THEN RAISE EXCEPTION 'El cobro de prematrícula está desactivado'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.students WHERE id=p_student_id) THEN RAISE EXCEPTION 'Estudiante inexistente'; END IF;
 INSERT INTO public.charges(student_id,kind,description,amount,due_date,academic_year,status)
 VALUES(p_student_id,'prematricula','Prematrícula '||p_year,setting_row.amount,setting_row.due_date,p_year,'pending')
 ON CONFLICT (student_id,academic_year) WHERE kind='prematricula' AND status<>'cancelled' DO NOTHING
 RETURNING id INTO charge_id;
 IF charge_id IS NULL THEN RAISE EXCEPTION 'El estudiante ya tiene prematrícula asignada'; END IF;
 INSERT INTO public.audit_log(actor_id,action,entity_id,details) VALUES(auth.uid(),'preenrollment_charge_created',charge_id,jsonb_build_object('student_id',p_student_id,'year',p_year,'amount',setting_row.amount));
 RETURN charge_id;
END $$;
REVOKE ALL ON FUNCTION public.admin_assign_preenrollment(uuid,integer) FROM public,anon;
GRANT EXECUTE ON FUNCTION public.admin_assign_preenrollment(uuid,integer) TO authenticated;
-- Al desactivar: no se borran cobros, comprobantes ni recibos existentes.
-- La aprobación usa el flujo general approve-payment: exclusivamente administrador.
-- El formulario existente exige comprobante de efectivo o transferencia.
-- Los reportes generales contabilizan los pagos aprobados y la cartera por concepto.
