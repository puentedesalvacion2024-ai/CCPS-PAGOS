# CCPS PAGOS — registro de estudiantes y acudientes

## Qué se agregó

- Pestaña **Estudiantes y acudientes** visible exclusivamente al administrador.
- Formulario manual para registrar estudiantes y acudientes.
- Plantilla Excel `.xlsx`, vista previa, validación de hasta 100 filas e importación.
- Función de Netlify `netlify/functions/manage-students.mjs` que comprueba sesión y rol administrativo en Supabase, crea/invita acudientes y vincula estudiantes.
- Un acudiente existente puede quedar vinculado a varios hermanos; un documento estudiantil existente no se vuelve a crear.

## Cómo publicar

1. Descomprima el ZIP y suba el contenido de `jps-gestion-pagos` a **la misma ruta de GitHub que ya usa Netlify**, sin crear una carpeta adicional.
2. Netlify deberá ejecutar `npm install` y `npm run build`. Se agregó la dependencia `exceljs` para la plantilla y lectura de Excel.
3. En **Netlify → Project configuration → Environment variables**, compruebe que existen:
   - `VITE_SUPABASE_URL`: URL de su proyecto Supabase.
   - `VITE_SUPABASE_ANON_KEY`: clave **publishable** de Supabase.
   - `SUPABASE_URL`: misma URL del proyecto (para funciones de servidor).
   - `SUPABASE_SERVICE_ROLE_KEY`: clave **secret** de Supabase; **nunca** la agregue con prefijo `VITE_`, ni al código ni a GitHub.
4. Si revocó la clave secreta usada antes, configure en Netlify una clave de servidor **activa** y distinta de la clave temporal de recuperación. No revocar una clave utilizada por funciones de producción.
5. Realice un nuevo deploy y compruebe que la función `manage-students` se publicó.

## Pruebas obligatorias antes de usar datos reales

- Probar con un estudiante y acudiente **ficticios** y un correo de prueba que controle.
- Verificar que llega la invitación y que el acudiente puede establecer contraseña.
- Verificar que un usuario acudiente no puede llamar a `manage-students` (403).
- Verificar que la segunda carga del mismo documento no duplica al estudiante.
- Verificar que hermanos comparten un mismo acudiente.
- Revisar las políticas de acceso RLS, límites de correo de Supabase, auditoría y recuperación ante fallos parciales.

## Limitaciones de esta versión

- **No genera automáticamente cobros** de matrícula/pensión: estos se gestionan con los módulos financieros existentes.
- No incluye todavía edición de datos ni teléfono, porque el esquema `profiles` actual no tiene columna de teléfono.
- La importación procesa filas secuencialmente; si falla a mitad de camino, los registros anteriores permanecen guardados y se informa dónde se detuvo.
- Las invitaciones requieren configuración de correo de Supabase; su servicio gratuito puede limitar la cantidad de mensajes. No realice importaciones masivas hasta configurar un proveedor SMTP confiable.
- El registro de un acudiente puede dejar una invitación o un perfil parcial si falla la base de datos. Revise Supabase antes de reintentar.
- No se ha realizado una auditoría de seguridad ni pruebas de integración contra la base de datos de producción. **No usar todavía con datos reales.**
