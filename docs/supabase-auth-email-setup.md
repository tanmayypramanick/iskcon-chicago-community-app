# ISKCON Chicago authentication email setup

This runbook configures production authentication mail for ISKCON Chicago: Act
of Service. SMTP passwords belong only in Supabase. They must never be added to
the Expo app, `.env.local`, Git, or a mobile build.

## Sender

- Sender name: `ISKCON Chicago`
- Sender address: `tech@iskconchicago.com`
- Reply-to address: `tech@iskconchicago.com`

## Supabase settings

In Authentication → URL Configuration:

- Keep the public ISKCON Chicago website as the Site URL when a suitable HTTPS
  page is available.
- Add `iskconchicago://auth/callback` to Redirect URLs.
- Add `iskconchicago://auth/recover` to Redirect URLs.

In Authentication → Emails → SMTP:

- Enable custom SMTP.
- Enter the host, port, username and password supplied by the chosen mail
  provider.
- Set the sender name and address exactly as shown above.

At the DNS provider for `iskconchicago.com`, publish the SPF and DKIM records
supplied by the SMTP provider. Publish a DMARC record as well, beginning with a
monitoring policy (`p=none`) until normal mail has been observed, then move to a
stricter policy with the domain administrator's approval.

Disable click/open tracking for authentication emails. Rewritten links can
break Supabase verification and recovery URLs.

## Confirm signup

Subject:

`Welcome to ISKCON Chicago — verify your email`

Body:

```html
<!doctype html>
<html lang="en">
  <body
    style="margin:0;background:#f7f0e3;color:#39332b;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;"
  >
    <table
      role="presentation"
      width="100%"
      cellspacing="0"
      cellpadding="0"
      style="background:#f7f0e3;padding:32px 16px;"
    >
      <tr>
        <td align="center">
          <table
            role="presentation"
            width="100%"
            cellspacing="0"
            cellpadding="0"
            style="max-width:560px;background:#fffdf8;border:1px solid #e2d5bf;border-radius:24px;overflow:hidden;"
          >
            <tr>
              <td style="height:7px;background:#273b73;"></td>
            </tr>
            <tr>
              <td style="padding:38px 34px 32px;">
                <p
                  style="margin:0;color:#1b766f;font-size:12px;letter-spacing:2px;text-transform:uppercase;"
                >
                  ISKCON Chicago
                </p>
                <h1
                  style="margin:12px 0 14px;color:#273b73;font-family:Georgia,'Times New Roman',serif;font-size:30px;font-weight:400;line-height:1.2;"
                >
                  Welcome to our temple community
                </h1>
                <p style="margin:0 0 14px;font-size:16px;line-height:1.65;">
                  Hare Kṛṣṇa,
                </p>
                <p style="margin:0 0 22px;font-size:16px;line-height:1.65;">
                  Thank you for joining the ISKCON Chicago community app, home
                  of Śrī Śrī Kiśora-Kiśorī. Verify your email to enter a shared
                  space for seva, kīrtana and Vaiṣṇava connection.
                </p>
                <table role="presentation" cellspacing="0" cellpadding="0">
                  <tr>
                    <td style="border-radius:999px;background:#e9a63b;">
                      <a
                        href="{{ .ConfirmationURL }}"
                        style="display:inline-block;padding:14px 24px;color:#273b73;text-decoration:none;font-size:16px;line-height:1;"
                        >Verify my email</a
                      >
                    </td>
                  </tr>
                </table>
                <p
                  style="margin:24px 0 0;color:#766d60;font-size:13px;line-height:1.6;"
                >
                  Open this link on the phone where the app is installed. For
                  your security, do not forward this email or share its link.
                </p>
                <p
                  style="margin:24px 0 0;color:#766d60;font-size:13px;line-height:1.6;"
                >
                  If you did not create this account, you may safely ignore this
                  message.
                </p>
              </td>
            </tr>
            <tr>
              <td
                style="border-top:1px solid #e2d5bf;padding:20px 34px;color:#8a8174;font-size:12px;line-height:1.6;"
              >
                ISKCON Chicago · 1716 W Lunt Ave, Chicago, IL 60626<br />
                Account support: tech@iskconchicago.com
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>
```

