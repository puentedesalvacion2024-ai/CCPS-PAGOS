# JPS Gestión de Pagos — versión inicial (MVP técnico)

Proyecto independiente, sin Lovable. Frontend React/Vite desplegable en Netlify, base de datos externa Supabase/PostgreSQL y funciones protegidas de Netlify.

## Incluye actualmente
- Escudo institucional proporcionado.
- Inicio de sesión con cédula y contraseña para cuentas creadas previamente por administración.
- Perfil familiar y sumatoria de obligaciones registradas.
- Conceptos: matrícula, pensiones, uniformes, derechos de grado, informes y otros.
- Registro de comprobantes privados JPG/PNG/PDF (máximo 5 MB).
- Validación del monto y recargo de $10.000 para pensiones pagadas después del vencimiento.
- Aprobación administrativa transaccional y numeración única de recibos.
- Descarga de PDF por usuarios autorizados después de la aprobación.
- Estructuras SQL para acuerdos de matrícula y seis prendas de uniformes.

## Pendiente antes de uso real
1. Pantallas administrativas para crear estudiantes, acudientes, tarifas, cargos, acuerdos, cuotas y pedidos de uniformes.
2. Visor privado de comprobantes para que administración pueda revisarlos; hoy solo se almacena el archivo y se visualizan sus datos. **No aprobar pagos sin consultar el banco.**
3. Envío automático de PDF por correo (servicio transaccional, dominio verificado, registro de entregas y reintentos). Hoy la descarga desde el portal sí está implementada.
4. Pantalla de rechazo, ajustes, anulaciones y abonos con controles de auditoría.
5. Reglas de pagos familiares con una sola consignación y asignación entre varios cargos; actualmente un reporte se asocia a una obligación.
6. Implementar recuperación segura de contraseñas, limitación de intentos, MFA para administradores, verificación de vinculación familiar, políticas de privacidad, pruebas de penetración y copias de seguridad.
7. Revisar reglas de recargo con la institución, especialmente pagos anticipados, festivos, fechas de pago vs. reporte, pagos parciales y obligaciones atrasadas. La fecha declarada por el usuario NO sustituye la fecha bancaria.
8. Crear mecanismo de provisión segura de cuentas (Supabase Admin API del lado servidor), usando correos internos `${cedula}@acceso.jps.invalid`; no habilitar autorregistro público ni depender de recuperación por esos correos ficticios.
9. Crear cargos mensuales febrero-noviembre por estudiante, con vencimiento el día 5. No generar cargos de enero o diciembre.
10. Añadir logo al PDF, validación pública segura de recibo, correo, y formato final institucional.

## Instalación
1. Crear proyecto en Supabase y ejecutar `supabase/schema.sql` desde SQL Editor.
2. Crear cuentas mediante Supabase Auth Admin API (solo servidor). Para cada cuenta, registrar `profiles.id` con el mismo UUID de `auth.users.id`. La cédula usada para el login corresponde al correo interno `${cedula}@acceso.jps.invalid` (ejemplo: `12345678@acceso.jps.invalid`). No crear perfiles con privilegio admin desde cliente.
3. Insertar estudiantes, vínculos `guardian_students` y cargos `charges` por SQL o un importador administrativo futuro.
4. Copiar `.env.example` a `.env` y completar `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY`.
5. En Netlify configurar además `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` y `VITE_SUPABASE_ANON_KEY`. **Nunca usar la service role key en variables `VITE_` ni publicarla.**
6. `npm install` y `npm run dev` para interfaz local; para probar funciones, `npx netlify dev` con Netlify CLI.
7. Conectar repositorio Git a Netlify; `netlify.toml` define build y funciones.

## Nota de seguridad
La base de datos usa RLS para las lecturas de acudientes. El backend usa `service_role` exclusivamente después de verificar la sesión y el rol del usuario. El procedimiento SQL de aprobación revalida el monto, el recargo y el estado de la obligación dentro de una transacción. El operador debe confirmar en el banco el dinero recibido; ni OCR ni IA verifican el movimiento financiero.

Este repositorio es una base de desarrollo, no una solución lista para producción ni una certificación de cumplimiento legal o contable.

