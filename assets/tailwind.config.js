const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

module.exports = {
  content: [
    "./js/**/*.js",
    "../lib/averziano_web.ex",
    "../lib/averziano_web/**/*.*ex"
  ],
  theme: {
    extend: {
      // Quinck Design System tokens (colors_and_type.css)
      colors: {
        neutral: {
          50: "#F7F7F8", 100: "#EDEDED", 200: "#D8D8DD", 300: "#B9BBC6", 400: "#8F92A3",
          500: "#71717A", 600: "#3A3D4F", 700: "#2A2C3A", 800: "#1E1E1E", 900: "#111114"
        },
        primary: {
          100: "#DDD2FF", 200: "#C2B0FF", 300: "#A98EFF", 400: "#8F6CFF",
          500: "#713EFF", 600: "#5E30E6", 700: "#4B24BF", 800: "#391A99"
        },
        success: {100: "#E8FFF7", 200: "#BDFCE7", 400: "#34D399", 600: "#059669", 800: "#065F46"},
        warning: {100: "#F9FFCC", 200: "#F4FFB3", 400: "#DDEB6E", 600: "#AEBF32", 800: "#6E7C1A"},
        danger: {100: "#FEE2E2", 200: "#FECACA", 400: "#F87171", 600: "#DC2626", 800: "#991B1B"},
        info: {100: "#E6F8FF", 200: "#BEEAFF", 600: "#0759C4", 800: "#075985"}
      },
      fontFamily: {
        sans: ["Funnel Sans", "-apple-system", "BlinkMacSystemFont", "Segoe UI", "Roboto", "Helvetica", "Arial", "sans-serif"],
        display: ["Funnel Display", "Funnel Sans", "-apple-system", "BlinkMacSystemFont", "sans-serif"]
      },
      borderRadius: {
        pill: "24px"
      },
      boxShadow: {
        q200: "0 2px 8px -1px rgba(30,41,59,0.12), 0 2px 2px 1px rgba(30,41,59,0.04)"
      }
    },
  },
  plugins: [
    require("@tailwindcss/forms"),
    plugin(({addVariant}) => addVariant("phx-click-loading", [".phx-click-loading&", ".phx-click-loading &"])),
    plugin(({addVariant}) => addVariant("phx-submit-loading", [".phx-submit-loading&", ".phx-submit-loading &"])),
    plugin(({addVariant}) => addVariant("phx-change-loading", [".phx-change-loading&", ".phx-change-loading &"])),

    // Hero icons
    plugin(function({matchComponents, theme}) {
      let iconsDir = path.join(__dirname, "../deps/heroicons/optimized")
      let values = {}
      let icons = [
        ["", "/24/outline"],
        ["-solid", "/24/solid"],
        ["-mini", "/20/solid"],
        ["-micro", "/16/solid"]
      ]
      icons.forEach(([suffix, dir]) => {
        try {
          fs.readdirSync(path.join(iconsDir, dir)).forEach(file => {
            let name = path.basename(file, ".svg") + suffix
            values[name] = {name, fullPath: path.join(iconsDir, dir, file)}
          })
        } catch (_e) {}
      })
      matchComponents({
        "hero": ({name, fullPath}) => {
          let content = fs.readFileSync(fullPath).toString().replace(/\r?\n|\r/g, "")
          let size = theme("googletag.width") || "1.25rem"
          return {
            [`--hero-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
            "-webkit-mask": `var(--hero-${name})`,
            "mask": `var(--hero-${name})`,
            "mask-repeat": "no-repeat",
            "background-color": "currentColor",
            "vertical-align": "middle",
            "display": "inline-block",
            "width": size,
            "height": size
          }
        }
      }, {values})
    })
  ]
}
