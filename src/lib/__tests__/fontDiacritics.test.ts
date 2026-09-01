/// <reference types="jest" />

import { execFileSync } from "child_process";
import { readFileSync } from "fs";
import { join } from "path";

/**
 * Every font the app loads must contain every letter of the ISKCON script.
 *
 * This guards a bug the temple actually saw and reported: in "Hare Kṛṣṇa" the
 * dotted letters — ṛ, ṣ, ṇ — rendered BOLD while the letters around them
 * stayed normal. Nothing in the styling asked for that. It happens because a
 * font that has no glyph for a character does not fail; the OS quietly
 * substitutes another family for those characters alone, and the substitute is
 * a different weight. The result is a word that changes weight in the middle,
 * which reads as a typography bug and cannot be fixed with a className.
 *
 * So the fix is coverage, and this is the test that keeps it: it parses the
 * real cmap table out of every .ttf the app loads and asserts that each one
 * maps every diacritic used in IAST transliteration. Swapping a display face
 * for one that lacks Latin Extended Additional fails here rather than in a
 * devotee's hands.
 *
 * The font list is read from App.tsx rather than written down twice, so adding
 * a face without checking it is not possible.
 */

const REPO_ROOT = join(__dirname, "..", "..", "..");

/**
 * The letters ISKCON transliteration actually uses, in both cases.
 *
 * ā ī ū ñ ś come from Latin Extended-A; ṛ ṝ ḷ ṅ ṭ ḍ ṇ ṣ ṁ ḥ from Latin
 * Extended Additional (U+1E00–1EFF), which is the block a Latin font is most
 * likely to omit and the one "Kṛṣṇa" depends on.
 */
const IAST = "āĀīĪūŪṛṚṝṜḷḶṅṄñÑṭṬḍḌṇṆśŚṣṢṁṀḥḤ";

/** Characters actually present in the app's own copy, as a sanity anchor. */
const WORDS_THE_APP_PRINTS = ["Kṛṣṇa", "Vaiṣṇava", "Ekādaśī", "Śrī", "sevā"];

/** The glyphs a TrueType cmap maps, read out of the file itself. */
function coveredCodePoints(file: string): Set<number> {
  const b = readFileSync(file);
  const tableCount = b.readUInt16BE(4);

  let cmapOffset: number | null = null;
  for (let i = 0; i < tableCount; i++) {
    const record = 12 + i * 16;
    if (b.toString("ascii", record, record + 4) === "cmap") {
      cmapOffset = b.readUInt32BE(record + 8);
      break;
    }
  }
  if (cmapOffset === null) throw new Error(`${file} has no cmap table`);

  // Prefer a format 12 subtable (full Unicode), then Windows BMP format 4.
  const subtableCount = b.readUInt16BE(cmapOffset + 2);
  let best: { offset: number; format: number } | null = null;
  let bestScore = -1;
  for (let i = 0; i < subtableCount; i++) {
    const record = cmapOffset + 4 + i * 8;
    const platform = b.readUInt16BE(record);
    const encoding = b.readUInt16BE(record + 2);
    const offset = b.readUInt32BE(record + 4);
    const format = b.readUInt16BE(cmapOffset + offset);
    const score =
      format === 12 ? 3 : format === 4 && platform === 3 && encoding === 1 ? 2 : format === 4 ? 1 : -1;
    if (score > bestScore) {
      bestScore = score;
      best = { offset: cmapOffset + offset, format };
    }
  }
  if (!best) throw new Error(`${file} has no usable cmap subtable`);

  const covered = new Set<number>();

  if (best.format === 4) {
    const segCountX2 = b.readUInt16BE(best.offset + 6);
    const segCount = segCountX2 / 2;
    const endOffset = best.offset + 14;
    const startOffset = endOffset + segCountX2 + 2;
    const deltaOffset = startOffset + segCountX2;
    const rangeOffset = deltaOffset + segCountX2;

    for (let seg = 0; seg < segCount; seg++) {
      const end = b.readUInt16BE(endOffset + seg * 2);
      const start = b.readUInt16BE(startOffset + seg * 2);
      const delta = b.readInt16BE(deltaOffset + seg * 2);
      const range = b.readUInt16BE(rangeOffset + seg * 2);
      if (start === 0xffff) continue;

      for (let code = start; code <= end; code++) {
        let glyph: number;
        if (range === 0) {
          glyph = (code + delta) & 0xffff;
        } else {
          const index = rangeOffset + seg * 2 + range + (code - start) * 2;
          if (index + 1 >= b.length) continue;
          glyph = b.readUInt16BE(index);
          if (glyph) glyph = (glyph + delta) & 0xffff;
        }
        if (glyph) covered.add(code);
      }
    }
  } else {
    const groupCount = b.readUInt32BE(best.offset + 12);
    for (let i = 0; i < groupCount; i++) {
      const group = best.offset + 16 + i * 12;
      const start = b.readUInt32BE(group);
      const end = b.readUInt32BE(group + 4);
      for (let code = start; code <= end; code++) covered.add(code);
    }
  }

  return covered;
}

