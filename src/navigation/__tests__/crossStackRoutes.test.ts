/// <reference types="jest" />

import { readdirSync, readFileSync } from "fs";
import { join } from "path";

/**
 * A screen registered in two stacks must be able to reach the same places from
 * both of them.
 *
 * "My seva and history" is deliberately registered in ProfileStack as well as
 * ServicesStack, because jumping a devotee to the Seva tab left them in a tab
 * they had not opened. But the four screens it opens were only in
 * ServicesStack, so from the Profile tab every card tap and every "See all"
 * did nothing at all. React Navigation only warns about that in development —
 * in a release build the tap is silently swallowed — which is exactly why it
 * survived to a device and has to be caught here instead.
 *
 * Read off the source rather than by rendering the navigators: the failure is
 * a route name that exists in one stack and not another, and that is a fact
 * about the files.
 */

const NAV_DIR = join(__dirname, "..");
const SCREEN_DIR = join(__dirname, "..", "..", "screens");

type Stack = { routes: Set<string>; screens: Map<string, string> };

function readStacks(): Map<string, Stack> {
  const stacks = new Map<string, Stack>();
  for (const file of readdirSync(NAV_DIR).filter((n) => n.endsWith("Stack.tsx"))) {
    const source = readFileSync(join(NAV_DIR, file), "utf8");
    const routes = new Set(
      [...source.matchAll(/name="([A-Za-z]+)"/g)].map((m) => m[1]),
    );
    const screens = new Map(
      [...source.matchAll(/name="([A-Za-z]+)"\s*component=\{([A-Za-z]+)\}/g)].map(
        (m) => [m[1], m[2]] as const,
      ),
    );
    stacks.set(file, { routes, screens });
  }
  return stacks;
}

/** Every route name a screen tries to push, taken from its own source. */
function destinationsOf(component: string): Set<string> {
  const path = join(SCREEN_DIR, `${component}.tsx`);
  let source: string;
  try {
    source = readFileSync(path, "utf8");
  } catch {
    return new Set();
  }
  return new Set(
    [...source.matchAll(/navigate\(\s*"([A-Za-z]+)"/g)].map((m) => m[1]),
  );
}

describe("routes reachable from every stack that registers a screen", () => {
  const stacks = readStacks();

  it("finds the stacks and at least one screen shared between two of them", () => {
    expect(stacks.size).toBeGreaterThanOrEqual(3);
    const homes = new Map<string, string[]>();
    for (const [file, stack] of stacks) {
      for (const component of stack.screens.values()) {
        homes.set(component, [...(homes.get(component) ?? []), file]);
      }
    }
    // If this ever drops to zero the test below is vacuous rather than passing.
    expect([...homes.values()].filter((f) => f.length > 1).length).toBeGreaterThan(0);
  });

  it("has no screen that can navigate somewhere one of its stacks cannot reach", () => {
    const homes = new Map<string, string[]>();
    for (const [file, stack] of stacks) {
      for (const component of stack.screens.values()) {
        homes.set(component, [...(homes.get(component) ?? []), file]);
      }
    }

    const unreachable: string[] = [];
    for (const [component, files] of homes) {
      if (files.length < 2) continue;
      const wanted = destinationsOf(component);
      for (const file of files) {
        const stack = stacks.get(file)!;
        for (const route of wanted) {
          if (!stack.routes.has(route)) {
            unreachable.push(`${component} in ${file} cannot reach ${route}`);
          }
        }
      }
    }

    expect(unreachable).toStrictEqual([]);
  });
});
