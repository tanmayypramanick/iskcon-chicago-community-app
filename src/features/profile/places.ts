/**
 * Place suggestions without a paid API.
 *
 * A true address autocomplete (Google Places, Mapbox) needs an API key and
 * costs per keystroke. Two things are free and get most of the way there:
 *
 *  1. A bundled list of the places an ISKCON congregation actually draws from
 *     — Indian cities and the major diaspora hubs — searched offline.
 *  2. The operating system's own geocoder, via expo-location, to turn "where I
 *     am standing" into a written address.
 *
 * Neither pretends to be exhaustive: the field stays free text, and the list
 * only offers. A devotee born somewhere not listed simply types it.
 */

/** Common birth places for this congregation, plus world hubs. */
export const commonPlaces: readonly string[] = [
  // India — the places most devotees or their families come from.
  "Mumbai, Maharashtra, India",
  "Pune, Maharashtra, India",
  "Nagpur, Maharashtra, India",
  "Delhi, India",
  "New Delhi, Delhi, India",
  "Bengaluru, Karnataka, India",
  "Mysuru, Karnataka, India",
  "Hyderabad, Telangana, India",
  "Chennai, Tamil Nadu, India",
  "Coimbatore, Tamil Nadu, India",
  "Kolkata, West Bengal, India",
  "Mayapur, West Bengal, India",
  "Siliguri, West Bengal, India",
  "Ahmedabad, Gujarat, India",
  "Surat, Gujarat, India",
  "Vadodara, Gujarat, India",
  "Rajkot, Gujarat, India",
  "Jaipur, Rajasthan, India",
  "Jodhpur, Rajasthan, India",
  "Lucknow, Uttar Pradesh, India",
  "Kanpur, Uttar Pradesh, India",
  "Varanasi, Uttar Pradesh, India",
  "Vrindavan, Uttar Pradesh, India",
  "Mathura, Uttar Pradesh, India",
  "Agra, Uttar Pradesh, India",
  "Noida, Uttar Pradesh, India",
  "Patna, Bihar, India",
  "Bhubaneswar, Odisha, India",
  "Puri, Odisha, India",
  "Guwahati, Assam, India",
  "Chandigarh, India",
  "Ludhiana, Punjab, India",
  "Amritsar, Punjab, India",
  "Indore, Madhya Pradesh, India",
  "Bhopal, Madhya Pradesh, India",
  "Raipur, Chhattisgarh, India",
  "Ranchi, Jharkhand, India",
  "Dehradun, Uttarakhand, India",
  "Thiruvananthapuram, Kerala, India",
  "Kochi, Kerala, India",
  "Visakhapatnam, Andhra Pradesh, India",
  "Vijayawada, Andhra Pradesh, India",
  "Tirupati, Andhra Pradesh, India",
  "Goa, India",
  "Srinagar, Jammu and Kashmir, India",

  // United States — Chicago first, then the wider diaspora.
  "Chicago, Illinois, United States",
  "Naperville, Illinois, United States",
  "Aurora, Illinois, United States",
  "Evanston, Illinois, United States",
  "Schaumburg, Illinois, United States",
  "Skokie, Illinois, United States",
  "Oak Brook, Illinois, United States",
  "Bloomington, Illinois, United States",
  "Milwaukee, Wisconsin, United States",
  "Indianapolis, Indiana, United States",
  "Detroit, Michigan, United States",
  "Columbus, Ohio, United States",
  "Cleveland, Ohio, United States",
  "Minneapolis, Minnesota, United States",
  "St. Louis, Missouri, United States",
  "Dallas, Texas, United States",
  "Houston, Texas, United States",
  "Austin, Texas, United States",
  "Atlanta, Georgia, United States",
  "New York, New York, United States",
  "Jersey City, New Jersey, United States",
  "Edison, New Jersey, United States",
  "Philadelphia, Pennsylvania, United States",
  "Boston, Massachusetts, United States",
  "Washington, District of Columbia, United States",
  "Miami, Florida, United States",
  "Orlando, Florida, United States",
  "Phoenix, Arizona, United States",
  "Denver, Colorado, United States",
  "Seattle, Washington, United States",
  "Portland, Oregon, United States",
  "San Francisco, California, United States",
  "San Jose, California, United States",
  "Los Angeles, California, United States",
  "San Diego, California, United States",
  "Sacramento, California, United States",
  "Las Vegas, Nevada, United States",

  // The rest of the diaspora.
  "Toronto, Ontario, Canada",
  "Brampton, Ontario, Canada",
  "Mississauga, Ontario, Canada",
  "Vancouver, British Columbia, Canada",
  "Calgary, Alberta, Canada",
  "Montreal, Quebec, Canada",
  "London, United Kingdom",
  "Leicester, United Kingdom",
  "Birmingham, United Kingdom",
  "Manchester, United Kingdom",
  "Watford, United Kingdom",
  "Sydney, New South Wales, Australia",
  "Melbourne, Victoria, Australia",
  "Brisbane, Queensland, Australia",
  "Perth, Western Australia, Australia",
  "Auckland, New Zealand",
  "Dubai, United Arab Emirates",
  "Abu Dhabi, United Arab Emirates",
  "Doha, Qatar",
  "Singapore",
  "Kuala Lumpur, Malaysia",
  "Hong Kong",
  "Kathmandu, Nepal",
  "Dhaka, Bangladesh",
  "Colombo, Sri Lanka",
  "Karachi, Pakistan",
  "Lahore, Pakistan",
  "Durban, South Africa",
  "Johannesburg, South Africa",
  "Cape Town, South Africa",
  "Port of Spain, Trinidad and Tobago",
  "Georgetown, Guyana",
  "Paramaribo, Suriname",
  "Nairobi, Kenya",
  "Lagos, Nigeria",
  "Moscow, Russia",
  "Kyiv, Ukraine",
  "Berlin, Germany",
  "Frankfurt, Germany",
  "Paris, France",
  "Amsterdam, Netherlands",
  "Zurich, Switzerland",
  "Stockholm, Sweden",
  "Lisbon, Portugal",
  "Madrid, Spain",
  "Rome, Italy",
  "Budapest, Hungary",
  "Warsaw, Poland",
  "Dublin, Ireland",
  "Tokyo, Japan",
  "Seoul, South Korea",
  "Manila, Philippines",
  "Jakarta, Indonesia",
  "Bangkok, Thailand",
  "Buenos Aires, Argentina",
  "São Paulo, Brazil",
  "Mexico City, Mexico",
  "Lima, Peru",
  "Santiago, Chile",
];

