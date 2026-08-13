/// <reference types="jest" />

import { readFileSync, readdirSync } from "fs";
import { join } from "path";

import { appNotificationKinds } from "../types";

const MIGRATIONS = join(__dirname, "../../../../supabase/migrations");

function migrationFiles() {
  return readdirSync(MIGRATIONS)
    .filter((name) => name.endsWith(".sql"))
    .sort();
}

/** The kinds the newest CHECK constraint permits. */
function constraintKinds(): string[] {
  let kinds: string[] = [];
  for (const file of migrationFiles()) {
    const sql = readFileSync(join(MIGRATIONS, file), "utf8");
    if (!sql.includes("app_notifications_kind_check")) continue;

    // A migration may build the constraint from an array rather than writing it
    // out, so the list it verifies and the list it installs cannot drift. That
    // form is checked first: its `format()` template also contains the literal
    // pattern below, but with a %s where the kinds would be.
    const generated = sql.match(/v_kinds text\[\] := array\[([\s\S]*?)\]/);
    if (generated) {
      kinds = [...generated[1].matchAll(/'([a-z_]+)'/g)].map((m) => m[1]);
      continue;
    }

    const literal = sql.match(
      /app_notifications_kind_check check \(\s*kind in \(([\s\S]*?)\)\s*\)/,
    );
    if (literal) {
      kinds = [...literal[1].matchAll(/'([a-z_]+)'/g)].map((m) => m[1]);
    }
  }
  return kinds;
}

/** Every kind any migration actually writes. */
function writtenKinds(): string[] {
  const kinds = new Set<string>();
  for (const file of migrationFiles()) {
    const sql = readFileSync(join(MIGRATIONS, file), "utf8");
    for (const m of sql.matchAll(
      /queue_app_notification\(\s*[^,]+,\s*'([a-z_]+)'/g,
    )) {
      kinds.add(m[1]);
    }
    for (const m of sql.matchAll(/notify_service_oversight\(\s*'([a-z_]+)'/g)) {
      kinds.add(m[1]);
    }
    for (const m of sql.matchAll(
      /insert into public\.app_notifications[\s\S]{0,400}?'([a-z_]+)',\s*\n?\s*'[^']*',/g,
    )) {
      kinds.add(m[1]);
    }
  }
  return [...kinds];
}

describe("notification kinds stay in step", () => {
  it("writes only kinds the CHECK constraint allows", () => {
    // A kind outside the constraint raises inside the function that queues it,
    // which aborts the whole surrounding transaction — so posting a seva or
    // verifying one would fail outright.
    const allowed = new Set(constraintKinds());
    const rejected = writtenKinds().filter((kind) => !allowed.has(kind));
    expect(rejected).toEqual([]);
  });

  it("declares every allowed kind on the client", () => {
    const declared = new Set<string>(appNotificationKinds);
    const missing = constraintKinds().filter((kind) => !declared.has(kind));
    expect(missing).toEqual([]);
  });

  it("declares no kind the database cannot produce", () => {
    const allowed = new Set(constraintKinds());
    const extra = appNotificationKinds.filter((kind) => !allowed.has(kind));
    expect(extra).toEqual([]);
  });

  it("found a real constraint and real writes, so the checks mean something", () => {
    expect(constraintKinds().length).toBeGreaterThan(10);
    expect(writtenKinds().length).toBeGreaterThan(10);
  });
});
