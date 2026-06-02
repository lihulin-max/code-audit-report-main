# CSS Audit Reference

Use for CSS, SCSS, LESS, and webpage style audits. Refer to Google HTML/CSS Style Guide, MDN, W3C standards, accessibility practices, and enterprise design-system conventions.

## Coding Standards

- Use consistent naming such as BEM, utility classes, CSS Modules, or local design-system conventions.
- Avoid excessive selector specificity and global overrides.
- Keep cascade boundaries clear; avoid `!important` except documented escape hatches.
- Use design tokens for color, spacing, typography, z-index, and breakpoints.
- Remove dead styles and duplicated declarations.

## Accessibility And UX

- Preserve focus-visible states and keyboard navigation.
- Maintain color contrast for text, icons, borders, and states.
- Support responsive layouts without overlapping text or controls.
- Respect reduced motion preferences.
- Avoid layout shift from hover states or late-loaded assets.

## Security And Privacy

- Avoid external font/style imports that leak information or violate CSP.
- Do not use CSS to hide security-critical state or authorization-only content.
- Check clickjacking-prone overlays and pointer-events misuse.

## Performance

- Avoid huge unused CSS bundles.
- Minimize expensive selectors and layout-thrashing animations.
- Prefer transform/opacity for animations.
- Audit critical rendering path for above-the-fold CSS.

## Tooling

Recommended tools:

- Stylelint
- Prettier
- Lighthouse
- axe or accessibility test tools
- Browser DevTools coverage