/** Best matches for what has been typed so far, nearest the start first. */
export function suggestPlaces(query: string, limit = 6): string[] {
  const needle = query.trim().toLocaleLowerCase();
  if (needle.length < 2) return [];

  const scored = commonPlaces
    .map((place) => ({ place, at: place.toLocaleLowerCase().indexOf(needle) }))
    .filter((entry) => entry.at >= 0)
    // A match at the start of the name beats one buried in the country.
    .sort((left, right) => left.at - right.at || left.place.localeCompare(right.place));

  return scored.slice(0, limit).map((entry) => entry.place);
}

/**
 * Turns the device's current position into a written address using the
 * operating system's geocoder. No API key, no per-request cost. Returns null
 * when permission is refused or nothing can be resolved, so the caller can
 * simply leave the field to be typed.
 */
export async function addressFromCurrentPosition(): Promise<string | null> {
  let Location: typeof import("expo-location");
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    Location = require("expo-location") as typeof import("expo-location");
  } catch {
    return null;
  }

  const permission = await Location.requestForegroundPermissionsAsync();
  if (!permission.granted) return null;

  const position = await Location.getCurrentPositionAsync({
    accuracy: Location.Accuracy.Balanced,
  });
  const [place] = await Location.reverseGeocodeAsync({
    latitude: position.coords.latitude,
    longitude: position.coords.longitude,
  });
  if (!place) return null;

  return [
    [place.streetNumber, place.street].filter(Boolean).join(" "),
    place.city ?? place.subregion,
    place.region,
    place.postalCode,
    place.country,
  ]
    .map((part) => part?.trim())
    .filter(Boolean)
    .join(", ");
}
