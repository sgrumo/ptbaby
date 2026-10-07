const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

const token = name => `rgb(var(--color-${name}) / <alpha-value>)`
const scale = (name, steps) => Object.fromEntries(steps.map(step => [step, token(`${name}-${step}`)]))

module.exports = {
  darkMode: ["selector", '[data-theme="dark"]'],
  content: [
    "./js/**/*.js",
    "../lib/averziano_web.ex",
    "../lib/averziano_web/**/*.*ex"
  ],
  theme: {
    extend: {
      // Quinck Design System tokens (colors_and_type.css). Values live in
      // css/app.css as RGB channels so dark mode can swap them in one place.
      colors: {
        surface: token("surface"),
        neutral: scale("neutral", [50, 100, 200, 300, 400, 500, 600, 700, 800, 900]),
        primary: scale("primary", [100, 200, 300, 400, 500, 600, 700, 800]),
        success: scale("success", [100, 200, 400, 600, 800]),
        warning: scale("warning", [100, 200, 400, 600, 800]),
        danger: scale("danger", [100, 200, 400, 600, 800]),
        info: scale("info", [100, 200, 600, 800])
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
