// AAP environment badge — issue #54, reworked in #87.
//
// The AAP sign-in page says which environment you are entering (custom_logo,
// badged by utilities/make-env-logo.py). After login that marker is gone: the
// masthead is the stock Red Hat lockup and a wide empty black bar, identical on
// both environments — and after login is when you are actually clicking things.
//
// No gateway setting fixes this. Measured on live AAP 2.6: 44 settings, only
// custom_login_info and custom_logo are branding-related, and custom_logo was
// already applied while the masthead still rendered stock. So this runs in the
// browser instead, and changes nothing on the cluster.
//
// IT ASKS AAP WHICH ENVIRONMENT IT IS. It used to look location.hostname up in
// a generated map built from aap_hostname in each connection.yml, and that map
// went stale every time RHDP handed over a new cluster — silently, labelling
// nothing rather than erroring (#87). The hostname is only a proxy for the
// environment. `target_env` is the environment, it already rides on the job
// templates this repo creates, and assert_target_environment.yml fails a run
// closed if it ever disagrees with the template's limit. So there is no map to
// keep in step and a new RHDP environment is back to being two edits.

(() => {
  "use strict";

  const BADGE_ID = "sales-demos-env-badge";

  // WHY manifest.json MATCHES ALL OF *.dyn.redhatworkshops.io, WHICH LOOKS TOO
  // BROAD. Chrome match patterns allow `*` only as an entire leading subdomain
  // (`*.example.com`) or as the whole host — never inside a hostname label. The
  // obvious `https://aap-aap.apps.cluster-*.dyn.redhatworkshops.io/*` is
  // rejected outright with "Invalid host wildcard", and the extension will not
  // load at all. Do not "tighten" it back to that.
  //
  // So the manifest matches every RHDP host and this narrows it here instead.
  // The AAP gateway Route on this catalog item is always `aap-<namespace>`, so
  // anything else — the OpenShift console, Cockpit, a demo web server — bails
  // before touching the page.
  const AAP_HOST = /^aap-/;

  // Below this width the masthead's own controls crowd the middle. Hide rather
  // than overlap: a badge sitting on top of the nav toggle is worse than none,
  // especially on a shared screen.
  const MIN_WIDTH = 1100;

  // Same-origin: the content script runs ON the AAP page, so this needs no
  // host_permissions and raises no CORS question. page_size is generous enough
  // to hold every template this repo creates in one request.
  const TEMPLATES_URL = "/api/controller/v2/job_templates/?page_size=200";

  // How long to wait between resolve attempts while the environment is still
  // unknown, and how many to make before giving up. Bounded on both ends:
  // attempts stop entirely once resolved, and an unattended sign-in page stops
  // asking after two minutes rather than polling all afternoon. Coming back to
  // the tab resets the budget, so a page left open still turns green when you
  // finally log in.
  const RETRY_MS = 3000;
  const MAX_ATTEMPTS = 40;

  // A hung request must not leave the badge in "pending" forever — that state
  // paints nothing, so an unbounded wait would silently mean no pill at all.
  const TIMEOUT_MS = 8000;

  let colors = null; // colors.json, loaded once
  let resolved = null; // the environment, once known. Sticky — it cannot change
  // under a live page, so one successful resolve is final.
  let status = "pending"; // "pending" | "logged-out" | "unknown"
  let inFlight = false;

  // OVERLAY, NOT DOM SURGERY. This appends one fixed-position element to <body>
  // and never touches AAP's own markup. The masthead is PatternFly with
  // version-prefixed class names (pf-v5-c-masthead__content and friends);
  // anchoring to those means a gateway upgrade silently breaks the badge, or
  // worse, breaks the header. All this needs is that a <header> exists.
  function mastheadBox() {
    const header = document.querySelector("header");
    if (!header) return null;
    const box = header.getBoundingClientRect();
    // A header that is off-screen or collapsed is not the masthead.
    if (box.height < 24 || box.top > 40) return null;
    return box;
  }

  function render(env, box) {
    let badge = document.getElementById(BADGE_ID);
    if (!badge) {
      badge = document.createElement("div");
      badge.id = BADGE_ID;
      document.body.appendChild(badge);
    }

    badge.textContent = env.label;
    Object.assign(badge.style, {
      position: "fixed",
      top: `${box.top + box.height / 2}px`,
      left: "50%",
      transform: "translate(-50%, -50%)",
      zIndex: "2147483000",
      background: env.fill,
      color: env.text,
      font: "600 13px/1 RedHatText, 'Red Hat Text', Overpass, Arial, sans-serif",
      letterSpacing: "0.14em",
      padding: "7px 18px",
      borderRadius: "999px",
      // A light outline so the pill reads against both the dark masthead and
      // AAP's light theme, without needing to detect which is active.
      boxShadow: "0 0 0 1px rgba(255,255,255,0.35)",
      pointerEvents: "none",
      userSelect: "none",
      whiteSpace: "nowrap",
    });
  }

  function remove() {
    const badge = document.getElementById(BADGE_ID);
    if (badge) badge.remove();
  }

  // Returns the environment, or null when AAP answered but nothing identified
  // it. Throws only on a network-level failure, which the caller treats as
  // "unknown" too.
  async function fetchEnv() {
    const abort = new AbortController();
    const timer = setTimeout(() => abort.abort(), TIMEOUT_MS);
    let response;
    try {
      response = await fetch(TEMPLATES_URL, {
        credentials: "same-origin",
        // NEVER RE-SERVE THE LOGGED-OUT ANSWER. Without this the browser can
        // hand back the cached 401 after you have signed in, and the pill never
        // turns green.
        cache: "no-store",
        headers: { Accept: "application/json" },
        signal: abort.signal,
      });
    } finally {
      clearTimeout(timer);
    }

    // TOLD, NOT GUESSED. A 401/403 is AAP stating you are not signed in, which
    // is a different thing from "this cluster is unidentifiable" and deserves a
    // different answer on screen. Keying off the status rather than the URL
    // keeps this from sniffing AAP's routes — the coupling this design avoids.
    if (response.status === 401 || response.status === 403) {
      status = "logged-out";
      return null;
    }
    if (!response.ok) {
      status = "unknown";
      return null;
    }

    const data = await response.json();

    // SCAN FOR THE FIELD, DO NOT QUERY BY TEMPLATE NAME. `?name=Sales Demos -
    // Provision VM` costs the same one request, but that name lives in
    // controller_templates.yml and renaming it there would take the badge
    // silently back to grey — the exact class of mistake #87 removed.
    //
    // AND DO NOT FALL BACK TO `limit`. Both templates also carry
    // limit: "{{ aap_env_name }}", which is tempting when extra_vars yields
    // nothing. Resist it: that is guessing from a second-best source, which is
    // how the hostname map justified itself too.
    const found = new Set();
    for (const template of data.results || []) {
      // extra_vars comes back as a JSON-ENCODED STRING, not an object. Verified
      // against live AAP 2.6; guarded both ways in case that ever changes.
      let vars = template.extra_vars;
      if (typeof vars === "string") {
        if (!vars.trim()) continue;
        try {
          vars = JSON.parse(vars);
        } catch {
          continue; // not JSON is not something to guess from
        }
      }
      const name = vars && vars.target_env;
      if (typeof name === "string" && name) found.add(name);
    }

    // Nothing declared an environment: an AAP this repo has not configured, or
    // one where config.yml has not run yet. More than one: its own templates
    // disagree. Both mean "do not claim to know" rather than picking a winner.
    if (found.size !== 1) {
      status = "unknown";
      return null;
    }

    // An environment name with no colour — a third environment nobody added to
    // env_colors.py — is unknown too. Better a grey pill than an invented hue.
    const name = [...found][0];
    if (!colors.environments[name]) {
      status = "unknown";
      return null;
    }

    status = "resolved";
    return { label: name.toUpperCase(), ...colors.environments[name] };
  }

  function ensureEnv(onResolved) {
    if (resolved || inFlight) return;
    inFlight = true;
    fetchEnv()
      .then((env) => {
        if (env) {
          resolved = env;
          onResolved();
        }
      })
      .catch(() => {
        // Network-level failure. Unknown, never a guessed colour.
        status = "unknown";
      })
      .finally(() => {
        inFlight = false;
      });
  }

  function paint() {
    if (window.innerWidth < MIN_WIDTH) {
      remove();
      return;
    }
    const box = mastheadBox();
    if (!box) {
      // The SPA has not rendered a header yet. Nothing to anchor to.
      remove();
      return;
    }

    if (resolved) {
      render(resolved, box);
      return;
    }

    // NOTHING ON THE SIGN-IN PAGE, and nothing in the moment before the first
    // answer arrives. That page already carries the badged logo, so a grey pill
    // beside a correct green one would contradict it — worse than staying out
    // of the way. This is also why "pending" paints nothing rather than
    // flashing grey and then turning green.
    if (status === "logged-out" || status === "pending") {
      remove();
      return;
    }

    // Signed in, AAP answered, and the environment could not be identified.
    // THAT is what the neutral pill is for. It is not a fallback: a cluster
    // nobody has recorded is exactly when you are most likely to act on the
    // wrong one.
    render(colors.unknown, box);
  }

  if (!AAP_HOST.test(location.hostname)) return;

  fetch(chrome.runtime.getURL("colors.json"))
    .then((r) => r.json())
    .then((loaded) => {
      colors = loaded;

      const update = () => {
        ensureEnv(update);
        paint();
      };
      update();

      // AAP is a single-page app: route changes re-render the body, and the
      // theme toggle re-renders the masthead. Re-assert on both rather than
      // painting once and hoping.
      new MutationObserver(update).observe(document.body, {
        childList: true,
        subtree: false,
      });
      window.addEventListener("resize", update);
      window.addEventListener("popstate", update);

      // Signing in does not reliably mutate a direct child of <body>, so the
      // observer alone can leave the pill missing until you click something.
      // This is the only timer here, and it is bounded twice over: it stops the
      // moment the environment is known, and it gives up after MAX_ATTEMPTS so
      // a sign-in page left open does not poll AAP all afternoon.
      let poll = null;
      const startPolling = () => {
        if (poll || resolved) return;
        let attempts = 0;
        poll = setInterval(() => {
          if (resolved || ++attempts > MAX_ATTEMPTS) {
            clearInterval(poll);
            poll = null;
            return;
          }
          update();
        }, RETRY_MS);
      };
      startPolling();

      // Coming back to the tab restarts a budget that has run out, so a page
      // left open for hours still turns green when you finally log in.
      document.addEventListener("visibilitychange", () => {
        if (document.visibilityState !== "visible") return;
        update();
        startPolling();
      });
    })
    .catch((err) => console.error("[sales.demos] env badge failed:", err));
})();
