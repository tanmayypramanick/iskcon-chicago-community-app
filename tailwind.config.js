const tokens = require("./design-tokens.json");

/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./App.tsx",
    "./src/**/*.{js,jsx,ts,tsx}"
  ],
  presets: [require("nativewind/preset")],
  theme: {
    extend: {
      colors: tokens.colors,
      spacing: tokens.spacing,
      borderRadius: tokens.radii,
      fontFamily: {
        display: ["EBGaramond_600SemiBold"],
        "display-italic": ["EBGaramond_500Medium_Italic"],
        sans: ["SourceSans3_400Regular"],
        "sans-bold": ["SourceSans3_700Bold"]
      }
    }
  },
  plugins: []
};
