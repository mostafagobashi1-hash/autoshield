-- Harx: شغّله مرة واحدة في Supabase → SQL Editor
create table if not exists profiles(
  id uuid primary key references auth.users on delete cascade,
  name text not null default '',
  role text not null default 'pending' check (role in ('owner','manager','reception','tech','viewer','pending')),
  created_at timestamptz not null default now());
create table if not exists docs(
  path text primary key, coll text not null, id text not null,
  data jsonb not null, updated_at timestamptz not null default now(), updated_by uuid default auth.uid());
alter table docs add column if not exists ver int not null default 1;
create index if not exists docs_coll_idx on docs(coll, updated_at desc);

create or replace function public.my_role() returns text language sql stable security definer set search_path=public as
$$ select role from profiles where id=auth.uid() $$;

-- أول حساب يتسجّل = المالك، وأي حساب بعده = pending (مفيش وصول لحد ما المالك يوافق)
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into profiles(id,name,role) values(new.id, coalesce(new.raw_user_meta_data->>'name',''),
    case when exists(select 1 from profiles) then 'pending' else 'owner' end);
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- حماية الفواتير: الدفعات بتتجمّع ومبتتمسحش لو اتنين سجّلوا في نفس اللحظة، وممنوع مجموع الدفعات يتخطى الإجمالي
create table if not exists counters(name text primary key, n bigint not null default 0);
insert into counters values('invoice',0) on conflict do nothing;
insert into counters values('customer',0) on conflict do nothing;
alter table counters enable row level security;  -- بدون policies: العدّاد مش ظاهر للعملاء

create or replace function public.docs_guard() returns trigger language plpgsql security definer set search_path=public as $$
declare o jsonb := '[]'::jsonb; n jsonb := coalesce(new.data->'pay','[]');
        extra jsonb; tot numeric; paid numeric; num bigint; r text; cc text; ph text;
begin
  new.updated_at := now();
  if tg_op = 'UPDATE' then new.ver := old.ver + 1; end if;
  if new.coll <> 'invoices' then return new; end if;
  -- رقم فاتورة تسلسلي بدون فجوات، بيتحط من السيرفر مرة واحدة ومبيتغيّرش بعد كده
  if tg_op = 'INSERT' then
    if not exists(select 1 from docs where path = new.path) then
      update counters c set n = c.n + 1 where c.name = 'invoice' returning c.n into num;
      new.data := jsonb_set(new.data, '{no}', to_jsonb('H-' || lpad(num::text, 5, '0')));
      -- كود ثابت لكل عميل (بنفس رقم الموبايل): بيتكرر لو العميل رجع، وبيتولّد جديد لو عميل جديد
      ph := right(regexp_replace(coalesce(new.data->>'phone',''), '\D', '', 'g'), 10);
      if length(ph) >= 8 then
        select d.data->>'cc' into cc from docs d
          where d.coll = 'invoices' and d.data ? 'cc'
            and right(regexp_replace(coalesce(d.data->>'phone',''), '\D', '', 'g'), 10) = ph
          order by d.updated_at limit 1;
      end if;
      if cc is null then
        update counters c set n = c.n + 1 where c.name = 'customer' returning c.n into num;
        cc := 'C-' || lpad(num::text, 4, '0');
      end if;
      new.data := jsonb_set(new.data, '{cc}', to_jsonb(cc));
    end if;
  elsif old.data ? 'no' then
    new.data := jsonb_set(new.data, '{no}', old.data->'no');
    if old.data ? 'cc' then new.data := jsonb_set(new.data, '{cc}', old.data->'cc'); end if;
  end if;
  if tg_op = 'UPDATE' then
    o := coalesce(old.data->'pay','[]');
    select coalesce(jsonb_agg(nn.e),'[]') into extra
    from (select t.e, count(*) c from jsonb_array_elements(n) as t(e) group by t.e) nn
    left join (select t.e, count(*) c from jsonb_array_elements(o) as t(e) group by t.e) oo on oo.e = nn.e
    cross join lateral generate_series(1, greatest(nn.c - coalesce(oo.c,0),0)::int) g;
    n := o || extra;
    new.data := jsonb_set(new.data, '{pay}', n);
    -- صلاحيات الأدوار بتتفرض هنا من القاعدة نفسها (مش بس من الواجهة)
    r := public.my_role();
    if r <> 'owner' then
      if new.data->>'st' = 'cancel' and old.data->>'st' is distinct from 'cancel' then raise exception 'إلغاء الفاتورة للمالك فقط'; end if;
      if r = 'reception' and (new.data - array['pay']) is distinct from (old.data - array['pay']) then raise exception 'غير مسموح لدورك: الاستقبال يسجّل دفعات فقط'; end if;
      if r = 'tech' and (new.data - array['st']) is distinct from (old.data - array['st']) then raise exception 'غير مسموح لدورك: الفني يغيّر الحالة فقط'; end if;
    end if;
  end if;
  select coalesce(sum((t.e->>'p')::numeric),0) - coalesce((new.data->>'disc')::numeric,0) into tot
    from jsonb_array_elements(coalesce(new.data->'items','[]')) as t(e);
  select coalesce(sum((t.e->>'a')::numeric),0) into paid from jsonb_array_elements(n) as t(e);
  if paid > tot + 0.005 then raise exception 'مجموع الدفعات يتجاوز إجمالي الفاتورة'; end if;
  return new;
