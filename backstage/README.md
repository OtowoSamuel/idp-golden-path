# Running Backstage locally (demo mode)

You do **not** vendor Backstage into this repo. You run it as an app that
points at the templates and catalog files here.

## One-time setup (~10 min)

```bash
npx @backstage/create-app@latest
# choose a directory outside this repo, e.g. ../backstage-app
```

## Wire this repo in

1. Copy the fragments from `app-config.fragment.yaml` into the generated
   `app-config.yaml` (they are annotated with what each block does).
2. Set `GITHUB_TOKEN` in your shell (needed by the scaffolder to create repos):

   ```bash
   export GITHUB_TOKEN=ghp_xxx   # repo, workflow, write:packages scopes
   ```

3. Start it:

   ```bash
   yarn dev
   # UI: http://localhost:3000  |  API: http://localhost:7007
   ```

## Verify the template is registered

- Open **Create → Create a new component** — you should see
  **"Create Node.js Service"**.
- If it's missing: **Catalog → Locations → refresh** the location entity
  (Backstage caches location results).

## Demo flow (the 15-minute pitch)

1. Click **Create a new component → Create Node.js Service**.
2. Fill: name (`payments-api`), description, owner (pick `payments`),
   repo location (your org + repo name).
3. Watch the four steps run: render → create repo → register.
4. Open the new GitHub repo: workflow, Dockerfile, kustomize, catalog-info
   are all there.
5. Push to `main` → CI runs lint/test/build/**sign** → image lands in GHCR,
   signed with Cosign.
6. Back in Backstage: the component shows owner, pipeline link, repo link.

## Prod shape (when you need it)

- k3s on a $5 VM, or kind/k3d for a laptop demo.
- Swap `auth.providers.guest` for GitHub auth.
- Point catalog locations at the raw.githubusercontent.com URL form.
- Tunnel with Cloudflare Tunnel / ngrok for a shareable demo URL.
