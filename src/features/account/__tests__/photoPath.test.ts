import { photoPathIn } from "../photoPath";

/**
 * The photograph has to be found before it can be deleted, and a devotee whose
 * reference was written in the older shape must not be the one whose picture
 * is left behind in the bucket.
 */
describe("finding a profile photograph in the bucket", () => {
  it("reads a full public URL, which is how the older uploads were stored", () => {
    expect(
      photoPathIn(
        "https://gkkeebhdavavizcvknwy.supabase.co/storage/v1/object/public/devotee-photos/abc-123/1786597627238.jpg",
      ),
    ).toBe("abc-123/1786597627238.jpg");
  });

  it("reads a signed URL, ignoring the token on the end", () => {
    expect(
      photoPathIn(
        "https://x.supabase.co/storage/v1/object/sign/devotee-photos/abc-123/p.jpg?token=eyJhbG",
      ),
    ).toBe("abc-123/p.jpg");
  });

  it("reads a bare path, which is how the newer ones are stored", () => {
    expect(photoPathIn("abc-123/1786597627238.jpg")).toBe(
      "abc-123/1786597627238.jpg",
    );
  });

  it("gives up on a reference to some other bucket rather than guessing", () => {
    expect(
      photoPathIn("https://x.supabase.co/storage/v1/object/public/message-images/a/b.jpg"),
    ).toBeNull();
  });

  it("gives up on nothing at all", () => {
    expect(photoPathIn("")).toBeNull();
    expect(photoPathIn("   ")).toBeNull();
  });
});
