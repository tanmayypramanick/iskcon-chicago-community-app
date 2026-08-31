/**
 * SUPERSEDED — do not deploy. The live page is docs/index.html on GitHub Pages.
 *
 * This function is correct and it cannot work. Supabase will not serve HTML
 * from an edge function: the platform rewrites the response's content-type to
 * text/plain and replaces the CSP below with a bare `sandbox`, an anti-phishing
 * measure on supabase.co. Deployed and opened in a browser, a devotee is shown
 * the raw markup as text. There is no way around it from inside a function.
 *
 * It is kept rather than deleted only because it has never been committed —
 * deleting it would take the reasoning below with it, and that reasoning is
 * still the reasoning for the static page. The page in docs/ is this file's
 * markup, styles and script split into three files, with the four response
 * headers answered another way; docs/index.html records how. If you change one,
 * change the other, and if that ever stops being worth doing, delete this.
 *
 * The deployed copy should be removed — `supabase functions delete auth-link
 * --project-ref …` — so that links from emails already sent fail visibly rather
 * than landing on a page of text.
 *
 * Why this exists at all
 * ----------------------
 * The emails used to redirect straight to `iskconchicago://auth/callback#…`.
 * The app handles that perfectly — but the app is never the thing that opens
 * it. Gmail and Outlook open links inside their own embedded browser, and an
 * embedded browser will not hand a custom scheme to another application: the
 * devotee taps, a browser appears, and nothing happens. On a laptop there is no
 * app to hand it to at all, so the link can never work there. A password reset
 * that only works if you happen to read your mail in Apple Mail is not a
 * password reset.
 *
 * So the emails now point at this `https://` page, which every mail client will
 * open, and the page finishes the job itself: it sets the new password in the
 * browser, or confirms the address, and offers to hand off to the app for the
 * devotees whose mail client can.
 *
 * How the tokens are handled, and why it is written this way
 * ---------------------------------------------------------
 * Supabase is on the implicit flow (see src/lib/supabase.ts), so the link
 * carries a live session in the URL **fragment**. Browsers never send a
 * fragment to the server, which is the one property that makes this safe — the
 * temple's own edge function never sees, never logs and never stores a
 * devotee's access token. Everything below protects that property:
 *
 *   - No token is ever read on the server. This file renders one static page.
 *   - The page strips the fragment with history.replaceState the instant it has
 *     read it, so the tokens do not sit in browser history or ride along on a
 *     later navigation.
 *   - The password change is made by the browser directly against Supabase's
 *     auth API with the access token as a bearer. It does not come back here.
 *   - Referrer-Policy: no-referrer, and a CSP whose connect-src is the Supabase
 *     origin and nothing else, so no script on this page can post a token
 *     anywhere — including to us.
 *   - The publishable/anon key is embedded. That key is public by design; it is
 *     the same one compiled into the app. The service-role key is never read in
 *     this file and must never be added to it.
 *
 * Environment
 * -----------
 *   SUPABASE_URL          required; injected automatically on deploy
 *   SUPABASE_ANON_KEY     required; injected automatically on deploy
 *   AUTH_LINK_ANON_KEY    optional; overrides the above when the project has
 *                         moved to `sb_publishable_…` keys and the legacy anon
 *                         JWT has been disabled
 *   AUTH_LINK_APP_SCHEME  optional; defaults to the app's `iskconchicago`
 *
 * Deploy: supabase functions deploy auth-link --no-verify-jwt --project-ref …
 * It must be public — the devotee opening it has no JWT to present.
 */

/** Mirrors PASSWORD_MIN_LENGTH in src/services/auth.ts, which mirrors the
 * project's `password_min_length`. If one moves, all three move together — a
 * page that promises a rule the server does not enforce is lying to devotees. */
const PASSWORD_MIN_LENGTH = 6;

const DEFAULT_APP_SCHEME = "iskconchicago";

