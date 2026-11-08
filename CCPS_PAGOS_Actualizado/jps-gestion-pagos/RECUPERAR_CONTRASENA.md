# Recuperación de contraseña JPS

Se añadió un formulario de recuperación mediante Supabase Auth, una pantalla `/restablecer-contrasena` y la posibilidad de ingresar con correo electrónico (administrador) o cédula (acudientes).

## Actualización
1. Descomprima el ZIP y cargue **el contenido de `jps-gestion-pagos`** en la carpeta homónima del repositorio GitHub `JPS-PAGOS`, reemplazando `src/main.jsx` y agregando este documento. No suba un segundo directorio anidado.
2. Netlify debe tener base directory `jps-gestion-pagos`, build command `npm run build`, publish directory `dist` (relativo a la base), y las variables `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY`.
3. En Supabase > Authentication > URL Configuration, configure Site URL con la URL real de Netlify y agregue a Redirect URLs `https://SU-SITIO.netlify.app/restablecer-contrasena` (puede conservar el patrón `https://SU-SITIO.netlify.app/**`).
4. Espere la publicación de Netlify y solicite **un nuevo enlace** desde «¿Olvidó su contraseña?» usando el correo del administrador.
5. Abra el enlace del correo más reciente, escriba y confirme una contraseña nueva. Luego inicie sesión con el correo del administrador.

**No comparta contraseñas, enlaces de recuperación ni claves privadas.**

## Nota
Esta entrega corrige la interfaz y el flujo de recuperación, pero no constituye una prueba de funcionamiento contra su proyecto remoto Supabase/Netlify. Verifique el flujo completo tras desplegarlo. No modifica la base de datos.
