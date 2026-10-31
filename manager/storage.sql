-- Execute depois do supabase.sql, no SQL Editor.
-- Imagens públicas, mas uploads permitidos SOMENTE aos administradores autorizados.
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('product-images','product-images',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=true,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp'];

create policy "Admin upload product images"
on storage.objects for insert to authenticated
with check (bucket_id='product-images' and public.is_admin());
create policy "Admin update product images"
on storage.objects for update to authenticated
using (bucket_id='product-images' and public.is_admin())
with check (bucket_id='product-images' and public.is_admin());
create policy "Admin delete product images"
on storage.objects for delete to authenticated
using (bucket_id='product-images' and public.is_admin());
