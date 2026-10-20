-- Harx: شغّله مرة واحدة في Supabase → SQL Editor
create table if not exists profiles(
  id uuid primary key references auth.users on delete cascade,
  name text not null default '',
  role text not null default 'pending' check (role in ('owner','manager','reception','tech','viewer','pending')),
  created_at timestamptz not null default now());
create table if not exists docs(
  path text primary key, coll text not null, id text not null,
  data jsonb not null, updated_at timestamptz not null default now(), updated_by uuid default auth.uid());
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
create or replace function public.docs_guard() returns trigger language plpgsql as $$
declare o jsonb := coalesce(old.data->'pay','[]'); n jsonb := coalesce(new.data->'pay','[]');
        extra jsonb; tot numeric; paid numeric;
begin
  new.updated_at := now();
  if new.coll <> 'invoices' then return new; end if;
  if tg_op = 'UPDATE' then
    select coalesce(jsonb_agg(nn.e),'[]') into extra
    from (select t.e, count(*) c from jsonb_array_elements(n) as t(e) group by t.e) nn
    left join (select t.e, count(*) c from jsonb_array_elements(o) as t(e) group by t.e) oo on oo.e = nn.e
    cross join lateral generate_series(1, greatest(nn.c - coalesce(oo.c,0),0)::int) g;
    n := o || extra;
    new.data := jsonb_set(new.data, '{pay}', n);
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
create policy d_ins on docs for insert with check (my_role() in ('owner','manager','reception','tech') and (coll <> 'settings' or my_role() = 'owner'));
create policy d_upd on docs for update using (my_role() in ('owner','manager','reception','tech') and (coll <> 'settings' or my_role() = 'owner'))
                                       with check (my_role() in ('owner','manager','reception','tech') and (coll <> 'settings' or my_role() = 'owner'));
create policy d_del on docs for delete using (my_role() = 'owner');

alter publication supabase_realtime add table docs, profiles;
