import {createClient} from '@supabase/supabase-js';
const reply=(status,data)=>new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
const clean=x=>String(x??'').trim();
export default async function(req){
 if(req.method!=='POST')return reply(405,{error:'Método no permitido'});
 try{
  const token=(req.headers.get('authorization')||'').replace(/^Bearer\s+/i,'');
  const url=process.env.SUPABASE_URL||process.env.VITE_SUPABASE_URL;
  const anon=process.env.VITE_SUPABASE_ANON_KEY;
  const secret=process.env.SUPABASE_SERVICE_ROLE_KEY;
  if(!url||!anon||!secret)return reply(503,{error:'Configure SUPABASE_URL, VITE_SUPABASE_ANON_KEY y SUPABASE_SERVICE_ROLE_KEY en Netlify (solo servidor).'});
  if(!token)return reply(401,{error:'Inicie sesión'});
  const authClient=createClient(url,anon,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:{user},error:authError}=await authClient.auth.getUser(token);
  if(authError||!user)return reply(401,{error:'Sesión inválida'});
  const db=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:actor,error:roleError}=await db.from('profiles').select('role').eq('id',user.id).single();
  if(roleError||actor?.role!=='admin')return reply(403,{error:'Solo administración puede registrar estudiantes'});
  const body=await req.json();
  const studentName=clean(body.studentName),document=clean(body.studentDocument),grade=clean(body.grade),campus=clean(body.campus);
  const guardianName=clean(body.guardianName),guardianDocument=clean(body.guardianDocument),guardianEmail=clean(body.guardianEmail).toLowerCase();
  const year=Number(body.academicYear||2027);
  if(studentName.length<3||studentName.length>160||guardianName.length<3||guardianName.length>160)return reply(400,{error:'Nombres requeridos (3 a 160 caracteres)'});
  if(!/^\d{5,15}$/.test(document)||!/^\d{5,15}$/.test(guardianDocument))return reply(400,{error:'Documentos deben contener entre 5 y 15 dígitos'});
  if(!/^\S+@\S+\.\S+$/.test(guardianEmail)||guardianEmail.length>254)return reply(400,{error:'Correo real del acudiente obligatorio'});
  if(!['Prejardín','Jardín','Transición','Primero','Segundo','Tercero','Cuarto','Quinto','Sexto','Séptimo','Octavo','Noveno','Décimo','Undécimo'].includes(grade))return reply(400,{error:'Grado inválido'});
  if(!['Porfía','Campestre','Acacías','Restrepo'].includes(campus)||!Number.isInteger(year)||year<2026||year>2100)return reply(400,{error:'Sede o año inválidos'});
  // Nunca se crea un usuario con contraseña compartida. Invitación al correo real del acudiente.
  let {data:guardian,error:ge}=await db.from('profiles').select('id,cedula,email,role').eq('cedula',guardianDocument).maybeSingle();
  if(ge)throw ge;
  let invited=false;
  if(guardian){
   if(guardian.role!=='guardian')return reply(409,{error:'El documento del acudiente pertenece a una cuenta administrativa'});
   if(guardian.email?.toLowerCase()!==guardianEmail)return reply(409,{error:'El correo no coincide con el acudiente existente. Revíselo antes de continuar.'});
  }else{
   const {data:emailConflict}=await db.from('profiles').select('id').eq('email',guardianEmail).maybeSingle();
   if(emailConflict)return reply(409,{error:'El correo ya está asociado a otra cédula'});
   const {data:invite,error:ie}=await db.auth.admin.inviteUserByEmail(guardianEmail,{data:{full_name:guardianName}});
   if(ie)return reply(400,{error:'No se pudo invitar al acudiente: '+ie.message});
   invited=true;
   const {error:pe}=await db.from('profiles').insert({id:invite.user.id,cedula:guardianDocument,full_name:guardianName,email:guardianEmail,role:'guardian'});
   if(pe)return reply(409,{error:'La invitación fue creada pero no se pudo crear el perfil: '+pe.message+'. Revise Supabase antes de reintentar.'});
   guardian={id:invite.user.id};
  }
  const {data:existing,error:se}=await db.from('students').select('id,name,document').eq('document',document).maybeSingle();
  if(se)throw se;
  let student=existing;
  if(existing){
   if(existing.name.toLocaleLowerCase('es')!==studentName.toLocaleLowerCase('es'))return reply(409,{error:'Ya existe ese documento con otro nombre; corrija el registro manualmente'});
   // No modificar año, grado o sede silenciosamente al importar duplicados.
  }else{
   const {data:created,error:ce}=await db.from('students').insert({document,name:studentName,grade,campus,academic_year:year}).select('id').single();
   if(ce)throw ce;
   student=created;
  }
  const {error:le}=await db.from('guardian_students').upsert({guardian_id:guardian.id,student_id:student.id},{onConflict:'guardian_id,student_id'});
  if(le)throw le;
  await db.from('audit_log').insert({actor_id:user.id,action:'admin_student_guardian_registration',entity_id:student.id,details:{document,guardianDocument,invited}});
  return reply(200,{message:existing?'Estudiante existente vinculado al acudiente.':'Estudiante registrado y vinculado.',invited});
 }catch(e){return reply(500,{error:'No se completó el registro. '+(e.message||'Revise los datos y el servidor.')});}
}
