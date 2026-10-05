-- Block disposable and temporary email signups at the database level.
-- Run this in the Supabase SQL editor.

create or replace function public.check_email_not_disposable()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  domain_part text;
begin
  if new.email is null then
    return new;
  end if;

  domain_part := lower(split_part(new.email, '@', 2));

  -- Check against common disposable domains
  if domain_part in (
    '10minutemail.com', '10minutemail.net', '10minmail.com', '20minutemail.com',
    'tempmail.com', 'temp-mail.org', 'temp-mail.io', 'tempmail.net', 'tempail.com',
    'mailinator.com', 'guerrillamail.com', 'guerrillamail.net', 'guerrillamail.org',
    'sharklasers.com', 'grr.la', 'spam4.me', 'trashmail.com', 'trashmail.net',
    'trashmail.org', 'trashmail.me', 'yopmail.com', 'yopmail.net', 'yopmail.fr',
    'dispostable.com', 'getairmail.com', 'throwawaymail.com', 'fakemailgenerator.com',
    'maildrop.cc', 'inboxkitten.com', 'generator.email', 'emailondeck.com',
    'crazymailing.com', 'mohmal.com', 'burnermail.io', 'nada.ltd', 'getnada.com',
    'abcvg.com', 'dropmail.me', 'tempinbox.com', 'tmail.ws', 'chacuo.net',
    'fakeinbox.com', 'mytemp.email', 'harakirimail.com', 'spambog.com', 'disposablemail.com'
  ) then
    raise exception 'Disposable or temporary email addresses are not allowed on InnerWave.';
  end if;

  -- Check against throwaway keyword patterns in domain
  if domain_part ~* '(^|\.)(temp|dispos|trash|fake|throwaway|burner|guerrilla|mailinator|10minute|maildrop|generator|spambox|fakemail|yopmail|mohmal|discard|sharklaser|mytemp|jetable)[\w-]*\.[a-z]{2,}$' then
    raise exception 'Disposable or temporary email addresses are not allowed on InnerWave.';
  end if;

  return new;
end;
$$;

drop trigger if exists on_auth_user_check_disposable on auth.users;
create trigger on_auth_user_check_disposable
before insert or update of email on auth.users
for each row
execute function public.check_email_not_disposable();
