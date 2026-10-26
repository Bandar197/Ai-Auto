// Cloudflare Worker that fronts the AutoMind API running in a Cloudflare Container.
//
// The FastAPI image (backend/Dockerfile) is a normal long-running HTTP server, so it
// runs as a Container, not as a Worker. This Worker forwards every request to the
// container on its port 8000. Cloudflare terminates TLS and provides DNS/WAF/CDN in
// front of it automatically.
//
// Requires the `@cloudflare/containers` helper (see infra/cloudflare/package.json) and
// the container binding in wrangler.jsonc. Docs: https://developers.cloudflare.com/containers/
import { Container, getContainer } from "@cloudflare/containers";

export class ApiContainer extends Container {
  // Must match EXPOSE / uvicorn port in backend/Dockerfile.
  defaultPort = 8000;
  // Scale to zero after idle to save cost; the next request cold-starts it.
  sleepAfter = "15m";
  // Give the app a moment to boot before the first request is forwarded.
  requiredPorts = [8000];
}

export default {
  /**
   * @param {Request} request
   * @param {{ API_CONTAINER: DurableObjectNamespace }} env
   */
  async fetch(request, env) {
    // One shared container instance (id "api"); raise instances/maxInstances in
    // wrangler.jsonc and shard by a key here if you need more throughput.
    return getContainer(env.API_CONTAINER, "api").fetch(request);
  },
};
