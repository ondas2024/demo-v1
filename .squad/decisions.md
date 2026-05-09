# Squad Decisions

## Active Decisions

### Architecture Decisions — Azure Arc Demo

> Author: Ripley (Lead/Architect)
> Date: 2026-05-09
> Status: Proposed
> Scope: Full demo architecture

**Context:** Demo showing how Azure Arc enables cloud-managed deployments to on-prem Kubernetes. Focused, reliable, ~5 minute on-stage presentation.

**Decisions:**
1. **K3s as on-prem cluster** — Single-node K3s simulates on-prem infrastructure (installs in 30s, real Kubernetes, no enterprise overhead)
2. **Flux v2 via Arc extension** — Arc-native GitOps engine, visible in Portal, manageable via az CLI (not ArgoCD)
3. **Single monorepo** — App source in src/, GitOps in gitops/, CI in .github/workflows/ (focused demo flow)
4. **Node.js Express demo app** — Fast builds (~10s), tiny images (~50MB alpine), status page with banner/version/hostname
5. **ghcr.io for images** — Free, no Azure setup needed, keeps Arc as focus (not ACR)
6. **Raw YAML + Kustomize** — Audience sees exact deployment, Kustomize Flux-native and readable (not Helm)
7. **CI updates manifests directly** — Pipeline writes new image tag to deployment.yaml and commits to main (transparent, not Flux Image Automation)
8. **Strict scope** — One cluster, one app, one environment (code push → GitOps → Arc → on-prem, focused message)

**Impact:** Defines work for Holden (app), Naomi (pipeline + cluster setup), Clarissa (docs). Full architecture at docs/architecture.md.

## Infrastructure & Deployment Decisions — Azure Arc Demo

> Author: Naomi (DevOps / Platform Engineer)
> Date: 2026-05-09
> Status: Active
> Scope: Azure Arc demo infrastructure-as-code

### Decision 1: NodePort 30080 specifically

**What:** The Kubernetes Service uses `nodePort: 30080` — a fixed, explicit value rather than letting Kubernetes assign a random port from the NodePort range (30000–32767).

**Why 30080:**
- Memorable and typeable during a live demo (`http://<node-ip>:30080` is fast to say on stage)
- Avoids collision with common system and development ports: 80 (HTTP), 443 (HTTPS), 8080 (common dev), 8443 (common dev TLS)
- Sits cleanly in the NodePort range without being the first one (30000) which can feel arbitrary
- The presenter bookmarks the URL before the demo. If the port were randomly assigned, a pod restart would break the bookmark because Kubernetes re-assigns random NodePort values on Service recreate. A fixed value survives teardown and rebuild.

**Alternative considered:** LoadBalancer type. Rejected because a single-node K3s cluster on a local VM won't have a cloud LoadBalancer controller, so the Service would stay in `<pending>` state — confusing on stage.

### Decision 2: `[skip ci]` in the manifest update commit message

**What:** The CI workflow's final commit message is `ci: update image tag to ${TAG} [skip ci]`.

**Why it's CRITICAL:**
GitHub Actions suppresses workflow triggers on commits containing `[skip ci]` or `[ci skip]` in the message. Without this tag, the flow becomes an infinite loop:

```
developer push
  → CI builds image + updates manifest
    → manifest commit triggers CI again
      → CI builds image (same SHA, nothing changes) + updates manifest
        → manifest commit triggers CI again
          → ... forever
```

Even if the second run produces no net change, it still consumes Actions minutes, can exhaust API rate limits, and creates noise in the commit history and Actions tab. In a live demo environment, a runaway workflow loop is catastrophic.

The `[skip ci]` convention is supported by GitHub Actions natively — no plugin or configuration required. It is the correct, standard mechanism for this pattern.

**Why not a path filter (`paths-ignore: ['gitops/**']`)?**
Path filters would work but are fragile: if a future commit touches both `src/` and `gitops/` (e.g., a refactor that also documents a GitOps change), the CI would run and then commit back to `gitops/`, triggering CI again. `[skip ci]` is intent-based and unambiguous regardless of which files changed.

### Decision 3: Environment variables instead of hardcoded values in setup/teardown scripts

**What:** `setup-arc.sh` and `teardown.sh` require four environment variables (`RESOURCE_GROUP`, `CLUSTER_NAME`, `LOCATION`, `REPO_URL`) instead of hardcoding values like `rg-arc-demo` directly in the script body.

**Why:**

1. **Reusability across contexts.** The same script runs correctly on the presenter's laptop, in a CI teardown job, or in a re-run with a different resource group name — without editing the file. Editing scripts before running them is a source of errors and "it worked on my machine" problems.

2. **Prevents accidental org-specific commits.** If we hardcoded the GitHub org name (`REPO_URL=https://github.com/contoso/demo-v1`) into the script, anyone forking or copying the repo would inherit the wrong value — and might not notice until the script silently connects to the wrong repo. Env vars make the substitution explicit and visible.

3. **Keeps secrets out of source code.** If we ever need to inject a service principal credential or tenant ID through the same pattern, env vars are the natural, safe mechanism. Hardcoded values in shell scripts have a history of ending up in git history even after removal.