## Reset or change password

Subject:

`Your secure ISKCON Chicago password link`

Body:

```html
<!doctype html>
<html lang="en">
  <body
    style="margin:0;background:#f7f0e3;color:#39332b;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;"
  >
    <table
      role="presentation"
      width="100%"
      cellspacing="0"
      cellpadding="0"
      style="background:#f7f0e3;padding:32px 16px;"
    >
      <tr>
        <td align="center">
          <table
            role="presentation"
            width="100%"
            cellspacing="0"
            cellpadding="0"
            style="max-width:560px;background:#fffdf8;border:1px solid #e2d5bf;border-radius:24px;overflow:hidden;"
          >
            <tr>
              <td style="height:7px;background:#273b73;"></td>
            </tr>
            <tr>
              <td style="padding:38px 34px 32px;">
                <p
                  style="margin:0;color:#1b766f;font-size:12px;letter-spacing:2px;text-transform:uppercase;"
                >
                  ISKCON Chicago
                </p>
                <h1
                  style="margin:12px 0 14px;color:#273b73;font-family:Georgia,'Times New Roman',serif;font-size:30px;font-weight:400;line-height:1.2;"
                >
                  Choose a new password
                </h1>
                <p style="margin:0 0 14px;font-size:16px;line-height:1.65;">
                  Hare Kṛṣṇa,
                </p>
                <p style="margin:0 0 22px;font-size:16px;line-height:1.65;">
                  A secure password-change link was requested for your ISKCON
                  Chicago account. Open it on the phone where the app is
                  installed.
                </p>
                <table role="presentation" cellspacing="0" cellpadding="0">
                  <tr>
                    <td style="border-radius:999px;background:#e9a63b;">
                      <a
                        href="{{ .ConfirmationURL }}"
                        style="display:inline-block;padding:14px 24px;color:#273b73;text-decoration:none;font-size:16px;line-height:1;"
                        >Choose my new password</a
                      >
                    </td>
                  </tr>
                </table>
                <p
                  style="margin:24px 0 0;color:#766d60;font-size:13px;line-height:1.6;"
                >
                  This link is private and time-limited. ISKCON Chicago will
                  never ask you to send your password by email or message.
                </p>
                <p
                  style="margin:24px 0 0;color:#766d60;font-size:13px;line-height:1.6;"
                >
                  If you did not request this change, leave your password
                  unchanged and contact tech@iskconchicago.com.
                </p>
              </td>
            </tr>
            <tr>
              <td
                style="border-top:1px solid #e2d5bf;padding:20px 34px;color:#8a8174;font-size:12px;line-height:1.6;"
              >
                ISKCON Chicago · 1716 W Lunt Ave, Chicago, IL 60626<br />
                Account support: tech@iskconchicago.com
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>
```

## Remaining Supabase email subjects

Use the same visual shell and footer for the remaining templates:

- Invite user: `You are invited to the ISKCON Chicago community`
- Magic link: `Your secure sign-in link for ISKCON Chicago`
- Change email address: `Confirm your new ISKCON Chicago email address`
- Reauthentication: `Your ISKCON Chicago security code`
- Password changed notification: `Your ISKCON Chicago password was changed`
- Email changed notification: `Your ISKCON Chicago email address was changed`
- Sign-in method linked: `A sign-in method was added to your account`
- Sign-in method removed: `A sign-in method was removed from your account`

Security-notification copy should state what changed, when it changed, that the
recipient does not need to act if they made the change, and that an unexpected
change must be reported immediately to `tech@iskconchicago.com`. Never include
passwords, session tokens, private profile details, or a request to reply with
security information.

## Release verification

Test with an address that is not a member of the Supabase organization:

1. Create an account and confirm that the email comes from the configured
   sender, passes SPF/DKIM, and opens the installed app.
2. Request a forgotten-password link while signed out and set a new password.
3. Request a change-password link from Profile and set a new password.
4. Confirm the old password no longer signs in and the new password does.
5. Open an expired or already-used link and confirm the app gives a clear error.
6. Confirm email clients in both light and dark mode keep the button and text
   readable.
7. Confirm authentication email click tracking is disabled.
