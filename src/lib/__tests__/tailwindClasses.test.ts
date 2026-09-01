/**
 * Every className in the app must resolve to a real utility.
 *
 * NativeWind silently ignores a class it does not recognise, and TypeScript
 * cannot see inside a string, so a typo like `textegg-stoneMuted` — which this
 * app shipped once — costs nothing at build time and renders unstyled text at
 * runtime. Nothing else in the toolchain catches it.
 *
 * So this compiles the real Tailwind against the real theme — the real
 * design-tokens.json colours, spacing and radii — and asserts that every class
 * the source uses came out the other side.
 */
import { execFileSync } from "child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";

const REPO_ROOT = join(__dirname, "..", "..", "..");

/** Class-shaped candidates Tailwind's extractor produces that are not classes. */
function isPlausibleClass(candidate: string): boolean {
  // Prose inside comments, CSS in the HTML export templates, and the bare
  // prefixes the extractor splits off arbitrary values like `text-[26px]`.
  if (!/^[a-z]/.test(candidate)) return false;
  if (candidate.includes(":") || candidate.includes(";")) return false;
  if (candidate.endsWith("-")) return false;
  return /^[a-z0-9[\]/.@%#()-]+$/i.test(candidate);
}

/**
 * Pull class tokens out of `className` / `contentContainerClassName` values
 * only.
 *
 * Tailwind's own whole-file extractor is tempting, but it also yields every
 * identifier in the file — `supabase.auth`, `queryClient.clear` — which are
 * indistinguishable from a misspelt class once they reach the diff. Scoping to
 * the attribute is what makes a failure here mean something.
 */
function extractClassTokens(source: string): string[] {
  const tokens: string[] = [];
  const attribute =
    /(?:className|contentContainerClassName)\s*=\s*\{?[\s\S]{0,4}?(?:"([^"]*)"|'([^']*)'|`([^`]*)`)/g;
  let match: RegExpExecArray | null;
  while ((match = attribute.exec(source))) {
    const value = (match[1] ?? match[2] ?? match[3] ?? "").replace(
      /\$\{[^}]*\}/g,
      " ",
    );
    tokens.push(...value.split(/\s+/).filter(Boolean));
  }
  // Ternaries and helper calls: every quoted string inside a className={...}
  // block, so `cond ? "bg-a" : "bg-b"` is covered too.
  const block =
    /(?:className|contentContainerClassName)\s*=\s*\{([\s\S]*?)\}\s*(?:\n|\/?>|[a-zA-Z])/g;
  while ((match = block.exec(source))) {
    const strings = /(?:"([^"]*)"|'([^']*)'|`([^`]*)`)/g;
    let inner: RegExpExecArray | null;
    while ((inner = strings.exec(match[1]))) {
      const value = (inner[1] ?? inner[2] ?? inner[3] ?? "").replace(
        /\$\{[^}]*\}/g,
        " ",
      );
      if (!/[a-z]/.test(value)) continue;
      tokens.push(...value.split(/\s+/).filter(Boolean));
    }
  }
  return tokens;
}

function classNamesUsedInSource(): Map<string, string> {
  const files = execFileSync(
    "find",
    [
      join(REPO_ROOT, "src"),
      join(REPO_ROOT, "App.tsx"),
      "-name",
      "*.tsx",
      "-not",
      "-path",
      "*/__tests__/*",
    ],
    { encoding: "utf8" },
  )
    .split("\n")
    .filter(Boolean);

  // candidate -> the first file it was seen in, so a failure names a location.
  const found = new Map<string, string>();
  for (const file of files) {
    for (const candidate of extractClassTokens(readFileSync(file, "utf8"))) {
      if (!found.has(candidate)) found.set(candidate, file);
    }
  }
  return found;
}

function classNamesTailwindGenerates(candidates: string[]): Set<string> {
  const dir = mkdtempSync(join(tmpdir(), "iskcon-tw-"));
  const probe = join(dir, "probe.html");
  const config = join(dir, "tailwind.config.js");
  const input = join(dir, "in.css");
  const output = join(dir, "out.css");

  writeFileSync(probe, `<div class="${candidates.join(" ")}"></div>`);
  writeFileSync(
    config,
    `const base = require(${JSON.stringify(join(REPO_ROOT, "tailwind.config.js"))});\n` +
      `module.exports = { ...base, content: [${JSON.stringify(probe)}], corePlugins: { preflight: false } };\n`,
  );
  writeFileSync(input, "@tailwind utilities;\n");

  execFileSync(
    join(REPO_ROOT, "node_modules/.bin/tailwindcss"),
    ["-c", config, "-i", input, "-o", output],
    { encoding: "utf8", stdio: "pipe" },
  );

  const css = readFileSync(output, "utf8");
  const generated = new Set<string>();
  const selector = /\.((?:[^\s{},:>+~()\\]|\\.)+)/g;
  let match: RegExpExecArray | null;
  while ((match = selector.exec(css))) {
    generated.add(match[1].replace(/\\(.)/g, "$1"));
  }
  return generated;
}

describe("every className resolves against the theme", () => {
  // Compiling Tailwind once for the whole suite; it is a real build.
  jest.setTimeout(120_000);

  const used = classNamesUsedInSource();
  const candidates = [...used.keys()];
  const generated = classNamesTailwindGenerates(candidates);

  it("finds the classes the app actually uses", () => {
    // A guard on the guard: if extraction silently broke, everything would
    // "pass" by having nothing to check.
    expect(candidates.length).toBeGreaterThan(300);
    expect(generated.has("flex-1")).toBe(true);
  });

  it("leaves no unresolvable class in the source", () => {
    const unresolved = candidates
      .filter(isPlausibleClass)
      .filter((candidate) => !generated.has(candidate))
      .map((candidate) => `${candidate}  (${used.get(candidate)})`);

    expect(unresolved).toEqual([]);
  });

  it("would catch a typo of the kind this app once shipped", () => {
    // Proves the mechanism rather than trusting it: these must NOT resolve.
    const planted = [
      "textegg-stoneMuted",
      "bg-marigold-999",
      "font-nonsense",
      "text-peacockk",
    ];
    const resolvable = classNamesTailwindGenerates(planted);
    for (const bad of planted) expect(resolvable.has(bad)).toBe(false);
  });
});
