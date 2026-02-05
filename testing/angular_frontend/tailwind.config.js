/** @type {import('tailwindcss').Config} */
const colors = require('tailwindcss/colors');

module.exports = {
  content: [
    './src/**/*.{html,ts}', // Scans your app component for Tailwind classes
  ],
  theme: {
    extend: {
      colors: {
        // We'll create a "primary" color palette based on 'indigo'
        // This gives a professional, academic feel
        primary: colors.indigo,
        
        // Use 'slate' for a more modern, neutral gray
        gray: colors.slate,
        
        // Use 'emerald' for a cleaner "success" green
        green: colors.emerald,
      },
      fontFamily: {
        // Use 'Inter' as the default sans-serif font
        sans: ['Inter', 'sans-serif'],
      },
    },
  },
  plugins: [
    require('@tailwindcss/forms'), // The forms plugin
  ],
};
