<mcl_constraint name="phase4a-ui-build-styles">

# Phase 4a — Styling Guidance

## Rule 1 — Respect Existing Design System

If the project already has a styling convention, USE IT without
introducing new dependencies:

| Signal in project                     | Use this                           |
| ------------------------------------- | ---------------------------------- |
| `tailwind.config.*` present           | Tailwind utility classes           |
| `@emotion/*` or `styled-components`   | CSS-in-JS matching the existing lib |
| `*.module.css` / `*.module.scss`      | CSS Modules                        |
| `uno.config.*`                        | UnoCSS                             |
| `shadcn` / `@radix-ui/*` in deps      | shadcn-style composition           |
| `@mui/material`, `@chakra-ui/react`   | that component library             |
| Plain `.css` / `.scss` in `src/styles/` | Plain CSS with existing class naming |

Detect by reading `package.json` deps + top-level config files. Do
NOT grep component code to infer convention — rely on manifest
signals only (faster, deterministic).

## Rule 2 — Minimal-Footprint Fallback

When NO styling convention is detected, use **plain CSS** — scoped
via CSS Modules when bundler supports it, or a single `<style>`
block when emitting static HTML. Reasons:

- No new dependency (nothing to install, nothing to configure).
- No lock-in — the developer can migrate to Tailwind / shadcn later
  without removing your code.
- Works with any bundler the project already uses.

Do NOT auto-introduce Tailwind / shadcn / MUI in Phase 4a — adding a
design system is a spec-level decision, not a Phase 4a default.

## Rule 3 — Neutral Dummy Appearance

The component should look presentable enough for the developer to
judge layout, spacing, and flow — but NOT polished enough that they
forget it is a mock. The goal is to make visual defects obvious, not
to impress.

Acceptable:
- System font stack (`system-ui, sans-serif`)
- Single accent color (match any existing CSS custom property, else
  `#3b82f6` blue or `currentColor`)
- Generous padding/margin — avoid cramped layouts

Avoid:
- Elaborate gradients, shadows, animations — they hide layout bugs
- Icon libraries introduced purely for mock display (`lucide-react`,
  `@heroicons/react`) unless already in deps
- Custom fonts from Google Fonts / a CDN — adds network dependency,
  changes render timing across dev and prod

## Rule 4 — Responsive by Default, Not by Elaboration

Emit flex/grid layouts that survive a mobile viewport resize. Do
NOT write media queries for pixel-perfect breakpoints in Phase 4a —
responsive design polish is a Phase 4c or separate-spec concern.

## Rule 5 — Accessibility Basics

Always include, even in mock:
- Semantic HTML (`<button>`, `<form>`, `<label>`, `<nav>`) — never
  divs-as-buttons
- `alt=""` on decorative images, descriptive alt on content images
- `aria-label` on icon-only controls
- Form inputs connected to `<label>` via `htmlFor`

These survive into Phase 4c without rework. Deeper a11y audit
(keyboard traversal, focus order, contrast ratios) is out of Phase
4a scope — surface in Phase 4.5 only if the spec called a11y out
as a MUST.

</mcl_constraint>
