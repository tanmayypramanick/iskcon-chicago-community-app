/**
 * Shapes returned by the feedback migration (202608040041_feedback.sql).
 *
 * A devotee sends one short note in one of three categories. The President and
 * the Tech Admin — the holders of `app.view_all` — read all of it and may mark
 * a note reviewed with an optional one-way acknowledgement.
 */

export const feedbackCategories = ["temple", "app", "community"] as const;

export type FeedbackCategory = (typeof feedbackCategories)[number];

export const feedbackCategoryLabels: Record<FeedbackCategory, string> = {
  temple: "Temple",
  app: "App",
  community: "Community",
};

/** What each category is for, shown under the picker so nobody has to guess. */
export const feedbackCategoryHints: Record<FeedbackCategory, string> = {
  temple: "The building, the programmes, the prasadam, the parking.",
  app: "This app — anything that is confusing, missing or broken.",
  community: "The devotees, and how we treat one another.",
};

export type FeedbackStatus = "new" | "reviewed";

/** A whole `feedback` row, as returned by `submit_feedback` / `review_feedback`. */
export type FeedbackRow = {
  id: string;
  devotee_id: string;
  category: FeedbackCategory;
  body: string;
  status: FeedbackStatus;
  reply: string | null;
  replied_by: string | null;
  replied_at: string | null;
  created_at: string;
};

/**
 * A row of `list_my_feedback`. The replier travels as a name and nothing else:
 * the devotee is being told the temple answered, not handed a contact card.
 */
export type MyFeedback = {
  id: string;
  category: FeedbackCategory;
  body: string;
  status: FeedbackStatus;
  reply: string | null;
  replied_by_name: string | null;
  replied_at: string | null;
  created_at: string;
  /** False wherever the removal migration has not run; see the api. */
  can_delete: boolean;
};

/** A row of `list_all_feedback`. Empty for anyone without `app.view_all`. */
export type AllFeedback = {
  id: string;
  devotee_id: string;
  devotee_name: string;
  devotee_photo_url: string | null;
  category: FeedbackCategory;
  body: string;
  status: FeedbackStatus;
  reply: string | null;
  replied_by: string | null;
  replied_by_name: string | null;
  replied_at: string | null;
  created_at: string;
  /** False wherever the removal migration has not run; see the api. */
  can_delete: boolean;
};

/**
 * One tap instead of a sentence. The queue only gets worked through if
 * acknowledging the ordinary cases costs nothing, and these are the four
 * answers that cover almost all of them.
 */
export const cannedFeedbackReplies = [
  "We have read this and are looking into it. Thank you.",
  "Thank you for telling us — this has been passed on.",
  "Thank you. We hear you, and we are sorry for the trouble.",
  "Hare Krsna, thank you for taking the time to write this.",
] as const;
