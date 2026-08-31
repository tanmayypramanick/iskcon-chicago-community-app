# Sending the temple's auth emails — Brevo

Supabase's built-in sender is rate-limited to a few messages an hour and is
explicitly not for production, so the app needs its own SMTP.

**Use Brevo.** Not because it is the best transactional provider, but because
the DNS work for it is already done on this domain — and DNS is the one thing
you cannot do, since HostMonster is not yours to log into.

Free tier: **300 emails/day**. The app sends signup confirmations and password
resets — a handful a day. That is ample.

---

## Why Brevo, checked rather than assumed

Every record below is live on `iskconchicago.com` right now:

| Record | Value | Means |
|---|---|---|
| `brevo1._domainkey` | CNAME → `b1.iskconchicago-com.dkim.brevo.com` | DKIM key 1 |
| `brevo2._domainkey` | CNAME → `b2.iskconchicago-com.dkim.brevo.com` | DKIM key 2 |
| `_dmarc` | `v=DMARC1; p=none; rua=mailto:rua@dmarc.brevo.com` | DMARC, reporting to Brevo |
| root `TXT` | `brevo-code:53d36c…` | domain ownership verified |

Note the CNAME targets contain `iskconchicago-com` — these keys belong to a
Brevo account **for this domain**. Somebody set this up properly and did not
finish wiring it to anything.

**This is why no SPF change is needed.** DMARC passes if *either* SPF or DKIM
aligns. Brevo signs with a key published under `iskconchicago.com`, so DKIM
aligns and DMARC passes on its own. Resend would have needed three new DNS
records; Brevo needs zero.

---

## Step 1 — get into the Brevo account

The DNS points at an existing account, so the goal is to reach **that** account,
not to make a new one.

1. Go to <https://app.brevo.com> → **Log in** → *Forgot password*.
2. Try `tech@iskconchicago.com` first. If a reset email arrives, you are in.
3. If not, try any other temple address you can read.

**If you cannot recover it**, you have two honest options:

- **Ask whoever holds HostMonster.** They almost certainly created the Brevo
  account too — the same person did the DNS. This is the better outcome, because
  you inherit the working DKIM.
- **Create a new Brevo account and verify only the sender address.** Brevo lets
  you send from a *verified sender* without domain authentication: you add
  `tech@iskconchicago.com`, Brevo emails it a confirmation link, you click it.
  **No DNS needed.** Mail still sends and still arrives — but it is signed with
  Brevo's own domain rather than yours, so DKIM will not align with
  `iskconchicago.com` and deliverability is a step worse. It is a fine place to
  start and worth replacing later.

Say which of these you end up on — it changes what step 4's headers should show.

---

## Step 2 — create an SMTP key

In Brevo: **top-right menu → SMTP & API → SMTP tab**.

1. Note the **Login** shown there. It is usually the account email, and it is
   *not* always the address you send from.
2. **Generate a new SMTP key**, name it `iskcon-chicago-app`.
3. Copy it now — it is shown once.

This is an SMTP key, **not** your Brevo account password and **not** an API
(`xkeysib-…`) key. Supabase needs the SMTP one.

---

## Step 3 — check the sender address is allowed

**Senders, Domains & Dedicated IPs → Senders.**

`tech@iskconchicago.com` must be listed and verified. If it is not, add it —
Brevo sends a confirmation link to that inbox, which you can read.

Supabase will send *from* this address. Brevo refuses mail from an unverified
sender, and the failure looks like Supabase silently not sending.

---

## Step 4 — point Supabase at Brevo

Supabase Dashboard → **Project Settings → Authentication → SMTP Settings** →
enable *Custom SMTP*:

| Field | Value |
|---|---|
| Sender email | `tech@iskconchicago.com` |
| Sender name | `ISKCON Chicago` |
| Host | `smtp-relay.brevo.com` |
| Port | `587` |
| Username | the **Login** from step 2 |
| Password | the **SMTP key** from step 2 |

Port `587` is STARTTLS and is what Brevo documents. `465` also works if 587 is
blocked. Never `25`.

**Then raise the rate limit.** Authentication → **Rate Limits** → *Emails per
hour*. The default is sized for Supabase's own sender and will throttle you long
before Brevo's 300/day does.

---

## Step 5 — allow the landing page and the app's deep links

An auth email is useless if its link cannot be opened, and Supabase redirects
only to URLs it has been told about — an unlisted one is silently replaced with
the Site URL, so the devotee lands somewhere that does nothing.

Dashboard → **Authentication → URL Configuration → Redirect URLs**, add all
three:

```
https://tanmayypramanick.github.io/iskcon-chicago-community-app/
iskconchicago://auth/callback
iskconchicago://auth/recover
```

**The https one is what the emails now point at**, and it is where a
"send me a fresh link" request on that page asks to come back to. The trailing
slash is part of it — Supabase matches the string, so
`…/iskcon-chicago-community-app` without the slash is a different entry and will
not match what the app sends.

That page is `docs/index.html` in this repo, published by **GitHub Pages**
(repo → Settings → Pages → Source: *Deploy from a branch*, branch `main`, folder
`/docs`). It exists because a custom scheme cannot be opened from inside Gmail's
or Outlook's embedded browser, and cannot be opened at all on a laptop — so the
email points at a web page, and the page finishes the job, including setting the
new password.

The two deep links stay listed because that page hands off to them: its "Open in
the ISKCON Chicago app" button builds `iskconchicago://auth/recover#…` for a
password reset and `iskconchicago://auth/callback#…` otherwise. `auth/callback`
is also what Google sign-in uses, and that one must never move to https —
`WebBrowser.openAuthSessionAsync` watches for exactly that URL. See
`src/services/auth.ts`.

