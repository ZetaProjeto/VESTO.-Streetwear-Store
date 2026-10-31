-- EXECUTE NO SQL EDITOR DO SUPABASE, EM PROJETO NOVO.
create extension if not exists pgcrypto;
create table public.admins(user_id uuid primary key references auth.users(id) on delete cascade);
create table public.products(id uuid primary key default gen_random_uuid(),name text not null check(length(name) between 1 and 120),category text not null check(length(category) between 1 and 60),description text not null default '',image_url text,price numeric(12,2) not null check(price>0),compare_price numeric(12,2) check(compare_price>=0),active boolean not null default true,created_at timestamptz not null default now());
create table public.product_variants(id uuid primary key default gen_random_uuid(),product_id uuid not null references public.products(id) on delete cascade,color text not null,size text not null,stock integer not null default 0 check(stock>=0),unique(product_id,color,size));
create table public.orders(id uuid primary key default gen_random_uuid(),order_number bigint generated always as identity unique,customer_name text not null,phone text not null,email text,delivery text not null check(delivery in ('retirada','entrega')),zip text,address text,notes text,subtotal numeric(12,2) not null,total numeric(12,2) not null,status text not null default 'pendente' check(status in ('pendente','confirmado','preparando','enviado','concluido','cancelado')),created_at timestamptz not null default now());
create table public.order_items(id uuid primary key default gen_random_uuid(),order_id uuid not null references public.orders(id) on delete cascade,variant_id uuid references public.product_variants(id) on delete set null,product_name text not null,color text not null,size text not null,unit_price numeric(12,2) not null,quantity integer not null check(quantity>0),line_total numeric(12,2) not null);
create index on public.product_variants(product_id);create index on public.orders(created_at desc);create index on public.order_items(order_id);
alter table public.admins enable row level security;alter table public.products enable row level security;alter table public.product_variants enable row level security;alter table public.orders enable row level security;alter table public.order_items enable row level security;
create function public.is_admin() returns boolean language sql stable security definer set search_path='' as $$ select exists(select 1 from public.admins where user_id=auth.uid()) $$;
revoke all on function public.is_admin() from public;grant execute on function public.is_admin() to authenticated;
create policy "Admin self" on public.admins for select to authenticated using(user_id=auth.uid());
create policy "Catalog public" on public.products for select to anon,authenticated using(active or public.is_admin());
create policy "Catalog admin insert" on public.products for insert to authenticated with check(public.is_admin());
create policy "Catalog admin update" on public.products for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "Variants public" on public.product_variants for select to anon,authenticated using(exists(select 1 from public.products p where p.id=product_id and (p.active or public.is_admin())));
create policy "Variants admin insert" on public.product_variants for insert to authenticated with check(public.is_admin());
create policy "Variants admin update" on public.product_variants for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "Variants admin delete" on public.product_variants for delete to authenticated using(public.is_admin());
create policy "Orders admin read" on public.orders for select to authenticated using(public.is_admin());
create policy "Orders admin update" on public.orders for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "Items admin read" on public.order_items for select to authenticated using(public.is_admin());
-- Criação do pedido é feita somente via função transacional, que calcula valores no servidor e bloqueia estoque.
create or replace function public.place_order(customer jsonb,items jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare rec record; line jsonb; ordered uuid[] := '{}'; oid uuid; total_price numeric(12,2):=0; nitems integer:=0; order_no bigint; delivery_mode text; name_val text; phone_val text;
begin
 if jsonb_typeof(items)<>'array' or jsonb_array_length(items) not between 1 and 40 then raise exception 'Carrinho inválido'; end if;
 if jsonb_typeof(customer)<>'object' then raise exception 'Dados do cliente inválidos'; end if;
 name_val:=trim(coalesce(customer->>'name',''));phone_val:=trim(coalesce(customer->>'phone',''));delivery_mode:=customer->>'delivery';
 if length(name_val) not between 2 and 120 or length(phone_val) not between 10 and 22 then raise exception 'Nome ou telefone inválido'; end if;
 if delivery_mode not in ('entrega','retirada') then raise exception 'Entrega inválida'; end if;
 if delivery_mode='entrega' and (length(trim(coalesce(customer->>'address','')))<8 or length(trim(coalesce(customer->>'zip','')))<8) then raise exception 'Preencha endereço e CEP'; end if;
 if length(coalesce(customer->>'email',''))>160 or length(coalesce(customer->>'notes',''))>500 or length(coalesce(customer->>'address',''))>400 then raise exception 'Texto muito longo';end if;
 -- Ordenação de IDs garante ordem estável de bloqueio concorrente.
 if exists(select 1 from jsonb_array_elements(items) x where (x->>'variant_id') is null or (x->>'quantity') is null or (x->>'quantity') !~ '^[0-9]{1,3}$' or (x->>'quantity')::int not between 1 and 99) then raise exception 'Itens inválidos';end if;
 if (select count(distinct x->>'variant_id') from jsonb_array_elements(items) x)<>jsonb_array_length(items) then raise exception 'Itens duplicados';end if;
 if exists(select 1 from jsonb_array_elements(items) x where (x->>'variant_id') !~ '^[0-9a-fA-F-]{36}$') then raise exception 'Variação inválida';end if;
 for rec in select v.id,v.stock,p.name,p.price,v.color,v.size,(x->>'quantity')::int as qty from jsonb_array_elements(items) x join public.product_variants v on v.id=(x->>'variant_id')::uuid join public.products p on p.id=v.product_id where p.active order by v.id for update of v loop
  if rec.qty>rec.stock then raise exception 'Estoque insuficiente para %',rec.name;end if;
  ordered:=array_append(ordered,rec.id);total_price:=total_price+rec.price*rec.qty;nitems:=nitems+1;
 end loop;
 if nitems<>jsonb_array_length(items) then raise exception 'Produto indisponível';end if;
 insert into public.orders(customer_name,phone,email,delivery,zip,address,notes,subtotal,total) values(name_val,phone_val,nullif(trim(coalesce(customer->>'email','')),''),delivery_mode,left(coalesce(customer->>'zip',''),9),left(coalesce(customer->>'address',''),400),left(coalesce(customer->>'notes',''),500),total_price,total_price) returning id,order_number into oid,order_no;
 for rec in select v.id,v.stock,p.name,p.price,v.color,v.size,(x->>'quantity')::int as qty from jsonb_array_elements(items) x join public.product_variants v on v.id=(x->>'variant_id')::uuid join public.products p on p.id=v.product_id order by v.id loop
  update public.product_variants set stock=stock-rec.qty where id=rec.id;
  insert into public.order_items(order_id,variant_id,product_name,color,size,unit_price,quantity,line_total) values(oid,rec.id,rec.name,rec.color,rec.size,rec.price,rec.qty,rec.price*rec.qty);
 end loop;
 return jsonb_build_object('order_number',order_no,'total',total_price);
end $$;
revoke all on function public.place_order(jsonb,jsonb) from public;grant execute on function public.place_order(jsonb,jsonb) to anon,authenticated;
-- Salva produto e substitui variações no servidor; apenas admins. Mantém o ID de variantes existentes com mesma cor/tamanho.
create or replace function public.admin_save_product(product_data jsonb,variant_data jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare pid uuid; v jsonb; color_val text; size_val text; qty integer;
begin
 if not public.is_admin() then raise exception 'Sem permissão';end if;
 if jsonb_typeof(variant_data)<>'array' or jsonb_array_length(variant_data) not between 1 and 100 then raise exception 'Variações inválidas';end if;
 if length(trim(coalesce(product_data->>'name',''))) not between 1 and 120 or length(trim(coalesce(product_data->>'category',''))) not between 1 and 60 or (product_data->>'price')::numeric<=0 then raise exception 'Produto inválido';end if;
 pid:=nullif(product_data->>'id','')::uuid;
 if pid is null then insert into public.products(name,category,description,image_url,price,compare_price,active) values(product_data->>'name',product_data->>'category',coalesce(product_data->>'description',''),nullif(product_data->>'image_url',''),(product_data->>'price')::numeric,nullif(product_data->>'compare_price','')::numeric,coalesce((product_data->>'active')::boolean,true)) returning id into pid;
 else update public.products set name=product_data->>'name',category=product_data->>'category',description=coalesce(product_data->>'description',''),image_url=nullif(product_data->>'image_url',''),price=(product_data->>'price')::numeric,compare_price=nullif(product_data->>'compare_price','')::numeric,active=coalesce((product_data->>'active')::boolean,true) where id=pid; if not found then raise exception 'Produto não encontrado';end if;end if;
 for v in select value from jsonb_array_elements(variant_data) loop
  color_val:=trim(v->>'color');size_val:=trim(v->>'size');qty:=(v->>'stock')::integer;
  if length(color_val) not between 1 and 50 or length(size_val) not between 1 and 30 or qty not between 0 and 100000 then raise exception 'Variação inválida';end if;
  insert into public.product_variants(product_id,color,size,stock) values(pid,color_val,size_val,qty) on conflict(product_id,color,size) do update set stock=excluded.stock;
 end loop;
 -- Variações não listadas são zeradas (não excluídas para preservar histórico de pedidos).
 update public.product_variants pv set stock=0 where pv.product_id=pid and not exists(select 1 from jsonb_array_elements(variant_data) x where x->>'color'=pv.color and x->>'size'=pv.size);
 return pid;
end $$;
revoke all on function public.admin_save_product(jsonb,jsonb) from public;grant execute on function public.admin_save_product(jsonb,jsonb) to authenticated;
-- Após criar o usuário em Authentication > Users, vincule o UUID dele ao painel:
-- insert into public.admins(user_id) values ('COLE-AQUI-O-UUID-DO-USUARIO');
