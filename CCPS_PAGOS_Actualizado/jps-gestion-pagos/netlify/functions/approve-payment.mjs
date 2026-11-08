import {createClient} from '@supabase/supabase-js';
const json=(status,obj)=>new Response(JSON.stringify(obj),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
export default async (req)=>{
 if(req.method!=='POST')return json(405,{error:'Método no permitido'});
 try{
  const token=(req.headers.get('authorization')||'').replace(/^Bearer\s+/i,'');if(!token)return json(401,{error:'No autenticado'});
  const url=process.env.SUPABASE_URL,anon=process.env.VITE_SUPABASE_ANON_KEY,secret=process.env.SUPABASE_SERVICE_ROLE_KEY;
  if(!url||!anon||!secret)return json(500,{error:'Servidor no configurado'});
  const userClient=createClient(url,anon,{global:{headers:{Authorization:`Bearer ${token}`}}});
  const {data:{user},error:ue}=await userClient.auth.getUser(token);if(ue||!user)return json(401,{error:'Sesión inválida'});
  const admin=createClient(url,secret,{auth:{persistSession:false}});
  const {data:p}=await admin.from('profiles').select('role').eq('id',user.id).single();if(p?.role!=='admin')return json(403,{error:'Solo administración puede aprobar'});
  const {reportId}=await req.json();if(!/^[0-9a-f-]{36}$/i.test(reportId||''))return json(400,{error:'Identificador inválido'});
  // Atomicidad y revalidación bancaria de monto/fecha se realizan dentro de la función SQL.
  const {data,error}=await admin.rpc('approve_payment_atomic',{p_report_id:reportId,p_admin_id:user.id});
  if(error)return json(400,{error:error.message});
  return json(200,{message:'Pago aprobado. Recibo PDF disponible para el acudiente.',receiptNumber:data});
 }catch(e){return json(500,{error:'No se pudo aprobar el pago'});}
};