If you prefer the Management API to the dashboard:

```bash
curl -X PATCH "https://api.supabase.com/v1/projects/gkkeebhdavavizcvknwy/config/auth" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "uri_allow_list": "https://tanmayypramanick.github.io/iskcon-chicago-community-app/,https://tanmayypramanick.github.io/iskcon-chicago-community-app/**,iskconchicago://auth/callback,iskconchicago://auth/recover"
  }'
```

`uri_allow_list` is a comma-separated string and **replaces** the whole list, so
send every entry you want to keep in one call.

---

## Step 6 — paste the templates

Dashboard → **Authentication → Email Templates**. For each tab, paste the whole
file and save:

| Tab | File |
|---|---|
| Confirm signup | `01-confirm-signup.html` |
| Reset password | `02-reset-password.html` |
| Magic link | `03-magic-link.html` |
| Change email address | `04-change-email.html` |

**Set the subject lines too** — a separate field above the body:

| Tab | Subject |
|---|---|
| Confirm signup | `Confirm your email — ISKCON Chicago` |
| Reset password | `Set a new password — ISKCON Chicago` |
| Magic link | `Your sign-in link — ISKCON Chicago` |
| Change email | `Confirm your new address — ISKCON Chicago` |

### About the six-digit code in three of them

`01-confirm-signup.html`, `02-reset-password.html` and `03-magic-link.html`
print `{{ .Token }}` — the six-digit OTP Supabase generates for every auth email
— underneath the button, with one line telling the devotee to tap **Enter a code
instead** on the app's sign-in screen.

It is there because the button cannot reach everybody. Gmail and Outlook open
links in their own embedded browser, and an embedded browser will not hand a
custom scheme to an app; on a laptop there is no app at all. The code needs no
browser, no scheme and no hosting. **It is a fallback, not a replacement** — the
button is still one tap where it works, and the code is deliberately quieter.

`04-change-email.html` deliberately has **no** code. The app has nowhere to type
one: an email change is started from inside the app, and Supabase's secure email
change wants a token from each of the two addresses. Printing a code with no
screen behind it would be worse than printing none.

`mailer_otp_exp` is `3600` on this project, and the copy says "good for one
hour". `EMAIL_CODE_TTL_MS` in `src/services/auth.ts` mirrors it — it is how the
app tells an expired code from a mistyped one, since GoTrue answers both with
the same "Token has expired or is invalid". If you ever change that setting,
change the constant and this line in the same commit.

### About the fonts in these emails

The templates ask for EB Garamond and Source Sans 3 the way the app does, but
**Gmail strips webfont links**. Gmail renders Georgia and Helvetica instead,
which is why every font stack in the file names a real fallback rather than
trusting the webfont to arrive. Apple Mail honours it and shows the real faces.
That is a limit of email clients, not of the templates.

---

## Step 7 — test it

Order matters; each step proves the one before.

**a. Send a real one.** In the app's sign-in screen → *Forgot password* →
`tech@iskconchicago.com`. Or from Supabase: **Authentication → Users** → your
row → *Send password recovery*.

**b. It arrives in the inbox, not spam.** If Supabase reports success and
nothing arrives at all, check Brevo → **Transactional → Logs**: a rejected
sender or a bad key shows there, and tells you which of steps 2–4 is wrong.

**c. It renders** — marigold rule, serif heading, marigold pill button.

**d. Open the raw headers.** Gmail → ⋮ → *Show original*:

- `DKIM: PASS` — and check the `d=` value.
  - `d=iskconchicago.com` → you are on the inherited account, fully aligned.
  - `d=brevo.com` (or similar) → you made a new account and verified only the
    sender. It works, but it is the weaker setup described in step 1.
- `DMARC: PASS` — expected either way, because the policy is `p=none`.
- `SPF` may show `fail` or `neutral`. **This is not a problem here** — the
  domain's SPF does not list Brevo, and it does not need to, because DMARC is
  satisfied by DKIM alignment.

**e. The button opens the landing page.** It should show *Choose a new password*
in a browser — on the phone and on a laptop, and from inside Gmail's own reader.
If it lands on the temple website or on the Site URL instead, the https entry in
step 5 is missing or its trailing slash is wrong. If it shows the page's markup
as plain text, the email is still pointing at the old edge function; see the
banner in `supabase/functions/auth-link/index.ts`.

Tap **Open in the ISKCON Chicago app** from that page on a phone that has the
app: it should land on *Choose a new password* in the app itself.

**f. Actually change the password and sign in with the new one.** An email that
arrives but whose link does not complete is not a working setup.

---

## One thing that is broken and is not the app's fault

The domain's SPF record is:

```
v=spf1 ip4:67.20.113.211 a mx ptr include:hostmonster.com ?all
```

There is **no `include:_spf.google.com`**, so ordinary mail sent from
`tech@iskconchicago.com` through Google Workspace is not SPF-authorised. That
affects the temple's normal correspondence, not this app, and it needs DNS
access to fix.

When you next speak to whoever holds HostMonster, ask them to change that record
— editing the existing one, never adding a second, since a domain with two SPF
records fails SPF outright:

```
v=spf1 ip4:67.20.113.211 a mx include:_spf.google.com include:hostmonster.com ~all
```

(`ptr` dropped as deprecated by RFC 7208; `?all` → `~all` because "neutral"
tells receivers to make nothing of a failure.)

Nothing in this guide depends on that being done.
