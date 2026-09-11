// Cross-origin environment resolver — issue #477.
//
// AO pages cannot same-origin-fetch AAP's job template API because they are on
// a different Route (ao-automation-orchestrator vs aap-aap), which is a
// different origin. The content script sends the AAP origin here and the
// service worker makes the request with host_permissions, which includes the
// AAP session cookie — valid because AO and AAP share SSO.

(() => {
  "use strict";

  const TEMPLATES_PATH = "/api/controller/v2/job_templates/?page_size=200";
  const TIMEOUT_MS = 8000;

  chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
    if (msg.type !== "resolve-env") return false;

    resolveEnv(msg.aapOrigin)
      .then(sendResponse)
      .catch(() => sendResponse({ status: "error" }));

    // true = will respond asynchronously
    return true;
  });

  async function resolveEnv(aapOrigin) {
    const url = `${aapOrigin}${TEMPLATES_PATH}`;
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
    } finally {
      clearTimeout(timer);
    }

    if (response.status === 401 || response.status === 403) {
      return { status: "logged-out" };
    }
    if (!response.ok) {
      return { status: "unknown" };
    }

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

    if (found.size !== 1) {
      return { status: "unknown" };
    }

    return { status: "resolved", env: [...found][0] };
  }
})();