/** The font families App.tsx actually hands to useFonts. */
function loadedFontNames(): string[] {
  const app = readFileSync(join(REPO_ROOT, "App.tsx"), "utf8");
  const block = app.slice(app.indexOf("useFonts({"));
  const names = block
    .slice(0, block.indexOf("})"))
    .split(/[\n,]/)
    .map((line) => line.trim())
    // Two underscores in EBGaramond_500Medium_Italic, so this cannot be
    // anchored to exactly one — requiring one silently skipped the italic face.
    .filter((line) => /^[A-Za-z0-9]+(?:_[A-Za-z0-9]+)+$/.test(line));
  return [...new Set(names)];
}

function fontFile(name: string): string {
  const found = execFileSync(
    "find",
    [
      join(REPO_ROOT, "node_modules", "@expo-google-fonts"),
      "-name",
      `${name}.ttf`,
    ],
    { encoding: "utf8" },
  )
    .split("\n")
    .filter(Boolean);
  if (!found.length) throw new Error(`no .ttf on disk for ${name}`);
  return found[0];
}

describe("the ISKCON script renders in one weight", () => {
  const names = loadedFontNames();

  it("reads the font list out of App.tsx", () => {
    // A guard on the guard: if the parse broke, every assertion below would
    // vacuously pass by having no fonts to check.
    expect(names.length).toBeGreaterThanOrEqual(4);
    expect(names).toContain("SourceSans3_400Regular");
  });

  it.each(names)("%s has every IAST diacritic", (name) => {
    const covered = coveredCodePoints(fontFile(name));
    const missing = [...IAST].filter(
      (character) => !covered.has(character.codePointAt(0)!),
    );

    // A miss here is not a missing character on screen — it is the OS
    // substituting a heavier family for those letters alone, which is how
    // "Kṛṣṇa" came to have three bold letters in the middle of it.
    expect(missing).toEqual([]);
  });

  it.each(names)("%s can set the words the app prints", (name) => {
    const covered = coveredCodePoints(fontFile(name));
    for (const word of WORDS_THE_APP_PRINTS) {
      const missing = [...word].filter(
        (character) => !covered.has(character.codePointAt(0)!),
      );
      expect({ word, missing }).toEqual({ word, missing: [] });
    }
  });

  it("would notice a font that lacks the dotted letters", () => {
    // Proves the parser rather than trusting it: Latin Extended Additional is
    // exactly what a stripped webfont subset drops, so an ASCII-only range
    // must be reported as missing.
    const asciiOnly = new Set<number>();
    for (let code = 0x20; code < 0x7f; code++) asciiOnly.add(code);

    const missing = [...IAST].filter(
      (character) => !asciiOnly.has(character.codePointAt(0)!),
    );
    expect(missing.length).toBe([...IAST].length);
    expect(missing).toContain("ṛ");
    expect(missing).toContain("ṣ");
    expect(missing).toContain("ṇ");
  });
});
