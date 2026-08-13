/**
 * Kept free of imports so screens can show the guidance without pulling in the
 * Supabase client (and its native storage) at module load.
 */
export const photoGuidelines = [
  "Face the camera so devotees can recognise you.",
  "Use good light and keep your whole face in the frame.",
  "One person only — no group photos.",
  "No text, logos, or filters over your face.",
] as const;
