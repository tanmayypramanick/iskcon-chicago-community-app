import type { FeatureKey } from "../navigation/types";

export const communityFeatures: Array<{
  key: FeatureKey;
  title: string;
  subtitle: string;
  icon: string;
}> = [
  {
    key: "communities",
    title: "Communities",
    subtitle: "Connect and serve together",
    icon: "people-circle-outline",
  },
  {
    key: "courses",
    title: "Courses",
    subtitle: "Learn at your pace",
    icon: "book-outline",
  },
  {
    key: "forum",
    title: "Forum",
    subtitle: "Share and discuss",
    icon: "chatbubbles-outline",
  },
  {
    key: "rankings",
    title: "Seva journey",
    subtitle: "Celebrate participation",
    icon: "ribbon-outline",
  },
  {
    key: "newsletter",
    title: "Newsletter",
    subtitle: "Temple stories and updates",
    icon: "newspaper-outline",
  },
  {
    key: "announcements",
    title: "Announcements",
    subtitle: "What is happening next",
    icon: "megaphone-outline",
  },
  {
    key: "donations",
    title: "Donations",
    subtitle: "Authorized view",
    icon: "wallet-outline",
  },
  {
    key: "feedback",
    title: "Feedback",
    subtitle: "Help us improve",
    icon: "heart-circle-outline",
  },
];

export const services = [
  {
    title: "Sunday Feast Kitchen",
    time: "Today · 3:30 PM",
    duration: "2 hours",
    slots: "2 of 5 spots open",
    status: "Open",
  },
  {
    title: "Temple Room Flowers",
    time: "Tomorrow · 8:00 AM",
    duration: "1 hour",
    slots: "1 of 3 spots open",
    status: "Open",
  },
  {
    title: "Evening Prasadam Cleanup",
    time: "Friday · 7:45 PM",
    duration: "1.5 hours",
    slots: "Team complete",
    status: "Full",
  },
];

export const devotees = [
  { name: "Ananda Dasa", initials: "AD", detail: "At the temple", tone: "peacock" },
  { name: "Bhakti Priya", initials: "BP", detail: "Kitchen seva", tone: "marigold" },
  { name: "Gopal Das", initials: "GD", detail: "Member", tone: "indigo" },
  { name: "Madhavi Devi Dasi", initials: "MD", detail: "At the temple", tone: "peacock" },
] as const;

export const featureContent: Record<
  FeatureKey,
  {
    eyebrow: string;
    intro: string;
    action: string;
    cards: Array<{ title: string; detail: string; meta: string }>;
  }
> = {
  communities: {
    eyebrow: "Serve together",
    intro: "Find smaller circles of devotees and stay connected through shared seva.",
    action: "Explore communities",
    cards: [
      { title: "Sunday Feast Team", detail: "46 devotees", meta: "2 new messages" },
      { title: "Young Adults Sanga", detail: "31 devotees", meta: "Meets Friday" },
    ],
  },
  courses: {
    eyebrow: "Learn and grow",
    intro: "Courses, materials, attendance, and progress in one calm place.",
    action: "Browse courses",
    cards: [
      { title: "Bhagavad-gita Foundations", detail: "Sundays · 11:00 AM", meta: "Enrollment open" },
      { title: "Introduction to Bhakti", detail: "Online · 6 weeks", meta: "Continue lesson 3" },
    ],
  },
  forum: {
    eyebrow: "Community conversation",
    intro: "Ask questions, share reflections, and continue meaningful discussions.",
    action: "Create a post",
    cards: [
      { title: "How do you prepare for Ekadashi?", detail: "12 thoughtful replies", meta: "Posted today" },
      { title: "Favorite verse this week", detail: "24 replies", meta: "Active discussion" },
    ],
  },
  rankings: {
    eyebrow: "Seva journey",
    intro: "A gentle celebration of consistent participation—not a measure of devotion.",
    action: "View my journey",
    cards: [
      { title: "Your month", detail: "8 hours of recorded seva", meta: "4 services completed" },
      { title: "Community gratitude", detail: "Sunday Feast Team", meta: "Most consistent team" },
    ],
  },
  newsletter: {
    eyebrow: "Temple stories",
    intro: "Monthly reflections, festival recaps, and community news.",
    action: "Read latest issue",
    cards: [
      { title: "July 2026", detail: "Ratha-yatra special issue", meta: "New" },
      { title: "June 2026", detail: "Summer seva and course updates", meta: "12 min read" },
    ],
  },
  announcements: {
    eyebrow: "Temple updates",
    intro: "Important notices are presented clearly, with dates and next steps.",
    action: "View calendar",
    cards: [
      { title: "Sunday Feast", detail: "This Sunday · 5:00 PM", meta: "Everyone is welcome" },
      { title: "Ratha-yatra volunteer meeting", detail: "Saturday · 10:00 AM", meta: "Community hall" },
    ],
  },
  donations: {
    eyebrow: "Authorized preview",
    intro: "A private, role-gated space for donation records and reporting.",
    action: "Review records",
    cards: [
      { title: "Monthly overview", detail: "Visible to authorized roles only", meta: "Private" },
      { title: "Recent records", detail: "Reporting layout to be confirmed", meta: "UI prototype" },
    ],
  },
  feedback: {
    eyebrow: "We are listening",
    intro: "Share a suggestion privately and help make the community experience better.",
    action: "Share feedback",
    cards: [
      { title: "Suggest an improvement", detail: "About the temple or this app", meta: "Private" },
      { title: "My feedback", detail: "See the status of past suggestions", meta: "1 submitted" },
    ],
  },
};
