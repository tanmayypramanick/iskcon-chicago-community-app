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
        display: ["Lora_600SemiBold"],
        sans: ["AtkinsonHyperlegible_400Regular"],
        "sans-bold": ["AtkinsonHyperlegible_700Bold"]
      }
    }
  },
  plugins: []
};
