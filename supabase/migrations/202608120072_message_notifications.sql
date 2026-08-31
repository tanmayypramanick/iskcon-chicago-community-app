-- Direct and sanga messages must reach the in-app bell as well as their
-- realtime chat lists. System push is then an optional delivery channel for
-- the same app_notifications row, not a separate source of truth.

alter table public.app_notifications
  drop constraint if exists app_notifications_kind_check;

alter table public.app_notifications
  add constraint app_notifications_kind_check check (
    kind in (
      'service_open', 'service_offer', 'service_recurring_offer',
      'service_offer_response', 'service_joined', 'service_left',
      'service_started', 'service_completed', 'service_cancelled',
      'service_deleted', 'service_coverage_needed',
      'service_coverage_resolved', 'recurring_interest_submitted',
      'recurring_interest_reviewed',
      'seva_verification_requested', 'seva_verification_reviewed',
      'weekly_offer_countered', 'weekly_offer_counter_reviewed',
      'access_request_submitted', 'access_request_reviewed',
      'devotee_joined', 'profile_incomplete',
      'sanga_created', 'sanga_reviewed',
      'sanga_join_requested', 'sanga_join_reviewed',
      'sanga_member_added', 'sanga_member_removed', 'sanga_member_left',
      'sanga_admin_transferred', 'sanga_deleted',
      'announcement_posted',
      'feedback_reviewed',
      'care_reply',
      'birthday_today',
      'newsletter_posted',
      'newsletter_reviewed',
      'access_appointed',
      'access_revoked',
      'sponsorship_fulfilled',
      'announcement_commented',
      'announcement_comment_replied',
      'seva_award_earned',
      'message_received',
      'sanga_message_received',
      'remote'
    )
  );

create or replace function public.notify_direct_message_received()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  conversation public.conversations;
  sender_name text;
  recipient_id uuid;
  summary text;
begin
  select * into conversation
  from public.conversations
  where id = new.conversation_id;

  if conversation.id is null then
    return new;
  end if;

  recipient_id := case
    when conversation.lower_devotee_id = new.sender_id
      then conversation.higher_devotee_id
    else conversation.lower_devotee_id
  end;

  select users.name into sender_name
  from public.users
  where users.id = new.sender_id;

  summary := case
    when nullif(trim(coalesce(new.body, '')), '') is not null
      then left(trim(new.body), 140)
    else 'Sent you a picture.'
  end;

  insert into public.app_notifications (user_id, kind, title, body, data)
  values (
    recipient_id,
    'message_received',
    coalesce(nullif(trim(sender_name), ''), 'A devotee') || ' sent you a message',
    summary,
    jsonb_build_object(
      'conversationId', new.conversation_id,
      'messageId', new.id,
      'devoteeId', new.sender_id,
      'name', coalesce(nullif(trim(sender_name), ''), 'A devotee')
    )
  );

  return new;
end;
$$;

revoke all on function public.notify_direct_message_received() from public, anon, authenticated;

drop trigger if exists direct_message_notified on public.messages;
create trigger direct_message_notified
  after insert on public.messages
  for each row execute function public.notify_direct_message_received();

create or replace function public.notify_sanga_message_received()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  sender_name text;
  sanga_name text;
  summary text;
begin
  select users.name into sender_name
  from public.users
  where users.id = new.sender_id;

  select sangas.name into sanga_name
  from public.sangas
  where sangas.id = new.sanga_id;

  summary := case
    when nullif(trim(coalesce(new.body, '')), '') is not null
      then left(trim(new.body), 140)
    else 'Sent a picture to the sanga.'
  end;

  insert into public.app_notifications (user_id, kind, title, body, data)
  select
    members.devotee_id,
    'sanga_message_received',
    coalesce(nullif(trim(sender_name), ''), 'A devotee') || ' in ' ||
      coalesce(nullif(trim(sanga_name), ''), 'your sanga'),
    summary,
    jsonb_build_object(
      'sangaId', new.sanga_id,
      'sangaName', coalesce(nullif(trim(sanga_name), ''), 'Sanga'),
      'messageId', new.id,
      'senderId', new.sender_id
    )
  from public.sanga_members members
  where members.sanga_id = new.sanga_id
    and members.devotee_id <> new.sender_id;

  return new;
end;
$$;

revoke all on function public.notify_sanga_message_received() from public, anon, authenticated;

drop trigger if exists sanga_message_notified on public.sanga_messages;
create trigger sanga_message_notified
  after insert on public.sanga_messages
  for each row execute function public.notify_sanga_message_received();

do $$
begin
  raise notice 'direct and sanga message notifications applied';
end;
$$;