end $$;
drop trigger if exists docs_bu on docs;
create trigger docs_bu before insert or update on docs for each row execute function public.docs_guard();

alter table profiles enable row level security;
alter table docs enable row level security;
drop policy if exists p_sel on profiles; drop policy if exists p_upd on profiles;
create policy p_sel on profiles for select using (id = auth.uid() or my_role() = 'owner');
create policy p_upd on profiles for update using (my_role() = 'owner') with check (my_role() = 'owner');
drop policy if exists d_sel on docs; drop policy if exists d_ins on docs; drop policy if exists d_upd on docs; drop policy if exists d_del on docs;
create policy d_sel on docs for select using (my_role() in ('owner','manager','reception','tech','viewer'));
create policy d_ins on docs for insert with check (my_role() in ('owner','manager','reception') and (coll <> 'settings' or my_role() = 'owner'));
create policy d_upd on docs for update using (my_role() in ('owner','manager','reception','tech') and (coll <> 'settings' or my_role() = 'owner'))
                                       with check (my_role() in ('owner','manager','reception','tech') and (coll <> 'settings' or my_role() = 'owner'));
create policy d_del on docs for delete using (my_role() = 'owner');

grant usage on schema public to authenticated;
grant select, insert, update, delete on public.docs to authenticated;
grant select, update on public.profiles to authenticated;

do $$ begin
  begin alter publication supabase_realtime add table docs; exception when others then null; end;
  begin alter publication supabase_realtime add table profiles; exception when others then null; end;
end $$;

-- ===== النسخ الاحتياطي داخل Supabase (نسخة يومية + يدوي + استرجاع) =====
create extension if not exists pg_cron;
create table if not exists backups(id bigserial primary key, taken_at timestamptz not null default now(),
  kind text not null check (kind in ('auto','manual','pre-restore')), doc_count int not null, data jsonb not null);
alter table backups enable row level security;
drop policy if exists b_sel on backups;
create policy b_sel on backups for select using (my_role() = 'owner');
revoke all on backups from anon, authenticated;
grant select (id, taken_at, kind, doc_count) on backups to authenticated;
create or replace function public.take_backup(p_kind text default 'manual') returns bigint language plpgsql security definer set search_path=public as $$
declare bid bigint;
begin
  if auth.uid() is not null and my_role() is distinct from 'owner' then raise exception 'النسخ الاحتياطي للمالك فقط'; end if;
  if p_kind not in ('auto','manual','pre-restore') then raise exception 'نوع نسخة غير صالح'; end if;
  insert into backups(kind, doc_count, data) select p_kind, count(*), coalesce(jsonb_agg(to_jsonb(d)), '[]'::jsonb) from docs d returning id into bid;
  delete from backups where kind = 'auto' and id not in (select id from backups where kind = 'auto' order by id desc limit 14);
  delete from backups where kind = 'manual' and id not in (select id from backups where kind = 'manual' order by id desc limit 20);
  delete from backups where kind = 'pre-restore' and id not in (select id from backups where kind = 'pre-restore' order by id desc limit 5);
  return bid;
