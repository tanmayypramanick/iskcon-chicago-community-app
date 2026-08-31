/// <reference types="jest" />

import { readFileSync, readdirSync, statSync } from "fs";
import { join } from "path";

/**
 * Three outages in this app have had one cause: a native module was reached at
 * module-evaluation time, it was not in the installed binary, and the app
 * opened on a blank screen with nothing on it to say why. expo-clipboard did
 * it, expo-image-manipulator did it, and expo-document-picker did it again on
 * a simulator whose binary was three weeks older than the dependency.
 *
 * The trap is that `await import("expo-…")` LOOKS like the fix and is not:
 * Metro compiles a dynamic import to a module-scope require, so the module
 * loads whether or not the function containing it is ever called. The only
 * thing that works is `require()` inside a `try`, behind a small wrapper.
 *
 * Type positions — `typeof import("expo-…")`, `import("expo-…").Options` — are
 * erased before they reach Metro and are fine, so they are stripped first.
 */

const SRC = join(__dirname, "..", "..");

/** Packages whose absence from the binary throws rather than degrading. */
const NATIVE_MODULES = [
  "expo-clipboard",
  "expo-document-picker",
  "expo-image-manipulator",
  "expo-image-picker",
];

function sourceFiles(dir: string): string[] {
  return readdirSync(dir).flatMap((entry) => {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) {
      return entry === "__tests__" ? [] : sourceFiles(path);
    }
    return /\.tsx?$/.test(entry) ? [path] : [];
  });
}

/**
 * Everything that never reaches Metro as a runtime reference: comments (which
 * in this repo quote the very pattern being banned), and the type positions
 * TypeScript erases.
 */
function runtimeSource(body: string): string {
  return body
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/^\s*\/\/.*$/gm, "")
    .replace(/typeof\s+import\s*\(\s*["'][^"']+["']\s*\)/g, "")
    .replace(/import\s*\(\s*["'][^"']+["']\s*\)\s*\./g, "")
    .replace(/^\s*import\s+type\s[^;]+;/gm, "");
}

describe("native modules are only ever reached through a guard", () => {
  const files = sourceFiles(SRC);

  it("finds the app's source to check", () => {
    expect(files.length).toBeGreaterThan(50);
  });

  it.each(NATIVE_MODULES)(
    "%s is never reached through a dynamic import",
    (moduleName) => {
      const offenders = files
        .filter((file) =>
          new RegExp(`import\\s*\\(\\s*["']${moduleName}["']`).test(
            runtimeSource(readFileSync(file, "utf8")),
          ),
        )
        .map((file) => file.slice(SRC.length + 1));

      // Metro turns this into a module-scope require, so it is not lazy: the
      // app crashes on startup rather than when the feature is used.
      expect(offenders).toStrictEqual([]);
    },
  );

  it.each(NATIVE_MODULES)(
    "%s is never imported at the top of a module",
    (moduleName) => {
      const offenders = files
        .filter((file) =>
          new RegExp(`^\\s*import\\s[^;]*["']${moduleName}["']`, "m").test(
            runtimeSource(readFileSync(file, "utf8")),
          ),
        )
        .map((file) => file.slice(SRC.length + 1));

      expect(offenders).toStrictEqual([]);
    },
  );

  it.each(NATIVE_MODULES)("%s is required inside a try", (moduleName) => {
    const users = files.filter((file) =>
      new RegExp(`require\\(\\s*["']${moduleName}["']\\s*\\)`).test(
        readFileSync(file, "utf8"),
      ),
    );
    if (users.length === 0) return; // nothing in the app uses it yet

    for (const file of users) {
      const body = readFileSync(file, "utf8");
      expect({ file: file.slice(SRC.length + 1), guarded: body.includes("catch") })
        .toStrictEqual({ file: file.slice(SRC.length + 1), guarded: true });
    }
  });
});
