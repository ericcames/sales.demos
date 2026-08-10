// AAP environment badge — issue #54.
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

  function paint(config) {
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
    // IT ALSO PAINTS ON THE SIGN-IN PAGE, which has a header of its own. That
    // was not the goal — the sign-in page already carries the badged logo — but
    // it is left alone on purpose: it is redundant rather than wrong, and it
    // doubles as confirmation the extension is loaded before you log in.
    // Suppressing it would mean sniffing the route, which is exactly the kind
    // of coupling to AAP's internals this design avoids.
    // An RHDP AAP host that is not in either connection.yml gets the neutral
    // pill. That is the point, not a fallback: a freshly built environment
    // nobody has recorded yet is exactly when you are most likely to act on the
    // wrong cluster.
    const env = config.environments[location.hostname] || config.unknown;
    render(env, box);
  }

  if (!AAP_HOST.test(location.hostname)) return;

  fetch(chrome.runtime.getURL("envs.json"))
    .then((r) => r.json())
    .then((config) => {
      const update = () => paint(config);
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
    })
    .catch((err) => console.error("[sales.demos] env badge failed:", err));
})();
