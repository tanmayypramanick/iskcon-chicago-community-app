/// <reference types="jest" />

import { birthdayAnnouncementPrefill } from "../types";

/**
 * The devotee's photograph must survive the trip from the server's suggestion
 * to the composer.
 *
 * This is guarding a bug that TypeScript cannot see: the server returns
 * `image_url` and the composer takes `imageUrl`, and because the extra
 * property is allowed and `imageUrl` is optional, handing the suggestion
 * straight over compiles perfectly and quietly posts a birthday notice with no
 * face on it.
 */
describe("birthdayAnnouncementPrefill", () => {
  const suggestion = {
    title: "Happy birthday, Ananda Das!",
    body: "Today is Ananda Das's birthday.\n\nHare Kṛṣṇa!",
    image_url:
      "https://abc.supabase.co/storage/v1/object/public/devotee-photos/uid-1/face.jpg",
  };

  it("carries the devotee's photograph across", () => {
    expect(birthdayAnnouncementPrefill(suggestion)).toEqual({
      title: suggestion.title,
      body: suggestion.body,
      imageUrl: suggestion.image_url,
      kind: "birthday",
    });
  });

  it("renames image_url, so nothing downstream reads the server's spelling", () => {
    const prefill = birthdayAnnouncementPrefill(suggestion);
    expect(prefill).not.toHaveProperty("image_url");
    expect(prefill.imageUrl).toBe(suggestion.image_url);
  });

  it("marks it a birthday, so the card draws the frame", () => {
    // Carried on the row rather than inferred from the title later: the
    // President is invited to rewrite that wording.
    expect(birthdayAnnouncementPrefill(suggestion).kind).toBe("birthday");
  });

  it("keeps the temple's wording exactly, diacritics and line breaks included", () => {
    const prefill = birthdayAnnouncementPrefill(suggestion);
    expect(prefill.body).toContain("Kṛṣṇa");
    expect(prefill.body).toContain("\n\n");
  });

  it("is happy with a devotee who has no photograph", () => {
    expect(
      birthdayAnnouncementPrefill({ ...suggestion, image_url: null }),
    ).toEqual({
      title: suggestion.title,
      body: suggestion.body,
      imageUrl: null,
      kind: "birthday",
    });
  });
});
