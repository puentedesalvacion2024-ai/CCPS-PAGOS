import {createClient} from '@supabase/supabase-js';
import {PDFDocument,StandardFonts,rgb} from 'pdf-lib';
const err=(status,message)=>new Response(JSON.stringify({error:message}),{status,headers:{'Content-Type':'application/json'}});
export default async req=>{
 try{
 const token=(req.headers.get('authorization')||'').replace(/^Bearer\s+/i,'');if(!token)return err(401,'No autenticado');
 const url=process.env.SUPABASE_URL,anon=process.env.VITE_SUPABASE_ANON_KEY,secret=process.env.SUPABASE_SERVICE_ROLE_KEY;
 const auth=createClient(url,anon);const {data:{user}}=await auth.auth.getUser(token);if(!user)return err(401,'Sesión inválida');
 const admin=createClient(url,secret,{auth:{persistSession:false}});const reportId=new URL(req.url).searchParams.get('reportId');if(!/^[0-9a-f-]{36}$/i.test(reportId||''))return err(400,'Reporte inválido');
 const {data:r}=await admin.from('payment_reports').select('*').eq('id',reportId).single();if(!r||r.status!=='approved')return err(404,'Recibo no disponible');
 const {data:profile}=await admin.from('profiles').select('role').eq('id',user.id).single();if(profile?.role!=='admin'&&r.guardian_id!==user.id)return err(403,'No autorizado');
 const {data:student}=await admin.from('students').select('*').eq('id',r.student_id).single();const {data:charge}=await admin.from('charges').select('*').eq('id',r.charge_id).single();
 const pdf=await PDFDocument.create();const page=pdf.addPage([595,842]);const font=await pdf.embedFont(StandardFonts.Helvetica),bold=await pdf.embedFont(StandardFonts.HelveticaBold);const navy=rgb(.08,.17,.31);const lines=[['RECIBO OFICIAL DE PAGO',20,bold],['COLEGIO CRISTIANO PUENTE DE SALVACION',12,bold],[`JPS-2027-${String(r.receipt_number).padStart(6,'0')}`,14,bold],[`Estudiante: ${student?.name||''}`,12,font],[`Grado: ${student?.grade||''}  Sede: ${student?.campus||''}`,12,font],[`Concepto: ${charge?.description||''}`,12,font],[`Referencia bancaria: ${r.reference}`,12,font],[`Fecha del pago: ${r.paid_at}`,12,font],[`Fecha de aprobacion: ${new Date(r.reviewed_at).toLocaleDateString('es-CO')}`,12,font],[`Valor recibido: COP ${Number(r.reported_amount).toLocaleString('es-CO')}`,15,bold],['Estado: PAGO VERIFICADO POR ADMINISTRACION',11,bold],['Documento generado por JPS Gestion de Pagos',10,font]];
 let y=780;for(const [t,size,f] of lines){page.drawText(t.replace(/[^\x20-\x7E]/g,' '),{x:42,y,size,font:f,color:navy,maxWidth:520});y-=size+26;}
 const bytes=await pdf.save();return new Response(bytes,{headers:{'Content-Type':'application/pdf','Content-Disposition':`attachment; filename="JPS-Recibo-${r.receipt_number}.pdf"`,'Cache-Control':'no-store'}});
 }catch(e){return err(500,'Error al generar recibo');}
};