end $$;
create or replace function public.restore_backup(p_id bigint) returns int language plpgsql security definer set search_path=public as $$
declare b backups%rowtype; cnt int;
begin
  if my_role() is distinct from 'owner' then raise exception 'الاسترجاع للمالك فقط'; end if;
  select * into b from backups where id = p_id;
  if not found then raise exception 'النسخة غير موجودة'; end if;
  perform take_backup('pre-restore');
  alter table docs disable trigger docs_bu;
  delete from docs where true;
  insert into docs select * from jsonb_populate_recordset(null::docs, b.data);
  get diagnostics cnt = row_count;
  alter table docs enable trigger docs_bu;
  return cnt;
end $$;
revoke all on function public.take_backup(text) from public, anon;
revoke all on function public.restore_backup(bigint) from public, anon;
grant execute on function public.take_backup(text) to authenticated;
grant execute on function public.restore_backup(bigint) to authenticated;
select cron.unschedule(jobid) from cron.job where jobname = 'harx-daily-backup';
select cron.schedule('harx-daily-backup', '0 1 * * *', $$select public.take_backup('auto')$$);

-- ===== إدارة الموظفين من القاعدة (بدون إيميلات تأكيد) =====
create or replace function public._mk_user(p_email text, p_password text, p_name text) returns uuid
language plpgsql security definer set search_path=public, extensions, auth as $$
declare uid uuid := gen_random_uuid(); em text := lower(trim(p_email));
begin
  insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,
    created_at,updated_at,confirmation_token,recovery_token,email_change_token_new,email_change,email_change_token_current,phone_change,phone_change_token,reauthentication_token)
  values('00000000-0000-0000-0000-000000000000',uid,'authenticated','authenticated',em,crypt(p_password,gen_salt('bf')),now(),
    '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('name',coalesce(p_name,'')),now(),now(),'','','','','','','','');
  insert into auth.identities(id,user_id,provider_id,identity_data,provider,last_sign_in_at,created_at,updated_at)
  values(gen_random_uuid(),uid,uid::text,jsonb_build_object('sub',uid::text,'email',em,'email_verified',true),'email',now(),now(),now());
  return uid;
end $$;
revoke all on function public._mk_user(text,text,text) from public, anon, authenticated;
create or replace function public.create_staff(p_email text, p_password text, p_name text, p_role text) returns uuid
language plpgsql security definer set search_path=public, extensions, auth as $$
declare uid uuid; em text := lower(trim(p_email));
begin
  if my_role() is distinct from 'owner' then raise exception 'إنشاء الحسابات للمالك فقط'; end if;
  if em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'الإيميل غير صالح'; end if;
  if length(coalesce(p_password,'')) < 8 then raise exception 'كلمة السر 8 أحرف على الأقل'; end if;
  if p_role not in ('manager','reception','tech','viewer') then raise exception 'دور غير صالح'; end if;
  if exists(select 1 from auth.users where lower(email) = em) then raise exception 'الإيميل ده مسجّل قبل كده'; end if;
  uid := public._mk_user(em, p_password, p_name);
  update profiles set role = p_role, name = coalesce(nullif(trim(p_name),''), name) where id = uid;
  return uid;
end $$;
create or replace function public.set_staff_password(p_user uuid, p_password text) returns void
language plpgsql security definer set search_path=public, extensions, auth as $$
begin
  if my_role() is distinct from 'owner' then raise exception 'تغيير كلمة السر للمالك فقط'; end if;
  if length(coalesce(p_password,'')) < 8 then raise exception 'كلمة السر 8 أحرف على الأقل'; end if;
  if not exists(select 1 from profiles where id = p_user and role <> 'owner') then raise exception 'مش مسموح لحساب المالك من هنا'; end if;
  update auth.users set encrypted_password = crypt(p_password, gen_salt('bf')), updated_at = now() where id = p_user;
end $$;
revoke all on function public.create_staff(text,text,text,text) from public, anon;
revoke all on function public.set_staff_password(uuid,text) from public, anon;
grant execute on function public.create_staff(text,text,text,text) to authenticated;
grant execute on function public.set_staff_password(uuid,text) to authenticated;

-- ===== لوحة الحسابات + قفل التسجيل العام =====
-- (دالة _mk_user أعلاه لازم تتحدّث بالنسخة دي: بتفتح علَم السماح قبل إنشاء الحساب)
create or replace function public._mk_user(p_email text, p_password text, p_name text) returns uuid
language plpgsql security definer set search_path=public, extensions, auth as $$
declare uid uuid := gen_random_uuid(); em text := lower(trim(p_email));
begin
  perform set_config('harx.allow_signup', '1', true);
  insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,
    created_at,updated_at,confirmation_token,recovery_token,email_change_token_new,email_change,email_change_token_current,phone_change,phone_change_token,reauthentication_token)
  values('00000000-0000-0000-0000-000000000000',uid,'authenticated','authenticated',em,crypt(p_password,gen_salt('bf')),now(),
    '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('name',coalesce(p_name,'')),now(),now(),'','','','','','','','');
  insert into auth.identities(id,user_id,provider_id,identity_data,provider,last_sign_in_at,created_at,updated_at)
  values(gen_random_uuid(),uid,uid::text,jsonb_build_object('sub',uid::text,'email',em,'email_verified',true),'email',now(),now(),now());
  return uid;
end $$;
revoke all on function public._mk_user(text,text,text) from public, anon, authenticated;
create or replace function public.block_public_signup() returns trigger language plpgsql as $$
begin
  if coalesce(current_setting('harx.allow_signup', true), '') <> '1' then
    raise exception 'التسجيل العام مقفول. الحسابات بيعملها مالك النظام فقط';
  end if;
  return new;
end $$;
drop trigger if exists harx_block_signup on auth.users;
create trigger harx_block_signup before insert on auth.users for each row execute function public.block_public_signup();
create or replace function public.list_staff() returns table(id uuid, name text, email text, role text, last_sign_in_at timestamptz, created_at timestamptz)
language plpgsql security definer set search_path=public, auth as $$
begin
  if my_role() is distinct from 'owner' then raise exception 'للمالك فقط'; end if;
  return query select p.id, p.name, u.email::text, p.role, u.last_sign_in_at, u.created_at
    from profiles p join auth.users u on u.id = p.id where p.role <> 'owner' order by u.created_at desc;
end $$;
create or replace function public.set_staff_role(p_user uuid, p_role text) returns void
language plpgsql security definer set search_path=public, auth as $$
begin
  if my_role() is distinct from 'owner' then raise exception 'للمالك فقط'; end if;
  if p_role not in ('manager','reception','tech','viewer','pending') then raise exception 'دور غير صالح'; end if;
  update profiles set role = p_role where id = p_user and role <> 'owner';
  if not found then raise exception 'الحساب غير موجود أو هو حساب المالك'; end if;
end $$;
create or replace function public.delete_staff(p_user uuid) returns void
language plpgsql security definer set search_path=public, auth as $$
begin
  if my_role() is distinct from 'owner' then raise exception 'للمالك فقط'; end if;
  if not exists(select 1 from profiles where id = p_user and role <> 'owner') then raise exception 'الحساب غير موجود أو هو حساب المالك'; end if;
  delete from auth.users where id = p_user;
end $$;
revoke all on function public.list_staff() from public, anon;
revoke all on function public.set_staff_role(uuid,text) from public, anon;
revoke all on function public.delete_staff(uuid) from public, anon;
grant execute on function public.list_staff() to authenticated;
grant execute on function public.set_staff_role(uuid,text) to authenticated;
grant execute on function public.delete_staff(uuid) to authenticated;
