-- Idempotent seed for the reliable live-seva milestone.
-- Run after 202608030007_reliable_service_activity_and_interests.sql.

insert into public.service_types (name, category)
values
  ('Pot Washing', 'kitchen'),
  ('Vegetable Cutting', 'kitchen'),
  ('Kitchen Preparation', 'kitchen'),
  ('Prasadam Serving', 'kitchen'),
  ('Sunday Feast Cleanup', 'cleaning'),
  ('Temple Room Cleaning', 'cleaning'),
  ('Flower Garlands', 'deity-worship'),
  ('Mangal Arati Setup', 'deity-worship'),
  ('Festival Decoration', 'event'),
  ('Guest Welcome', 'event'),
  ('Book Table', 'event'),
  ('Shoe Room', 'event'),
  ('Kirtana Support', 'event'),
  ('General Temple Service', 'other')
on conflict (name) do update
set
  category = excluded.category,
  is_active = true;

update public.service_types
set qr_token = 'iskcon-chicago:seva:' || id::text
where qr_token is null;