## Becas y recargo (migración 002)
Ejecutar `supabase/002_becas.sql` después del esquema inicial. Solo el administrador puede autorizar becas desde un backend protegido (aún pendiente de construir). Las becas cubren matrícula, pensión o ambas, con porcentajes separados y vigencia anual. `charge_net_amount(id, fecha_real_pago)` calcula el valor exigible después del descuento y añade $10.000 de mora solo si existe pensión neta positiva y el pago fue posterior al vencimiento. La aprobación valida el valor neto nuevamente en el servidor. Para becas del 100%, crear un proceso administrativo de cierre de obligaciones sin pago (pendiente); no generar recibo de consignación ficticia. No permitir cambiar becas con efectos retroactivos sobre pagos aprobados. Antes de producción falta completar el frontend de becas, validación al enviar reportes, manejo de pagos parciales, controles de acceso y pruebas de concurrencia.

## Actualización: panel administrativo de estudiantes y becas
Ejecute `supabase/003_panel_administrativo.sql` después de las migraciones anteriores.
El panel Administración ahora permite seleccionar estudiante, asignar porcentajes de beca separados para matrícula y pensión y crear obligaciones manuales. Los cambios se realizan con funciones SQL que comprueban el rol de administrador y registran auditoría. Las becas se registran por año académico y reemplazan la beca activa anterior del mismo estudiante/año. **No** se han implementado todavía la edición de los datos personales de estudiantes, importación Excel, generación automática de las 10 pensiones, acuerdos de matrícula, descuentos retroactivos ni envío de correos. No usar en producción sin pruebas de permisos, seguridad, integridad de pagos y conciliación bancaria.

## Panel financiero inicial (migración 004)
1. Ejecutar `supabase/004_dashboard_financiero.sql` después de las migraciones anteriores.
2. Iniciar sesión con un perfil cuyo `role` sea `admin`; abrir **Inicio financiero**.
3. El filtro inicial es **2026 / Todas las sedes**. Permite seleccionar otra sede o año, actualizar datos y exportar PDF o CSV compatible con Excel.
4. Las cifras vienen de PostgreSQL: ingresos por `payment_reports.status='approved'` y `paid_at`; obligaciones vencidas por `charges.status='pending'` y `due_date`; padres por `guardian_students`.
5. No se inventan cifras. Sin datos reales cargados, el tablero mostrará cero.

**Limitaciones a resolver antes de producción:** el esquema inicial registra un solo pago por obligación y no soporta abonos parciales ni asignaciones de un pago a varias obligaciones; tampoco conserva un desglose de descuentos/becas por cargo, ni anulaciones contables. El tablero refleja el estado actual de la base y puede requerir conciliación histórica si se modifican pagos. La mora se calcula para cada obligación pendiente de pensión de importe positivo, no para cargos completamente becados; las becas deben aplicarse al valor exigible de `charges` antes de generar el cobro. Un estudiante con varios acudientes vinculados puede aparecer en la lista de cada uno; no sumar filas de acudientes para reconstruir la cartera total. El CSV se abre con Excel y no es un archivo `.xlsx`. El PDF exportado usa transliteración básica de caracteres para compatibilidad con fuentes estándar.

## Módulo 005 — Retiros y cancelación de matrícula
Ejecute `supabase/005_retiros_matricula.sql` después de las migraciones anteriores. El panel de administración incluye **Retiros y matrícula**, con motivo `retiro`, fecha inicial `2026-11-07` y observaciones `Sin observaciones`. La solicitud pasa a revisión y únicamente el administrador puede confirmarla. La cancelación por no pago exige soporte y revisión jurídica documentados, y **no** se automatiza. La base conserva cartera, recibos y auditoría. Los cargos posteriores a la fecha efectiva requieren revisión manual y no se eliminan de forma automática. No se ha comprobado conformidad legal ni se ha desplegado a producción.

## Módulo de prematrículas 2027 (migración 008)

Ejecutar `supabase/008_prematriculas_2027.sql` después de `007_dashboard_calendarios.sql`.
Se inicializa el cobro de prematrícula 2027 **activo** por **COP $150.000**.
La configuración y asignación individual de cobros se hace exclusivamente desde el perfil administrador en la pestaña Prematrículas. Coordinación puede consultar el listado y reportar pagos en la pestaña general Reportar pago. El acudiente ve la obligación asignada en su portal y reporta con soporte obligatorio. La aprobación sigue siendo exclusiva del administrador.
La activación no genera cargos automáticamente a todos los estudiantes; el administrador los asigna individualmente. Los ingresos aprobados y saldos vencidos se integran a los reportes financieros existentes. Desactivar no cancela cobros ya creados.

**Advertencia:** sigue siendo un proyecto de desarrollo. No desplegar con información real sin revisar RLS, almacenamiento seguro de soportes, identidad de reportantes y pruebas de extremo a extremo.
