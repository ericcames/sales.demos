// AAP environment badge — issue #54, reworked in #87, extended to AO in #477.
//
// The AAP sign-in page says which environment you are entering (custom_logo,
// badged by utilities/make-env-logo.py). After login that marker is gone: the
// masthead is the stock Red Hat lockup and a wide empty black bar, identical on
// both environments — and after login is when you are actually clicking things.
// AO has no branding at all (#426), so this is the only environment indicator
// on every AO page.
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
//
// ON AO, the environment comes from two paths, tried in order:
//
// 1. chrome.storage.local — the AAP content script caches it when it
//    resolves. AAP and AO share the same cluster domain (everything after
//    `.apps.`), so the cache key is identical.
//
// 2. Cross-origin fetch to AAP — if the cache is empty (common after SSO
//    login, where the redirect never gives the AAP content script a chance
//    to fetch templates while authenticated), the AO content script asks
//    AAP directly. host_permissions covers the domain, and AAP's session
//    cookie (SameSite=None on the OpenShift Route) carries authentication.
//    If the cookie does not carry (SameSite policy, third-party cookie
//    blocking), this returns 401 and the cache-polling fallback continues.
//
// A storage.onChanged listener picks up a cache write from any other tab
// the moment it happens.

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
  const AO_HOST = /^ao-automation-orchestrator\b/;

  // Below this width the masthead's own controls crowd the middle. Hide rather
  // than overlap: a badge sitting on top of the nav toggle is worse than none,
  // especially on a shared screen.
  const MIN_WIDTH = 1100;

  // On AAP this is same-origin. On AO it is used cross-origin (prefixed
  // with the AAP hostname); host_permissions covers the domain.
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

  // AO's post-login app shell uses PatternFly v6's Compass layout. The
  // Compass main-header renders as a <div>, not a <header> — so
  // querySelector("header") misses it entirely. The login page still uses
  // <header> (via PF's LoginHeader), so try both.
  function aoMastheadBox() {
    const el =
      document.querySelector("header") ||
      document.querySelector("[class*='compass__main-header']");
    if (!el) return null;
    const box = el.getBoundingClientRect();
    if (box.height === 0) return null;
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
      top: `${Math.min(box.top + box.height / 2, 24)}px`,
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
    // Cache for AO pages on the same cluster.
    const domain = clusterDomain();
    if (domain) chrome.storage.local.set({ ["env:" + domain]: name });
    return { label: name.toUpperCase(), ...colors.environments[name] };
  }

  // AAP and AO are different Routes on the same cluster. The cluster domain
  // (everything after `.apps.`) is the shared key.
  function clusterDomain() {
    const idx = location.hostname.indexOf(".apps.");
    if (idx < 0) return null;
    return location.hostname.slice(idx + 5); // skip ".apps."
  }

  // On AO, read the environment from chrome.storage.local. The AAP content
  // script writes it when it resolves — same cluster domain, same key.
  async function fetchEnvFromCache() {
    const domain = clusterDomain();
    if (!domain) {
      status = "unknown";
      return null;
    }
    const key = "env:" + domain;
    const result = await chrome.storage.local.get(key);
    const name = result[key];
    if (!name) {
      // AAP hasn't cached an environment for this cluster yet. The poll timer
      // and storage.onChanged listener will pick it up when it does.
      status = "pending";
      return null;
    }
    if (!colors.environments[name]) {
      status = "unknown";
      return null;
    }
    status = "resolved";
    return { label: name.toUpperCase(), ...colors.environments[name] };
  }

  const onAO = AO_HOST.test(location.hostname);

  // On AO, if the cache is empty, try the AAP templates API directly.
  // The SSO login flow (AO → AAP login → redirect back to AO) never
  // gives the AAP content script a chance to fetch while authenticated,
  // so the cache stays empty. This cross-origin fetch fills the gap.
  let aapFetchAttempted = false;
  async function fetchEnvFromAAP() {
    const domain = clusterDomain();
    if (!domain) return null;
    const url =
      `https://aap-aap.apps.${domain}${TEMPLATES_URL}`;
    const abort = new AbortController();
    const timer = setTimeout(() => abort.abort(), TIMEOUT_MS);
    let response;
    try {
      response = await fetch(url, {
        credentials: "include",
        cache: "no-store",
        headers: { Accept: "application/json" },
        signal: abort.signal,
      });
    } catch {
      return null;
    } finally {
      clearTimeout(timer);
    }

    if (response.status === 401 || response.status === 403) return null;
    if (!response.ok) return null;

    const data = await response.json();
    const found = new Set();
    for (const template of data.results || []) {
      let vars = template.extra_vars;
      if (typeof vars === "string") {
        if (!vars.trim()) continue;
        try {
          vars = JSON.parse(vars);
        } catch {
          continue;
        }
      }
      const name = vars && vars.target_env;
      if (typeof name === "string" && name) found.add(name);
    }
    if (found.size !== 1) return null;
    const name = [...found][0];
    if (!colors.environments[name]) return null;

    status = "resolved";
    if (domain) chrome.storage.local.set({ ["env:" + domain]: name });
    return { label: name.toUpperCase(), ...colors.environments[name] };
  }

  async function fetchEnvForAO() {
    const cached = await fetchEnvFromCache();
    if (cached) return cached;
    if (aapFetchAttempted) return null;
    aapFetchAttempted = true;
    try {
      return await fetchEnvFromAAP();
    } catch {
      return null;
    }
  }

  function ensureEnv(onResolved) {
    if (resolved || inFlight) return;
    inFlight = true;
    const resolver = onAO ? fetchEnvForAO : fetchEnv;
    resolver()
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
    // mastheadBox has strict dimension checks for AAP's wide masthead.
    // AO's compact header may fail those — fall back to aoMastheadBox.
    const box = mastheadBox() || (onAO ? aoMastheadBox() : null);
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

  if (!AAP_HOST.test(location.hostname) && !onAO) return;

  fetch(chrome.runtime.getURL("colors.json"))
    .then((r) => r.json())
    .then((loaded) => {
      colors = loaded;

      const update = () => {
        ensureEnv(update);
        paint();
      };
      update();

      // Both AAP and AO are single-page apps. AAP route changes swap direct
      // children of <body>; AO renders its header deep inside an existing root
      // div. subtree: true catches both. The 150ms trailing-edge debounce
      // coalesces a React render burst into one update() after the DOM settles.
      let debounceTimer = null;
      new MutationObserver(() => {
        if (debounceTimer) return;
        debounceTimer = setTimeout(() => {
          debounceTimer = null;
          update();
        }, 150);
      }).observe(document.body, {
        childList: true,
        subtree: true,
      });
      window.addEventListener("resize", update);
      window.addEventListener("popstate", update);

      // Belt-and-suspenders with the observer: retries paint() on a timer in
      // case a mutation is missed. Stops when the badge is actually in the DOM
      // (not just when the environment is resolved — the header may not exist
      // yet), and gives up after MAX_ATTEMPTS.
      let poll = null;
      const startPolling = () => {
        if (poll || (resolved && document.getElementById(BADGE_ID))) return;
        let attempts = 0;
        poll = setInterval(() => {
          if ((resolved && document.getElementById(BADGE_ID)) || ++attempts > MAX_ATTEMPTS) {
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

      // On AO, react immediately when AAP caches the environment in another
      // tab — no need to wait for the next poll tick.
      if (onAO) {
        const domain = clusterDomain();
        if (domain) {
          chrome.storage.onChanged.addListener((changes, area) => {
            if (resolved || area !== "local") return;
            if (changes["env:" + domain]) update();
          });
        }
      }
    })
    .catch((err) => console.error("[sales.demos] env badge failed:", err));
})();
