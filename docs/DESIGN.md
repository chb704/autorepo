# Design Vision

This is the source of truth for frontend design review. Replace the placeholders
with real product decisions before you make Design Review a required check.

The goal is not generic taste. The goal is consistency: an agent should be able
to read this file, inspect a PR, and decide whether the change belongs in this
specific product.

## Product Feel

Describe the product in concrete terms:

- Who uses it.
- What they are trying to get done.
- Whether the UI should feel dense, calm, playful, editorial, operational, or
  something else.
- What the interface should never feel like.

## Typography

Record exact choices:

- Font families.
- Type scale.
- Weight usage.
- Line height.
- Where large display type is allowed.
- Where compact UI type is required.

## Color

Record the palette and usage rules:

- Primary, secondary, accent, surface, border, success, warning, and danger colors.
- Dark mode rules if applicable.
- Whether raw hex values are allowed in feature code.
- Colors that are reserved for state, alerts, or charts.

## Spacing And Layout

Record the spacing system:

- Base unit and spacing scale.
- Page width constraints.
- Grid and stack rules.
- Form density.
- Card radius and shadow rules.
- Mobile breakpoints.

## Components

List reusable components and where they live once your app has them. New work
should compose existing components before inventing new ones.

For this skeleton, use this section to describe the component strategy you want
agents to follow when the real app appears.

## Interaction And Motion

Record expectations for:

- Hover, active, focus, loading, empty, and error states.
- Keyboard behavior.
- Motion duration and easing.
- When animation is forbidden because it slows repeated work.

## Accessibility

Record the minimum bar:

- Keyboard navigation.
- Visible focus states.
- Contrast expectations.
- Form labels and error text.
- Reduced motion support.

## Review Rejections

Design Review should block PRs that:

- Add one-off spacing, colors, or typography.
- Rebuild a component that already exists.
- Hide required states such as loading, empty, error, disabled, or focus.
- Use marketing-page composition inside an operational app.
- Ship frontend code that cannot be evaluated against this file because the
  design decision was never recorded.