function html(config: Record<string, unknown>, nonce: string) {
  // Serialised rather than interpolated so a stray quote in an env value can
  // never break out into markup. Nothing here comes from the URL — the
  // fragment is read only in the browser — but the habit is worth keeping.
  const json = JSON.stringify(config).replace(/</g, "\\u003c");

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light">
<meta name="referrer" content="no-referrer">
<title>ISKCON Chicago</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=EB+Garamond:ital,wght@0,600;1,500&family=Source+Sans+3:wght@400;600;700&display=swap" rel="stylesheet">
<style nonce="${nonce}">
  :root {
    --marigold:#E8971C; --marigold-soft:#F8D791; --indigo:#2B3A67;
    --vermilion:#C1440E; --vermilion-soft:#FAE7DF; --ivory:#FBF7EF;
    --stone:#3A342B; --stone-muted:#766D61; --peacock:#1F6F67;
    --peacock-soft:#DCECE8; --border:#DED2BF; --white:#FFFFFF;
    --serif:'EB Garamond',Georgia,'Times New Roman',serif;
    --sans:'Source Sans 3',-apple-system,'Segoe UI',Helvetica,Arial,sans-serif;
  }
  * { box-sizing:border-box; }
  body {
    margin:0; background:var(--ivory); color:var(--stone);
    font-family:var(--sans); font-size:16px; line-height:26px;
    -webkit-text-size-adjust:100%;
    /* One layout for 375px and 1440px: the card simply stops growing. The
       page is centred vertically only when there is room for it, so a long
       recovery form on a short phone still scrolls from the top. */
    display:flex; align-items:center; justify-content:center;
    min-height:100vh; padding:32px 16px;
  }
  .wrap { width:100%; max-width:600px; }
  .eyebrow {
    text-align:center; font-size:11px; font-weight:700; letter-spacing:1.6px;
    text-transform:uppercase; color:var(--peacock); line-height:16px;
    margin:0 0 20px 0;
  }
  .card {
    background:var(--white); border:1px solid var(--border);
    border-radius:16px; overflow:hidden;
  }
  .rule { height:4px; background:var(--marigold); }
  .body { padding:30px 40px 32px 40px; text-align:center; }
  .greeting {
    margin:0; font-family:var(--serif); font-style:italic; font-size:17px;
    line-height:24px; color:var(--peacock);
  }
  h1 {
    margin:10px 0 0 0; font-family:var(--serif); font-weight:600;
    /* Reads at 375px and does not become a banner at 1440px. */
    font-size:clamp(26px,5vw,30px); line-height:1.24; color:var(--stone);
  }
  p.lede { margin:14px 0 0 0; color:var(--stone-muted); }
  .mark {
    width:64px; height:64px; margin:0 auto 4px auto; border-radius:999px;
    display:flex; align-items:center; justify-content:center;
    background:var(--peacock-soft); color:var(--peacock);
  }
  .mark.warn { background:var(--vermilion-soft); color:var(--vermilion); }
  .mark svg { width:32px; height:32px; }

  form { margin:24px 0 0 0; text-align:left; }
  label {
    display:block; font-size:13px; font-weight:600; line-height:20px;
    color:var(--stone); margin:0 0 6px 2px;
  }
  .field { position:relative; margin:0 0 12px 0; }
  input, select {
    width:100%; min-height:48px; padding:11px 14px; font-family:var(--sans);
    font-size:16px; line-height:24px; color:var(--stone);
    background:var(--white); border:1px solid var(--border);
    border-radius:16px; appearance:none;
  }
  /* appearance:none takes the native arrow with it, and a select that looks
     like a text box does not get opened. Drawn rather than fetched, so the CSP
     has no host to allow. */
  select {
    padding-right:44px;
    background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23766D61' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='m6 9 6 6 6-6'/%3E%3C/svg%3E");
    background-repeat:no-repeat; background-position:right 14px center;
    background-size:18px 18px;
  }
  input[type=password], input#reveal-target { padding-right:78px; }
  input:focus-visible, select:focus-visible, button:focus-visible, a:focus-visible {
    outline:2px solid var(--indigo); outline-offset:2px;
  }
  .reveal {
    position:absolute; top:0; right:0; height:100%; padding:0 14px;
    background:none; border:0; color:var(--stone-muted);
    font-family:var(--sans); font-size:13px; font-weight:600; cursor:pointer;
    min-width:auto;
  }

  button.primary, a.primary, button.secondary, a.secondary {
    display:flex; align-items:center; justify-content:center; width:100%;
    min-height:48px; padding:10px 24px; border-radius:999px; border:1px solid transparent;
    font-family:var(--sans); font-size:16px; font-weight:700; line-height:24px;
    text-decoration:none; cursor:pointer; margin-top:12px;
  }
  button.primary, a.primary { background:var(--marigold); color:var(--indigo); }
  button.secondary, a.secondary {
    background:var(--white); color:var(--indigo); border-color:var(--border);
  }
  button[disabled] { opacity:.55; cursor:default; }

  .note {
    margin:22px 0 0 0; padding:18px 0 0 0; border-top:1px solid var(--border);
    font-size:13px; line-height:21px; color:var(--stone-muted);
  }
  .message {
    margin:12px 0 0 0; font-size:14px; line-height:22px; text-align:left;
  }
  .message.bad { color:var(--vermilion); }
  .message.good { color:var(--peacock); }
  .detail {
    margin:14px 0 0 0; padding:12px 16px; border-radius:16px;
    background:var(--ivory); border:1px solid var(--border);
    font-size:14px; line-height:22px; color:var(--stone-muted);
    text-align:left; word-break:break-word;
  }

  /* The hand-off to the app. Never hidden — a devotee on a laptop may still
     want it on the phone in their hand — but it earns the loud styling only
     where it can actually work. */
  .handoff {
    margin:22px 0 0 0; padding:18px 0 0 0; border-top:1px solid var(--border);
  }
  .handoff p { margin:0; font-size:13px; line-height:21px; color:var(--stone-muted); }
  .servant {
    margin:22px 0 0 0; font-family:var(--serif); font-style:italic;
    font-size:15px; line-height:23px; color:var(--stone-muted);
  }
  .mantra {
    margin:24px 0 0 0; text-align:center; font-family:var(--serif);
    font-style:italic; font-size:15px; line-height:24px; color:var(--stone-muted);
  }
  .footer {
    margin:18px 0 0 0; text-align:center; font-size:12px; line-height:19px;
    color:var(--stone-muted);
  }
  .footer a, .mantra a { color:var(--indigo); }
  [hidden] { display:none !important; }

  @media (max-width:600px) {
    body { align-items:flex-start; padding:24px 12px 40px 12px; }
    .body { padding:26px 24px 28px 24px; }
  }
  /* Larger than a phone: the primary action does not need to span the card. */
  @media (min-width:601px) {
    button.primary, a.primary, button.secondary, a.secondary {
      width:auto; min-width:280px; margin-left:auto; margin-right:auto;
    }
    form button.primary { width:100%; }
  }
</style>
</head>
<body>
<div class="wrap">
  <p class="eyebrow">ISKCON Chicago</p>
  <div class="card">
    <div class="rule"></div>
    <div class="body">
      <div class="mark" id="mark" hidden>
        <svg id="mark-glyph" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"></svg>
      </div>
      <p class="greeting">Hare Kṛṣṇa</p>
      <h1 id="heading">One moment</h1>
      <p class="lede" id="lede">Opening your link.</p>
      <p class="detail" id="detail" hidden></p>

      <!-- Password recovery, done here in the browser. -->
      <form id="password-form" hidden autocomplete="on">
        <div class="field">
          <label for="password">New password</label>
          <input id="password" name="new-password" type="password" autocomplete="new-password" autocapitalize="none" spellcheck="false" required>
          <button type="button" class="reveal" id="reveal">Show</button>
        </div>
        <div class="field">
          <label for="confirmation">Confirm new password</label>
          <input id="confirmation" name="confirm-password" type="password" autocomplete="new-password" autocapitalize="none" spellcheck="false" required>
        </div>
        <button type="submit" class="primary" id="save">Save my new password</button>
        <p class="message" id="password-message" hidden aria-live="polite"></p>
      </form>

      <!-- Asking for a fresh link, when this one cannot be used. -->
      <form id="resend-form" hidden>
        <div class="field" id="kind-field" hidden>
          <label for="kind">What were you trying to do?</label>
          <select id="kind">
            <option value="recovery">Reset my password</option>
            <option value="signup">Confirm my email address</option>
            <option value="magiclink">Sign in with a link</option>
          </select>
        </div>
        <div class="field">
          <label for="email">Your email address</label>
          <input id="email" type="email" autocomplete="email" autocapitalize="none" spellcheck="false" placeholder="you@example.com" required>
        </div>
        <button type="submit" class="primary" id="send">Send me a fresh link</button>
        <p class="message" id="resend-message" hidden aria-live="polite"></p>
      </form>

      <div class="handoff" id="handoff" hidden>
        <p id="handoff-note">Have the app on this phone?</p>
        <a class="secondary" id="open-app" href="#">Open in the ISKCON Chicago app</a>
      </div>

      <p class="note" id="note" hidden></p>
      <p class="servant">Your servant,<br>ISKCON Chicago</p>
    </div>
  </div>
  <p class="mantra">Hare Kṛṣṇa Hare Kṛṣṇa &middot; Kṛṣṇa Kṛṣṇa Hare Hare<br>Hare Rāma Hare Rāma &middot; Rāma Rāma Hare Hare</p>
  <p class="footer">ISKCON Chicago &middot; <a href="mailto:tech@iskconchicago.com">tech@iskconchicago.com</a></p>
</div>
<script nonce="${nonce}">
(function () {
  "use strict";
  var CONFIG = ${json};

  /* ---------------------------------------------------------------------
   * 1. Read the fragment, then destroy it.
   *
   * This is the first thing that happens, before anything is rendered and
   * before any network call is possible. The tokens live from here on in a
   * closure variable and nowhere else: not in history, not in the DOM, not in
   * storage, and never in a URL that leaves this page except the app deep
   * link the devotee taps themselves.
   * ------------------------------------------------------------------- */
  var rawFragment = window.location.hash.replace(/^#/, "");
  var params = new URLSearchParams(rawFragment);
  /* GoTrue occasionally reports a refused verification in the query string
     rather than the fragment. Those are error codes, not secrets. */
  var query = new URLSearchParams(window.location.search);

  if (window.location.hash) {
    try {
      history.replaceState(null, "", window.location.pathname + window.location.search);
    } catch (e) {
      /* Some embedded browsers refuse replaceState. Better to carry on with a
         working reset than to abandon the devotee over a history entry. */
    }
  }

  var accessToken = params.get("access_token") || "";
  var refreshToken = params.get("refresh_token") || "";
  var linkType = params.get("type") || "";
  var errorCode = params.get("error_code") || query.get("error_code") || "";
  var errorText =
    params.get("error_description") || params.get("error") ||
    query.get("error_description") || query.get("error") || "";

  var el = function (id) { return document.getElementById(id); };
  /* Everything from the URL is written as text, never as markup. */
  var say = function (id, text) { el(id).textContent = text; };
  var show = function (id, on) { el(id).hidden = !on; };

  var GLYPHS = {
    check: "M20 6 9 17l-5-5",
    key: "M15 7a4 4 0 1 1-3.9 5H8v3H5v3H2v-3.6L9.6 9.4A4 4 0 0 1 15 7z",
    alert: "M12 8v5M12 17h.01M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"
  };
  function mark(glyph, warn) {
    el("mark-glyph").innerHTML = "";
    var path = document.createElementNS("http://www.w3.org/2000/svg", "path");
    path.setAttribute("d", GLYPHS[glyph]);
    el("mark-glyph").appendChild(path);
    el("mark").className = warn ? "mark warn" : "mark";
    show("mark", true);
  }

  /* ---------------------------------------------------------------------
   * 2. The hand-off to the app.
   *
   * Same tokens, same fragment, handed to the scheme the app registers. The
   * paths match what src/services/auth.ts builds, so an app that was never
   * updated still understands them.
   * ------------------------------------------------------------------- */
  var isPhone = /Android|iPhone|iPad|iPod/i.test(navigator.userAgent) ||
    window.matchMedia("(max-width: 600px)").matches;

  function offerTheApp() {
    /* Only when there is actually a session to hand over. An expired link has
       a fragment too, and sending that to the app would be inviting a devotee
       to watch the same failure happen twice. */
    if (!accessToken || !refreshToken) return;
    var path = linkType === "recovery" ? "auth/recover" : "auth/callback";
    el("open-app").setAttribute("href", CONFIG.appScheme + "://" + path + "#" + rawFragment);
    /* Loud where it can work, quiet but present everywhere else. */
    el("open-app").className = isPhone ? "primary" : "secondary";
    say("handoff-note", isPhone
      ? "Prefer to finish in the app? It is already signed in by this link."
      : "On the phone where you have the app installed, this button opens it directly.");
    show("handoff", true);
  }

  /* ---------------------------------------------------------------------
   * 3. Which of the five endings this link has.
   * ------------------------------------------------------------------- */
  function renderProblem(heading, lede, detail, kind) {
    mark("alert", true);
    say("heading", heading);
    say("lede", lede);
    if (detail) { say("detail", detail); show("detail", true); }
    show("resend-form", true);
    /* Only pre-select a kind the form can actually send. An email-change link
       cannot be re-sent without a session, so that devotee is asked what they
       want rather than being handed a form that would quietly do the wrong
       thing. */
    if (kind === "recovery" || kind === "signup" || kind === "invite" || kind === "magiclink") {
      el("kind").value = kind === "invite" ? "signup" : kind;
    } else {
      show("kind-field", true);
    }
    offerTheApp();
  }

  function renderConfirmation(heading, lede, note) {
    mark("check", false);
    say("heading", heading);
    say("lede", lede);
    if (note) { say("note", note); show("note", true); }
    offerTheApp();
  }

  /* A developer string is not an explanation. These are the three things that
     actually reach this page, said in a way a devotee can act on. */
  function explainFailure() {
    var raw = (errorCode + " " + errorText).toLowerCase();
    if (/expired/.test(raw)) {
      return {
        heading: "That link has expired",
        lede: "For your protection a link from us opens only for a short while. Ask for a fresh one below and it will reach you in a moment."
      };
    }
    if (/access_denied|already|used/.test(raw)) {
      return {
        heading: "That link has already been used",
        lede: "A link from us opens once. Ask for a fresh one below and you may carry on."
      };
    }
    return {
      heading: "That link could not be opened",
      lede: "A link from us opens once, and does not last forever. If it has been sitting a while, ask for a fresh one below."
    };
  }

  function start() {
    if (errorText || errorCode) {
      var reason = explainFailure();
      renderProblem(
        reason.heading,
        reason.lede,
        /* Verbatim, escaped by textContent, because a devotee reporting this to
           the temple should be able to say what it said. */
        errorText ? errorText.replace(/\\+/g, " ") : "",
        linkType || ""
      );
      return;
    }

    if (!accessToken || !refreshToken) {
      renderProblem(
        "There is no link to open here",
        "This page finishes a link from one of the temple's emails. Open the button in that email, or ask for a fresh link below.",
        "",
        ""
      );
      return;
    }

    if (linkType === "recovery") {
      mark("key", false);
      say("heading", "Choose a new password");
      say("lede", "Your link has signed you in. Choose a password so you can sign in normally next time \u2014 at least " + CONFIG.passwordMinLength + " characters.");
      show("password-form", true);
      offerTheApp();
      el("password").focus({ preventScroll: true });
      return;
    }

    if (linkType === "signup" || linkType === "invite") {
      renderConfirmation(
        "Your email is confirmed",
        "Welcome to the temple. Your place in the ISKCON Chicago community is ready — open the app and sign in.",
        "Nothing else is needed here. You may close this page."
      );
      return;
    }

    if (linkType === "email_change") {
      renderConfirmation(
        "Your new address is confirmed",
        "This account now uses this email address to sign in. The old one no longer will.",
        "Nothing else is needed here. You may close this page."
      );
      return;
    }

    if (linkType === "magiclink") {
      renderConfirmation(
        "You are signed in",
        "No password was needed. Open the app to carry on where you left off.",
        "Nothing else is needed here. You may close this page."
      );
      return;
    }

    /* A link we do not recognise. It carried a session, so the app may well
       understand it — the hand-off stays — but this page will not guess at
       what it was for. */
    renderProblem(
      "This link is not one we recognise",
      "It opened, but it does not say what it was for. Try it in the app below, or ask for a fresh link.",
      linkType ? "The link described itself as: " + linkType : "",
      ""
    );
  }

  /* ---------------------------------------------------------------------
   * 4. Setting the password — browser to Supabase, direct.
   * ------------------------------------------------------------------- */
  function authFetch(path, body, token) {
    var headers = { "apikey": CONFIG.anonKey, "content-type": "application/json" };
    if (token) headers["authorization"] = "Bearer " + token;
    return fetch(CONFIG.supabaseUrl + path, {
      method: token ? "PUT" : "POST",
      headers: headers,
      body: JSON.stringify(body),
      /* No cookies, and no Referer — this page must be invisible to anything
         but the auth API it is talking to. */
      credentials: "omit",
      referrerPolicy: "no-referrer"
    });
  }

  function describeSaveFailure(status, payload) {
    var raw = ((payload && (payload.error_code || payload.msg || payload.error_description || payload.error)) || "").toString();
    if (status === 401 || status === 403 || /session|jwt|token/i.test(raw)) {
      return "Your reset link has lapsed before this could be saved. Ask for a new link and choose your password again.";
    }
    if (/same_password|should be different/i.test(raw)) {
      return "That is the password you already have. Choose a different one.";
    }
    if (/weak_password|at least/i.test(raw)) {
      return "That password is too easy to guess. Choose a longer one.";
    }
    return "That password could not be saved. Please try again.";
  }

  el("reveal").addEventListener("click", function () {
    var showing = el("password").type === "text";
    el("password").type = showing ? "password" : "text";
    el("confirmation").type = showing ? "password" : "text";
    el("reveal").textContent = showing ? "Show" : "Hide";
  });

  el("password-form").addEventListener("submit", function (event) {
    event.preventDefault();
    var password = el("password").value;
    var message = function (text, good) {
      el("password-message").className = "message " + (good ? "good" : "bad");
      say("password-message", text);
      show("password-message", true);
    };

    if (password.length < CONFIG.passwordMinLength) {
      message("Use at least " + CONFIG.passwordMinLength + " characters.", false);
      return;
    }
    if (password !== el("confirmation").value) {
      message("Both passwords must match.", false);
      return;
    }
    if (!CONFIG.anonKey) {
      message("This page is not fully set up yet. Please write to tech@iskconchicago.com.", false);
      return;
    }

    el("save").disabled = true;
    say("save", "Saving…");
    authFetch("/auth/v1/user", { password: password }, accessToken)
      .then(function (response) {
        return response.json().catch(function () { return {}; })
          .then(function (payload) { return { ok: response.ok, status: response.status, payload: payload }; });
      })
      .then(function (result) {
        if (!result.ok) {
          el("save").disabled = false;
          say("save", "Save my new password");
          message(describeSaveFailure(result.status, result.payload), false);
          return;
        }
        /* Saved. Replace the form outright rather than leaving a filled-in
           password box on screen next to a success line, and empty the fields
           so the new password is not left sitting in the DOM. */
        el("password").value = "";
        el("confirmation").value = "";
        show("password-form", false);
        mark("check", false);
        say("heading", "Your new password is saved");
        say("lede", "Use it the next time you sign in. Hare Kṛṣṇa.");
        say("note", "Nothing else is needed here. You may close this page.");
        show("note", true);
      })
      .catch(function () {
        el("save").disabled = false;
        say("save", "Save my new password");
        message("The temple could not be reached. Check your connection and try again.", false);
      });
  });

  /* ---------------------------------------------------------------------
   * 5. Asking for a fresh link.
   *
   * The answer is deliberately the same whether or not the address has an
   * account. Saying "no such devotee" would turn this page into a way to test
   * whether somebody is a member of the temple.
   * ------------------------------------------------------------------- */
  el("resend-form").addEventListener("submit", function (event) {
    event.preventDefault();
    var email = el("email").value.trim();
    var kind = el("kind").value;
    var message = function (text, good) {
      el("resend-message").className = "message " + (good ? "good" : "bad");
      say("resend-message", text);
      show("resend-message", true);
    };

    if (!email) { message("Please enter the email address you use here.", false); return; }
    if (!CONFIG.anonKey) {
      message("This page is not fully set up yet. Please write to tech@iskconchicago.com.", false);
      return;
    }

    var back = "?redirect_to=" + encodeURIComponent(CONFIG.pageUrl);
    var path = kind === "signup" ? "/auth/v1/resend" + back
      : kind === "magiclink" ? "/auth/v1/magiclink" + back
      : "/auth/v1/recover" + back;
    var body = kind === "signup" ? { type: "signup", email: email } : { email: email };

    el("send").disabled = true;
    say("send", "Sending…");
    authFetch(path, body, null)
      .then(function (response) {
        el("send").disabled = false;
        say("send", "Send me a fresh link");
        if (response.status === 429) {
          message("A link was asked for very recently. Give it a minute, then try again.", false);
          return;
        }
        message("If that address has an account here, a fresh link is on its way. It may take a minute to arrive.", true);
      })
      .catch(function () {
        el("send").disabled = false;
        say("send", "Send me a fresh link");
        message("The temple could not be reached. Check your connection and try again.", false);
      });
  });

  start();
})();
</script>
</body>
</html>`;
}

Deno.serve((request) => {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response("Method not allowed", { status: 405 });
  }

  const supabaseUrl = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/+$/, "");
  // Publishable/anon only. A service-role key here would be handed to every
  // browser that opens an email link; nothing in this file may ever read one.
  const anonKey = Deno.env.get("AUTH_LINK_ANON_KEY") ??
    Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const appScheme = Deno.env.get("AUTH_LINK_APP_SCHEME") ?? DEFAULT_APP_SCHEME;

  const requested = new URL(request.url);
  // Where a replacement link should come back to: this page, with nothing
  // carried over from the request that is now being replaced.
  const pageUrl = `${requested.origin}${requested.pathname}`;

  const nonce = crypto.randomUUID().replace(/-/g, "");
  const body = html(
    { supabaseUrl, anonKey, appScheme, pageUrl, passwordMinLength: PASSWORD_MIN_LENGTH },
    nonce,
  );

  // connect-src is the Supabase auth origin and nothing else, so no script on
  // this page — ours or one somehow injected — can send a token anywhere,
  // including back to this function. Everything else is denied outright.
  const csp = [
    "default-src 'none'",
    `script-src 'nonce-${nonce}'`,
    `style-src 'nonce-${nonce}' https://fonts.googleapis.com`,
    "font-src https://fonts.gstatic.com",
    "img-src 'self' data:",
    `connect-src ${supabaseUrl || "'none'"}`,
    "form-action 'none'",
    "frame-ancestors 'none'",
    "base-uri 'none'",
  ].join("; ");

  return new Response(request.method === "HEAD" ? null : body, {
    status: 200,
    headers: {
      "content-type": "text/html; charset=utf-8",
      "content-security-policy": csp,
      // The fragment is never sent as a referrer by any browser, but the query
      // string is, and a leaked Referer from this page tells an outside host
      // that this person is mid password reset. Send nothing.
      "referrer-policy": "no-referrer",
      "x-content-type-options": "nosniff",
      "x-frame-options": "DENY",
      // A page that carries a live session must not sit in a shared cache.
      "cache-control": "no-store, max-age=0",
    },
  });
});
