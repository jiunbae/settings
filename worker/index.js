/**
 * Cloudflare Worker — settings.jiun.dev
 *
 * Proxies the bootstrap installer from GitHub raw content.
 *
 * Usage:
 *   curl -LsSf https://settings.jiun.dev | sh
 *   curl -LsSf https://settings.jiun.dev | bash -s -- --all
 *   curl -LsSf https://settings.jiun.dev | bash -s -- zsh nvim tmux
 *
 * Routes:
 *   GET /              → bootstrap.sh (installer script)
 *   GET /install.sh    → install.sh
 *   GET /bootstrap.sh  → bootstrap.sh
 *   GET /<path>        → raw file from repo
 */

const REPO = "jiunbae/settings";
const BRANCH = "master";
const RAW_BASE = `https://raw.githubusercontent.com/${REPO}/${BRANCH}`;

// Cache TTL in seconds (5 minutes — balance between freshness and speed)
const CACHE_TTL = 300;

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname;

    // Route: root → bootstrap.sh
    let targetPath;
    if (path === "/" || path === "") {
      targetPath = "/bootstrap.sh";
    } else {
      targetPath = path;
    }

    const rawUrl = `${RAW_BASE}${targetPath}`;

    try {
      const resp = await fetch(rawUrl, {
        cf: { cacheTtl: CACHE_TTL, cacheEverything: true },
      });

      if (!resp.ok) {
        if (resp.status === 404) {
          return new Response("Not found\n", { status: 404 });
        }
        return new Response(`Upstream error: ${resp.status}\n`, {
          status: resp.status,
        });
      }

      return new Response(resp.body, {
        status: 200,
        headers: {
          "content-type": "text/plain; charset=utf-8",
          "cache-control": `public, max-age=${CACHE_TTL}`,
          "x-repo": `github.com/${REPO}`,
        },
      });
    } catch (err) {
      return new Response(`Error: ${err.message}\n`, { status: 502 });
    }
  },
};
