# JPS Gestión de Pagos — despliegue de PRUEBAS

Este paquete contiene **código fuente**, no `dist/`. No debe subirse directamente a Netlify Drop: debe compilarse en Netlify mediante repositorio Git o en un computador con Node.js y acceso a npm.

## Despliegue recomendado
1. Cree un repositorio GitHub **privado** e incorpore los archivos de esta carpeta (no suba contraseñas ni archivos `.env`).
2. En Netlify: Add new project > Import a Git repository > GitHub > seleccione el repositorio.
3. Build command: `npm run build`; publish directory: `dist`; functions directory: `netlify/functions` (también en `netlify.toml`).
4. Configure variables de entorno en Netlify: `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY` (clave pública/publishable). Para funciones del servidor: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` (SECRETA; jamás en variables `VITE_`).
5. Lance el deploy de prueba y revise logs. Verifique login, permisos, rutas y funcionamiento con datos ficticios.

## Estado de esta entrega
- Se verificó la estructura del ZIP y la configuración de Netlify.
- **No se pudo instalar dependencias ni ejecutar `npm run build` en este entorno**: el registro npm no fue accesible (EAI_AGAIN). Por tanto NO se garantiza una compilación exitosa.
- La base de datos del usuario no se ha probado contra este código. El SQL de este paquete NO debe reejecutarse sobre el proyecto existente sin revisión de migraciones.
- Hay pendientes críticos documentados en `DEPLOY_CHECKLIST.md`: validación de roles, recibos, conciliación, notificaciones, privacidad de menores y más.
- **Solo entorno de pruebas; no utilizar con familias reales ni pagos reales.**

## Alternativa sin GitHub
En computador con Node.js: `npm install`, `npm run build`; después subir **la carpeta `dist`** a Netlify Drop. Esta modalidad no publica las funciones de Netlify automáticamente, por lo que el flujo de aprobación/recibos no será funcional. Por ello se recomienda GitHub.
