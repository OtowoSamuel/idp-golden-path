import { mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { join, relative, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import nunjucks from 'nunjucks';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const skeletonDir = join(root, 'templates', 'service-node', 'skeleton');
const outDir = join(root, 'render-output', 'payments-api');

const values = {
  service_name: 'payments-api',
  description: 'Handles payment processing for the storefront',
  owner: 'group:default/payments',
  destination: { host: 'github.com', owner: 'acme', repo: 'payments-api' },
  team_label: 'payments',
};

const env = new nunjucks.Environment(null, {
  autoescape: false,
  throwOnUndefined: true,
  tags: { variableStart: '${{', variableEnd: '}}' },
});
env.addFilter('dump', (v) => JSON.stringify(v));

async function* walk(dir) {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const p = join(dir, entry.name);
    if (entry.isDirectory()) yield* walk(p);
    else yield p;
  }
}

const errors = [];
const rendered = [];

await rm(outDir, { recursive: true, force: true });
await mkdir(outDir, { recursive: true });

for await (const file of walk(skeletonDir)) {
  const rel = relative(skeletonDir, file);
  const target = join(outDir, rel);
  await mkdir(dirname(target), { recursive: true });

  const raw = await readFile(file, 'utf8');
  let output;
  try {
    output = env.renderString(raw, { values });
  } catch (e) {
    errors.push(`${rel}: render error: ${e.message}`);
    continue;
  }
  await writeFile(target, output);
  rendered.push({ rel, output });
}

for (const { rel, output } of rendered) {
  if (/\$\{\{\s*values\./.test(output)) {
    errors.push(`${rel}: unresolved \${{ values.* }} placeholder remains after render`);
  }
  if (/\{\%/.test(output) && !rel.endsWith('ci.yaml')) {
    errors.push(`${rel}: unresolved nunjucks block tag remains`);
  }
}

const pkg = rendered.find((r) => r.rel === 'package.json');
if (pkg) {
  try {
    const parsed = JSON.parse(pkg.output);
    if (parsed.name !== values.service_name) {
      errors.push(`package.json: name is ${parsed.name}, expected ${values.service_name}`);
    }
  } catch (e) {
    errors.push(`package.json: invalid JSON after render: ${e.message}`);
  }
}

const ci = rendered.find((r) => r.rel === '.github/workflows/ci.yaml');
if (ci) {
  if (!ci.output.includes('${{ github.actor }}') || !ci.output.includes('${{ secrets.GITHUB_TOKEN }}')) {
    errors.push('ci.yaml: GitHub Actions expressions were eaten by templating (raw block broken)');
  }
  if (!ci.output.includes('cosign sign')) {
    errors.push('ci.yaml: cosign signing step missing');
  }
}

const lock = rendered.find((r) => r.rel === 'package-lock.json');
if (lock) {
  try {
    const parsed = JSON.parse(lock.output);
    if (parsed.name !== values.service_name) {
      errors.push(`package-lock.json: root name is ${parsed.name}, expected ${values.service_name}`);
    }
    if (parsed.packages?.['']?.name !== values.service_name) {
      errors.push(`package-lock.json: packages[""].name did not render`);
    }
    if (parsed.lockfileVersion !== 3) {
      errors.push(`package-lock.json: expected lockfileVersion 3`);
    }
  } catch (e) {
    errors.push(`package-lock.json: invalid JSON after render: ${e.message}`);
  }
} else {
  errors.push('package-lock.json: missing from skeleton (required for npm ci)');
}

const catalog = rendered.find((r) => r.rel === 'catalog-info.yaml');
if (catalog && !catalog.output.includes('github.com/project-slug: acme/payments-api')) {
  errors.push('catalog-info.yaml: project-slug not rendered correctly');
}

if (errors.length) {
  console.error('RENDER TEST FAILED:');
  for (const e of errors) console.error(`  - ${e}`);
  process.exit(1);
}
const { execSync } = await import('node:child_process');
const steps = [
  ['npm ci', 'lockfile install'],
  ['npm run lint', 'eslint on rendered output'],
  ['npm test', 'unit tests on rendered output'],
];
for (const [cmd, label] of steps) {
  try {
    execSync(cmd, { cwd: outDir, stdio: 'pipe' });
    console.log(`${label}: OK`);
  } catch (e) {
    const out = `${e.stdout ?? ''}${e.stderr ?? ''}`.trim().split('\n').slice(-15).join('\n');
    console.error(`RENDER TEST FAILED at "${cmd}" (${label}):`);
    console.error(out);
    process.exit(1);
  }
}
console.log(`render test passed: ${rendered.length} files rendered, lint + unit tests green on output`);
