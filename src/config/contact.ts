export const COMMUNITY_EMAIL = "tech@iskconchicago.com";

/**
 * The published policy documents, served from GitHub Pages beside
 * `docs/seva-flows.html`. Both stores require a privacy policy at a URL a
 * reviewer can open without an account, which is why these are web pages and
 * not only the in-app Terms of Service and Privacy and visibility screens.
 */
const PUBLISHED_DOCS_BASE_URL =
  "https://tanmayypramanick.github.io/iskcon-chicago-community-app";

export const PRIVACY_POLICY_URL = `${PUBLISHED_DOCS_BASE_URL}/privacy-policy.html`;
export const TERMS_OF_SERVICE_URL = `${PUBLISHED_DOCS_BASE_URL}/terms-of-service.html`;

export function communityEmailUrl(subject?: string) {
  const query = subject ? `?subject=${encodeURIComponent(subject)}` : "";
  return `mailto:${COMMUNITY_EMAIL}${query}`;
}
