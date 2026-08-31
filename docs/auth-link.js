/**
 * The auth landing page's behaviour.
 *
 * This began life inside supabase/functions/auth-link/index.ts, which built the
 * page per request and could therefore give the <script> a fresh nonce. Supabase
 * will not serve HTML from an edge function — the platform rewrites the
 * content-type to text/plain and replaces the function's CSP with a bare
 * `sandbox`, as an anti-phishing measure on supabase.co — so the page is static
 * on GitHub Pages instead, and a static file cannot rotate a nonce. The script
 * therefore lives here, in a file of its own, covered by `script-src 'self'`.
 * It must never move back inline: 'unsafe-inline' on a page holding a live
 * access token is not a trade worth making.
 *
 * Everything below is the edge function's logic unchanged. The fragment is read
 * and destroyed before anything renders, the tokens stay in this closure, and
 * the only origin they are ever sent to is Supabase's auth API.
 */
(function () {
  "use strict";

  /* Baked in rather than injected, because GitHub Pages has no environment.
   *
   * Both values are public: the same project URL and publishable key are
   * compiled into the app itself. The service-role key is not read here and
   * must never be added — this file is handed to every browser that opens an
   * email link. `pageUrl` is where a replacement link comes back to, so it must
   * stay identical to `AUTH_EMAIL_PAGE_URL` in src/services/auth.ts and to what
   * is allow-listed under Authentication -> URL Configuration. */
  var CONFIG = {
    supabaseUrl: "https://gkkeebhdavavizcvknwy.supabase.co",
    anonKey: "sb_publishable_XMScAfq8QC0Ut7b1pan91A_aDgiH6MJ",
    appScheme: "iskconchicago",
    pageUrl: "https://tanmayypramanick.github.io/iskcon-chicago-community-app/",
    passwordMinLength: 6
  };

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
    /* What `X-Frame-Options: DENY` used to do, done in script because it can no
       longer be done in a header. `frame-ancestors` is the CSP replacement, but
       the spec has browsers ignore it when the policy arrives in a <meta> tag,
       so a static host cannot express it at all. The header was never the
       point: the point is that nobody puts this password box behind a page of
       their own. Refusing to render inside a frame says the same thing. */
    if (window.top !== window.self) {
      mark("alert", true);
      say("heading", "This page cannot be shown here");
      say("lede", "Open the link from the temple's email in a browser tab of its own.");
      return;
    }

    if (errorText || errorCode) {
      var reason = explainFailure();
      renderProblem(
        reason.heading,
        reason.lede,
        /* Verbatim, escaped by textContent, because a devotee reporting this to
           the temple should be able to say what it said. */
        errorText ? errorText.replace(/\+/g, " ") : "",
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
      say("lede", "Your link has signed you in. Choose a password so you can sign in normally next time — at least " + CONFIG.passwordMinLength + " characters.");
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