4. **Infrastructure as code principle.** A script that requires you to edit it before running it is not reproducible infrastructure — it's a template. Env vars are the correct abstraction for "things that vary per environment."

**Validation:** Both scripts use `${VAR:?'error message'}` syntax, which causes the script to exit immediately with a clear error if a required variable is unset. This prevents the scripts from running in an undefined state.

## Application & Deployment Decisions

> Author: Holden (Backend Developer)
> Date: 2026-05-09
> Status: Active

### Decision 1: Inline HTML instead of a template engine

**Chosen:** Inline HTML string in `server.js` via template literals.

**Rationale:** The demo app has exactly one page. Pulling in a template engine (EJS, Handlebars, Pug) adds a dependency, a `views/` directory, and a concept to explain — for zero gain. Template literals give us dynamic values (`${BANNER_MESSAGE}`, `${APP_VERSION}`, `${hostname}`) with no additional packages. The HTML is 60 lines and sits right next to the route handler. On stage, the presenter can point to the file and the whole thing is visible in one scroll. Simple is right here.

### Decision 2: Single-stage Dockerfile (no multi-stage build)

**Chosen:** Single `FROM node:20-alpine` stage.

**Rationale:** Multi-stage builds exist to separate build-time dependencies from runtime. For a Node.js app with no compiled assets, there's nothing to separate. `npm ci --production` already excludes dev dependencies. A multi-stage Dockerfile would add 5+ lines and a concept (build stage vs. runtime stage) for exactly no reduction in image size. Demo pacing matters — this image builds in ~10 seconds on a warm cache. That's the right number. If someone asks "why no multi-stage?" the answer fits in one sentence.

### Decision 3: What `/health` returns and why

**Returns:**
```json
{
  "status": "ok",
  "version": "abc1234",
  "timestamp": "2026-05-09T05:36:47.920Z"
}
```

**Rationale:**
- `status: "ok"` — Kubernetes liveness/readiness probes key off this. It's the minimum required field.
- `version` — Injected from `APP_VERSION` env var (set to Git SHA by CI). Lets the presenter prove which version is running without opening the browser: `curl /health | jq .version`. Also proves the rollout happened — the SHA changes on every push.
- `timestamp` — Shows when the response was generated, not when the pod started. Useful for confirming the pod is live and not cached. Quick sanity check during demo.

No pod name, no uptime, no memory stats. Those belong in a monitoring dashboard. The health endpoint tells you one thing: is it up, and which version is it?

## Documentation & Demo Script Decisions

> Author: Clarissa (DevRel/Docs)
> Date: 2026-05-09
> Status: Active

### Decision 1: Demo Script — Recovery Paths at Every Step

**Topic:** Why Every Step in the Demo Script Includes an "If It Goes Wrong" Recovery Path

**Decision Rationale**

**Every step in `docs/demo-script.md` includes a recovery instruction** under "If it goes wrong:" rather than assuming the happy path.

#### Why This Matters

1. **Live demos are unpredictable.** Network latency, async operations, API delays — any step can stall or fail. A presenter who knows the recovery path *before* it breaks is confident and keeps audience trust. A presenter who scrambles to debug on stage loses the story.

2. **Flux reconciliation is async.** The core of this demo is watching a Kubernetes GitOps engine automatically deploy code. Pods take time to pull images, controllers take time to process manifests. Without explicit recovery guidance, a presenter might assume failure when it's just "still processing."

3. **Token/permission issues are silent until they break.** The CI workflow won't immediately show a permission error — it will run, seem to succeed, then fail silently. By building recovery logic into every step, we make these failures *visible and fixable on stage*.

4. **The audience expects confidence.** If a presenter has to visibly troubleshoot, they should do it *quickly* and *with a clear path forward*. "I know exactly what to check here" sounds better than "let me see what went wrong."

#### Structure

Each step follows this pattern:

```
**You do:** [Exact action]
**Audience sees:** [Visual confirmation]
**Say:** [Talking point]
**If it goes wrong:** [One-line recovery or diagnostic]
```

The "If it goes wrong" line is *short* — not a full troubleshooting essay. It points to the right place (Portal, logs, script) and gives the presenter a next step within ~10 seconds. Full diagnostics are in `docs/troubleshooting.md`.

#### Examples

- **Step 3 (Show Flux):** "If compliance state shows 'Error,' hover over it to see the error message. Verify GitHub token permissions."
- **Step 8 (Watch Flux reconcile):** "If no new pods appear after 2 minutes, check Flux compliance state in Portal for errors."
- **Step 9 (Browser refresh):** "If the banner didn't change, wait a few more seconds and refresh again. Flux polls every 60 seconds."

#### Impact

Presenters using this script will:
- Recover from ~80% of common failures without breaking demo flow
- Know exactly where to look for errors
- Maintain audience trust by seeming prepared
- Have a clear handoff to full troubleshooting if needed (point to `docs/troubleshooting.md`)

This approach turns "it might break" into "when it gets slow, here's what to check."

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction
