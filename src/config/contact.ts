export const COMMUNITY_EMAIL = "tech@iskconchicago.com";

export function communityEmailUrl(subject?: string) {
  const query = subject ? `?subject=${encodeURIComponent(subject)}` : "";
  return `mailto:${COMMUNITY_EMAIL}${query}`;
}
