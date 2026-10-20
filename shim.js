(()=>{
const C=window.HARX_CONFIG||{};let sb,me=null,prof=null,resolveReady;
const ready=new Promise(r=>resolveReady=r),cache={},L={};
const S='width:100%;padding:10px;margin:0 0 8px;border:1px solid #ccd;border-radius:8px;font:inherit;box-sizing:border-box';
const B='padding:10px 14px;border:0;border-radius:8px;background:#0f9d9a;color:#fff;font:inherit;cursor:pointer;margin-inline-end:6px';
function gate(h){let g=document.getElementById('hxg');if(!g){g=document.createElement('div');g.id='hxg';g.style.cssText='position:fixed;inset:0;z-index:99;background:#0d2a3a;align-items:center;justify-content:center;padding:16px;font-family:Tahoma,Arial,sans-serif;direction:rtl';document.body.appendChild(g)}
 g.style.display=h?'flex':'none';if(h)g.innerHTML='<div style="background:#fff;color:#12212c;border-radius:14px;padding:20px;width:min(380px,100%)">'+h+'</div>'}
const $=i=>document.getElementById(i);
function login(msg){gate(`<h3 style="margin:0 0 12px">Harx</h3><input id="hxe" type="email" placeholder="الإيميل" style="${S}"><input id="hxp" type="password" placeholder="كلمة السر (8 أحرف على الأقل)" style="${S}"><input id="hxn" placeholder="الاسم (للحساب الجديد فقط)" style="${S}"><div id="hxm" style="color:#c0392b;min-height:20px;font-size:13px;margin-bottom:6px">${msg||''}</div><button id="hxi" style="${B}">دخول</button><button id="hxs" style="${B};background:#e9eff2;color:#234">حساب جديد</button>`);
 const m=t=>$('hxm').textContent=t;
 $('hxi').onclick=async()=>{const{error}=await sb.auth.signInWithPassword({email:$('hxe').value.trim(),password:$('hxp').value});error?m('بيانات الدخول غير صحيحة'):start()};
 $('hxs').onclick=async()=>{const p=$('hxp').value;if(p.length<8)return m('كلمة السر 8 أحرف على الأقل');const{data,error}=await sb.auth.signUp({email:$('hxe').value.trim(),password:p,options:{data:{name:$('hxn').value.trim()}}});if(error)return m(error.message);data.session?start():m('تم إنشاء الحساب. أكّد الإيميل من الرسالة ثم ادخل.')}}
async function start(){const{data:{session}}=await sb.auth.getSession();if(!session)return login();me=session.user;
 const{data,error}=await sb.from('profiles').select('*').eq('id',me.id).single();if(error)return login('تعذّر تحميل الحساب: '+error.message);prof=data;
 if(prof.role==='pending'){gate('<h3>تم تسجيل حسابك ✅</h3><p>بانتظار موافقة المالك لتفعيله.</p><button id="hxr" style="'+B+'">تحديث</button><button id="hxo" style="'+B+';background:#e9eff2;color:#234">خروج</button>');$('hxr').onclick=start;$('hxo').onclick=out;return}
 gate('');bar();realtime();resolveReady()}
const out=async()=>{await sb.auth.signOut();location.reload()};
function bar(){if($('hxbar'))return;const d=document.createElement('div');d.id='hxbar';d.style.cssText='position:fixed;top:6px;left:6px;z-index:30;display:flex;gap:6px';
 d.innerHTML='<button id="hxx" style="'+B+';padding:6px 10px;font-size:12px">خروج</button>'+(prof.role==='owner'?'<button id="hxb" style="'+B+';padding:6px 10px;font-size:12px;background:#0d2a3a">نسخة احتياطية</button>':'');document.body.appendChild(d);$('hxx').onclick=out;if($('hxb'))$('hxb').onclick=backup}
async function backup(){const all=[];for(let f=0;;f+=1000){const{data,error}=await sb.from('docs').select('*').order('path').range(f,f+999);if(error)return alert(error.message);all.push(...data);if(data.length<1000)break}
 const{data:pr}=await sb.from('profiles').select('*');const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([JSON.stringify({at:new Date().toISOString(),docs:all,profiles:pr})],{type:'application/json'}));a.download='harx-backup-'+new Date().toISOString().slice(0,10)+'.json';a.click()}
const notify=k=>(L[k]||new Set()).forEach(f=>f());
const listen=(k,f)=>{(L[k]=L[k]||new Set()).add(f);f()};
function realtime(){sb.channel('hx').on('postgres_changes',{event:'*',schema:'public',table:'docs'},p=>{const r=p.new&&p.new.path?p.new:null,path=(r||p.old).path,i=path.indexOf('/'),k=path.slice(0,i),id=path.slice(i+1),m=cache[k];if(!m)return;p.eventType==='DELETE'?m.delete(id):m.set(id,r.data);notify(k)})
 .on('postgres_changes',{event:'*',schema:'public',table:'profiles'},()=>notify('staff')).subscribe()}
async function load(k){if(cache[k])return cache[k];const m=new Map();for(let f=0;;f+=1000){const{data,error}=await sb.from('docs').select('id,data').eq('coll',k).order('updated_at',{ascending:false}).range(f,f+999);if(error)throw error;data.forEach(r=>m.set(r.id,r.data));if(data.length<1000)break}return cache[k]=m}
function snap(k,o){const a=[...cache[k].entries()].map(([id,d])=>({id,data:()=>d}));if(o)a.sort((x,y)=>{const p=x.data()[o.f]??'',q=y.data()[o.f]??'';return(p>q?1:p<q?-1:0)*(o.d==='desc'?-1:1)});return{docs:a}}
async function staffSnap(){const{data}=await sb.from('profiles').select('id,name,role').in('role',['manager','reception','tech','viewer']);return{docs:(data||[]).map(r=>({id:r.id,data:()=>({role:r.role,name:r.name})}))}}
const Q=(k,o)=>({doc:id=>D(k+'/'+id),orderBy:(f,d)=>Q(k,{f,d}),limit:()=>Q(k,o),
 async get(){if(k==='staff')return staffSnap();await load(k);return snap(k,o)},
 onSnapshot(cb,err){let on=1;(k==='staff'?Promise.resolve():load(k)).then(()=>listen(k,async()=>on&&cb(k==='staff'?await staffSnap():snap(k,o)))).catch(e=>err&&err(e));return()=>on=0}});
const D=path=>{const i=path.indexOf('/'),k=path.slice(0,i),id=path.slice(i+1);return{
 async set(v){if(k==='staff'){const{error}=await sb.from('profiles').update({role:v.role}).eq('id',id);if(error)throw error;return notify('staff')}
  const{error}=await sb.from('docs').upsert({path,coll:k,id,data:v});if(error)throw error;if(cache[k]){cache[k].set(id,v);notify(k)}},
 async delete(){if(k==='staff'){const{error}=await sb.from('profiles').update({role:'pending'}).eq('id',id);if(error)throw error;return notify('staff')}
  const{error}=await sb.from('docs').delete().eq('path',path);if(error)throw error;if(cache[k]){cache[k].delete(id);notify(k)}},
 onSnapshot(cb,err){if(k==='staff'){listen('staff',async()=>{const{data}=await sb.from('profiles').select('role,name').eq('id',id).maybeSingle();cb({exists:!!data,data:()=>data})});return()=>{}}
  load(k).then(()=>listen(k,()=>{const m=cache[k];cb({exists:m.has(id),data:()=>m.get(id)})})).catch(e=>err&&err(e));return()=>{}}}};
const DB={collection:k=>Q(k),doc:D};
const U={id:async()=>me.id,isOwner:async()=>prof.role==='owner',canEdit:async()=>prof.role==='owner',me:async()=>({id:me.id,name:prof.name,isOwner:prof.role==='owner'}),
 async profiles(ids){const{data}=await sb.from('profiles').select('id,name').in('id',ids);return Object.fromEntries((data||[]).map(p=>[p.id,{name:p.name}]))},
 async search(q){const{data}=await sb.from('profiles').select('id,name').ilike('name','%'+String(q).replace(/[%_]/g,'')+'%').neq('role','owner').limit(10);return data||[]}};
const A={upload:f=>new Promise((ok,no)=>{if(f.size>400000)return no(new Error('الصورة أكبر من 400KB'));const r=new FileReader();r.onload=()=>ok({url:r.result});r.onerror=no;r.readAsDataURL(f)})};
window.claude={use:async n=>{await ready;return({db:DB,user:U,assets:A})[n]||null}};
document.addEventListener('DOMContentLoaded',()=>{if(!C.url||/PASTE/.test(C.url+C.key)||!window.supabase)return gate('<h3>الإعداد ناقص</h3><p>افتح index.html وحط Project URL و anon key في أول الملف (راجع README).</p>');sb=window.supabase.createClient(C.url,C.key);start()});

document.addEventListener('click',async e=>{if(e.target.id!=='hxadd')return;const v=i=>document.getElementById(i).value.trim(),m=document.getElementById('hxam'),say=t=>m.textContent=t;
 const name=v('hxan'),email=v('hxae'),pw=document.getElementById('hxap').value,role=v('hxar');
 if(!name||!email||pw.length<8)return say('اكتب الاسم والإيميل وكلمة سر 8 أحرف على الأقل');
 if(!prof||prof.role!=='owner')return say('الإنشاء للمالك فقط');say('جاري الإنشاء...');
 try{const t=window.supabase.createClient(C.url,C.key,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
  const{data,error}=await t.auth.signUp({email,password:pw,options:{data:{name}}});if(error)return say(error.message);
  const u=data&&data.user;if(!u)return say('تعذّر إنشاء الحساب');if(u.identities&&!u.identities.length)return say('الإيميل ده مسجّل قبل كده. ابحث عنه بالاسم تحت وفعّله.');
  await new Promise(r=>setTimeout(r,700));
  const{data:ok,error:e2}=await sb.from('profiles').update({role}).eq('id',u.id).select();
  if(e2||!ok||!ok.length)return say('اتعمل الحساب لكن تفعيل الدور فشل. ابحث عنه بالاسم تحت وفعّله.');
  notify('staff');['hxan','hxae','hxap'].forEach(i=>document.getElementById(i).value='');
  say('✅ تم إنشاء حساب '+name+'. سلّمه الإيميل وكلمة السر.'+(data.session?'':' ⚠️ لازم يأكّد الإيميل من رسالة Supabase، أو اقفل Confirm email من إعدادات Authentication.'))}
 catch(x){say('خطأ: '+(x.message||x))}});
})();
