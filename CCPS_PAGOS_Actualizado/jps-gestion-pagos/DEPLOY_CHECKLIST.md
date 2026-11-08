# JPS Gestión de Pagos — guía de despliegue (versión de desarrollo)

**Aviso:** este ZIP es un proyecto de desarrollo, NO una plataforma lista para operar con datos reales ni un despliegue ya realizado. No se ha probado contra una instancia Supabase ni contra Netlify. Hay módulos solicitados aún pendientes (véase abajo).

## Requisitos
- Cuenta de Supabase con PostgreSQL, Auth y Storage.
- Cuenta de Netlify y repositorio Git.
- Node.js 20+ y npm.
- Dominio verificado y proveedor transaccional de correo para notificaciones.

## Pasos
1. Descomprima el ZIP. Ejecute `npm install` y `npm run build` en un equipo con acceso a npm.
2. Cree un proyecto **de pruebas** en Supabase. En SQL Editor ejecute **en este orden** `supabase/schema.sql`, `002_becas.sql`, `003_panel_administrativo.sql`, `004_dashboard_financiero.sql`, `005_retiros_matricula.sql`, `006_calendarios_coordinadores_medios.sql`, `007_dashboard_calendarios.sql`.
3. Configure en Netlify `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`. La service role **solo** debe existir en Netlify Functions; jamás exponerla en variables VITE.
4. Publique el repositorio en Netlify: comando de build `npm run build`, carpeta `dist`, funciones `netlify/functions`.
5. Cree un usuario en Supabase Auth con correo interno derivado de cédula, formato `CEDULA@acceso.jps.invalid`; luego cree `public.profiles` con `id` de Auth y rol `admin`. **Este aprovisionamiento es manual en esta versión**. No use claves compartidas ni guarde contraseñas en archivos.
6. Cree usuarios de prueba, estudiantes y vínculos en base de datos. Compruebe RLS, importación y reportes con datos ficticios.
7. Antes de habilitar familias reales: realizar auditoría de seguridad, privacidad, pruebas de caja, calendario, recargos, permisos, notificaciones y respaldo.

## Reglas ya representadas en el código
- Plazo general: días 1–5 calendario; desde día 6 mora de COP $10.000 por cuota de pensión con saldo exigible.
- Calendario especial: día de inicio elegido por coordinador o administrador y cuatro días adicionales calendario. Puede cruzar el fin de mes. Para evitar fechas inexistentes, la UI permite días de inicio 1–28.
- El calendario se guarda por estudiante/año (todavía no se asigna una sola vez a la familia completa). La columna `charges.pension_month` debe estar poblada para que se aplique automáticamente a cada pensión; de lo contrario se usa `charges.due_date`.
- El comprobante es obligatorio en reportes. Medios: efectivo/transferencia.
- Solo el administrador aprueba y emite número de recibo.

## Pendientes CRÍTICOS antes de producción
- Crear usuarios y recuperar contraseña desde el panel; limitar coordinadores por sede.
- Separar `reporter_id` de `guardian_id` en los reportes del coordinador; el esquema heredado los mezcla.
- Registrar mes de pensión de forma obligatoria y generar automáticamente febrero–noviembre, con becas aplicadas al valor neto.
- Ajustar la pantalla de cobros para que muestre el vencimiento **efectivo** y la mora; comprobar calendario de cuotas ya creadas.
- Confirmar pagos en efectivo mediante conciliación de caja y transferencias mediante extractos; protección contra referencias duplicadas por medio.
- Comprobante visible al administrador con acceso temporal y seguro; rechazo con motivo; recibo PDF y envío automático de email (la generación/descarga parcial no equivale a entrega por correo).
- Solicitud de certificados de notas (desde 2016; año actual desde 1 de diciembre salvo traslado autorizado), constancias de matrícula y entrega física en 5–8 días hábiles tras aprobación.
- Acuerdos de matrícula, inventario completo de uniformes, reportes de ingresos por método y notificaciones al correo institucional.
- Políticas legales de retiro por no pago, gestión de documentos, tratamiento de datos de menores, copias de seguridad y pruebas integrales.

**No ingresar información real de menores ni aprobar cobros reales antes de resolver estos pendientes.**
