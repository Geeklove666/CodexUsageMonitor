# Codex Quota Monitor — DESIGN.md

> Native macOS design specification for a Codex usage and quota monitoring app.
> Visual direction: Apple Liquid Glass, calm system utility, information-first.

## 1. Source of Truth

This file is the visual source of truth for the product. Product requirements and accessibility requirements override decorative preferences. When this document conflicts with native macOS behavior, prefer the current Apple Human Interface Guidelines and standard SwiftUI/AppKit components.

Do not invent new colors, spacing values, corner radii, shadows, or component variants unless this file is updated first.

## 2. Product Definition

The app helps people understand Codex allowance without repeatedly opening account pages or discovering a limit only after work is interrupted.

Primary jobs:

1. Show current allowance and remaining capacity at a glance.
2. Show when each allowance window resets.
3. Explain recent usage and trend without creating anxiety.
4. Notify the user before a threshold is reached.
5. Clearly communicate stale, unavailable, estimated, or unsupported data.

The product has two surfaces:

- **Menu bar surface:** instant status, reset time, refresh, and open-dashboard action.
- **Dashboard window:** allowance details, history, alerts, data source, and preferences.

The app must never imply that estimated or locally inferred usage is authoritative. Every value has a visible data status: `live`, `cached`, `estimated`, `unavailable`, or `unsupported`.

## 3. Design Character

The interface should feel:

- Native to macOS, quiet, precise, and trustworthy.
- Lightweight enough to remain open all day.
- Informative without resembling a trading terminal.
- Dimensional through system materials, not ornamental gradients or glass cards everywhere.
- Friendly during normal use and direct during limit conditions.

Use Apple's Liquid Glass as a functional layer for navigation, controls, toolbars, popovers, and transient interactions. Keep usage data, charts, tables, and explanatory text in the content layer using standard system backgrounds and materials.

## 4. Platform and Technology

- Primary platform: macOS 26 or later.
- Preferred implementation: SwiftUI with native macOS scene, toolbar, sidebar, menu, popover, chart, table, settings, and notification APIs.
- Use system components first so Liquid Glass behavior, contrast, vibrancy, hover, focus, and accessibility adapt automatically.
- Custom Liquid Glass is permitted only for a small number of important floating controls.
- If supporting macOS 15 or earlier, preserve hierarchy with standard materials; do not imitate Liquid Glass using static translucent fills.

## 5. Information Architecture

### Menu Bar Popover

Order from top to bottom:

1. Product identity and data freshness.
2. Primary remaining allowance.
3. Reset time and compact progress visualization.
4. Other active allowance windows, if available.
5. Refresh and Open Dashboard actions.

Keep the popover between 320 and 360 points wide. Avoid scrolling in the default state. If more than three allowance windows exist, show the three most relevant and provide “View all”.

### Dashboard Window

Use a native split-view layout.

Sidebar destinations:

- Overview
- Usage History
- Alerts
- Data Source
- Settings

Default window size: `960 × 680 pt`.
Minimum window size: `720 × 520 pt`.

The Overview content order is:

1. Page title, freshness indicator, and Refresh toolbar action.
2. Primary quota summary.
3. Secondary allowance windows.
4. Usage trend.
5. Reset schedule and active alerts.
6. Data-quality note when needed.

## 6. Liquid Glass Rules

### Use Liquid Glass for

- Window toolbar and native sidebar treatment.
- Menu bar popover chrome.
- Search, filtering, segmented controls, and toolbar actions when supplied by the system.
- A floating time-range control over a chart, only when it materially improves navigation.
- A single emphasized primary action when one is necessary.

### Do not use Liquid Glass for

- Quota summary cards.
- Every chart container or table row.
- Decorative background panels.
- Status badges, progress fills, or large colored surfaces.
- Nested glass-on-glass containers.

Use the regular glass variant by default. Do not use clear glass because this product has no rich photo or video background that needs to remain visible.

Never hard-code the opacity, blur, refraction, border highlight, or shadow of native Liquid Glass. Let the operating system render and adapt the material.

## 7. Color System

Use semantic system colors. Values below are roles, not fixed hex colors.

| Token | SwiftUI role | Usage |
|---|---|---|
| `color.canvas` | window/content background | Main content layer |
| `color.surface` | secondary system background/material | Cards and grouped sections |
| `color.text.primary` | `.primary` | Titles, values, essential labels |
| `color.text.secondary` | `.secondary` | Metadata and explanations |
| `color.separator` | `.separator` equivalent | Quiet structural separation |
| `color.accent` | user/app accent color | Selection, primary action, current series |
| `color.success` | `.green` | Healthy status when a status color is necessary |
| `color.warning` | `.orange` | Approaching user-defined threshold |
| `color.critical` | `.red` | Exhausted quota or failed action |
| `color.info` | `.blue` | Informational state or live connection |

Rules:

- Normal quota states are neutral or accent-colored, not green by default.
- Warning begins only at the configured threshold; suggested default is 20% remaining.
- Critical begins at 5% remaining or when a limit is exhausted.
- Never rely on red, orange, or green alone. Pair color with a symbol and text label.
- Tint only one primary control in a local action group.
- Charts use at most one accent series plus neutral comparison series.

## 8. Typography

Use San Francisco through semantic system text styles. Do not bundle or imitate an Apple font.

| Role | Style guidance |
|---|---|
| Window title | Native navigation/title style |
| Page title | `.largeTitle`, semibold, primary |
| Section title | `.title3`, semibold |
| Quota value | `.system(size: 34, weight: .semibold, design: .rounded)` with monospaced digits |
| Card title | `.headline` |
| Body | `.body` |
| Metadata | `.subheadline` or `.caption`, secondary |
| Table values | `.body.monospacedDigit()` |

Rules:

- Show the number first and unit second: `72% remaining`, `14.2K tokens`, or `2 h 18 min`.
- Use monospaced digits for changing counters, percentages, times, and chart axes.
- Do not use all-caps headings.
- Do not reduce essential text below the semantic caption size.
- Support Dynamic Type and increased text sizes without truncating quota meaning.

## 9. Spacing and Geometry

Base spacing scale: `4, 8, 12, 16, 20, 24, 32, 40 pt`.

- Window content inset: `24 pt`; use `20 pt` in compact widths.
- Section separation: `24–32 pt`.
- Card internal padding: `16 pt`.
- Compact row gap: `8 pt`.
- Grid gap: `16 pt`.
- Small control gap: `8 pt`.
- Standard content card radius: `12 pt`.
- Small badge radius: capsule.
- Avoid large 24–32 pt “mobile-style” rounded cards in the desktop window.
- Prefer aligned edges and a calm grid over staggered decorative layouts.

## 10. Depth and Surfaces

Content cards use a standard secondary background or grouped material with a subtle separator. Avoid custom drop shadows in the content layer.

Hierarchy is created by:

1. Native Liquid Glass navigation/control layer.
2. Main content background.
3. Quiet grouped surfaces for summaries.
4. Typography and spacing.

Do not use glowing borders, neon effects, colored shadows, background mesh gradients, or fake specular highlights.

## 11. Core Components

### Quota Summary

Each summary contains:

- Allowance name.
- Remaining value as the dominant element.
- Human-readable reset time.
- Progress indicator.
- Data status and last-updated time when not live.
- Optional comparison to the previous equivalent period.

Prefer “72% remaining” over an ambiguous “72%”. Show the absolute amount only when the source supports it reliably.

### Progress Indicator

- Use a linear indicator for precise comparison between allowance windows.
- Use a circular gauge only in the menu bar status item or a single hero summary.
- The empty portion remains neutral.
- Animate changes only after a confirmed refresh, using a subtle system animation.
- Add an accessibility value such as “72 percent remaining; resets in 2 hours”.

### Status Badge

Allowed labels:

- Live
- Updated 4 min ago
- Estimated
- Offline
- Data unavailable

The badge must remain visually secondary to quota values. Use a symbol plus text for warning and failure states.

### Usage Chart

- Default to a restrained line or area chart.
- Display one primary series.
- Use quiet grid lines and semantic labels.
- Provide hover inspection with exact time and value.
- Do not smooth data in a way that changes its meaning.
- Mark resets as labeled vertical rules.
- Never display invented precision.
- Supply a text summary and accessible representation of the trend.

### Allowance Table

Columns when space permits:

- Allowance
- Used / Remaining
- Reset
- Status

At compact widths, collapse each row to a two-line layout. Keep the allowance name and remaining value visible; move metadata to the second line.

### Refresh Action

- Place Refresh in the toolbar and menu bar popover.
- While refreshing, retain existing data and show subtle progress.
- Do not replace the entire dashboard with a blocking spinner.
- If refresh fails, keep cached values visible and label their age.

### Alerts

Alert rows contain threshold, delivery method, affected allowance, and enabled state. Use native toggles and forms. Destructive actions use confirmation only when recovery is difficult.

## 12. Menu Bar Status Item

The status item should use a simple SF Symbol-compatible monochrome glyph. Do not display a colorful logo in the menu bar.

Display modes:

- Icon only.
- Icon + remaining percentage.
- Icon + reset countdown.

Use a warning variant only when a configured threshold is crossed. Do not continuously animate the menu bar item. VoiceOver must announce the remaining allowance and freshness state.

## 13. States and Feedback

### Loading

Preserve layout. Use short neutral placeholders only on first load. Do not use shimmering placeholders indefinitely.

### Empty

Explain why no history exists and what will create it. Provide one relevant action, such as “Refresh data” or “Configure source”.

### Stale

Keep the last known values visible. Add “Updated [time]” and a refresh action. Never present cached data as live.

### Offline

Use a nonblocking inline notice. The app remains navigable and continues to show cached history.

### Unsupported or unauthenticated source

State the limitation plainly. Do not fabricate quota figures. Provide setup or documentation actions only when they are valid.

### Threshold warning

Use orange, a warning symbol, remaining amount, and reset time. Avoid alarmist copy.

### Exhausted

Use red sparingly. State what is unavailable and when the allowance is expected to reset. Do not show celebratory or gamified visuals.

## 14. Motion

- Use system-standard transitions and durations.
- Animate progress only when values change.
- A chart update may crossfade or interpolate once; it must not pulse continuously.
- Hover and press feedback should come from native controls.
- Respect Reduce Motion. Replace morphing or movement with a crossfade when necessary.
- Do not animate decorative glass blobs or backgrounds.

## 15. Accessibility

- Support Light, Dark, Increase Contrast, Reduce Transparency, Reduce Motion, VoiceOver, keyboard navigation, and Full Keyboard Access.
- Never encode quota state by color alone.
- Maintain readable content when transparency is disabled.
- Give chart points, gauges, buttons, and menu bar items meaningful accessibility labels and values.
- Preserve visible keyboard focus.
- Keep pointer targets at least `24 × 24 pt`; prefer standard macOS control sizing.
- Localize dates, numbers, percentages, time zones, and reset countdowns.
- Avoid phrases such as “today” when the allowance resets in a different time zone unless the time zone is explicit.

## 16. Window Adaptation

### Wide: 960 pt and above

- Visible sidebar.
- Two-column quota summary grid when useful.
- Full chart and allowance table.

### Medium: 720–959 pt

- Collapsible sidebar.
- Single-column summaries where labels would otherwise compress.
- Preserve chart height and reduce secondary metadata.

### Minimum window

- Prioritize primary remaining allowance, reset time, and refresh.
- Permit vertical scrolling.
- Never introduce horizontal scrolling for the main dashboard.

## 17. Content Style

Use concise, factual labels:

- “72% remaining”
- “Resets in 2 h 18 min”
- “Updated 4 min ago”
- “Estimated from local activity”
- “Live quota data is unavailable”

Avoid vague or stressful language:

- “You are running out fast!”
- “Usage health”
- “AI power level”
- “Unlimited productivity”

Use “allowance” or the exact provider term instead of mixing “credits”, “quota”, “tokens”, and “usage” as if they are equivalent.

## 18. Data Integrity Rules

- The UI must render missing values as unavailable, never as zero.
- Estimated values must display an `Estimated` label adjacent to the value.
- Show the source and timestamp in the Data Source view.
- Separate different reset windows; never merge them into one percentage unless the provider defines a combined allowance.
- If the source definition changes, preserve raw historical data and mark incompatible comparisons.
- Never ask users to paste secrets into an ordinary text field; use Keychain-backed secure entry where credentials are legitimately required.

## 19. Do and Don't

### Do

- Use native SwiftUI/AppKit navigation and controls.
- Let content scroll beneath navigation where the system supports it.
- Keep the most important remaining value immediately scannable.
- Use semantic colors and system materials.
- Explain freshness and estimation honestly.
- Test real long labels, large numbers, dark mode, and narrow windows.

### Don't

- Do not make every card translucent glass.
- Do not reproduce an iPhone layout inside a Mac window.
- Do not use giant pills for ordinary content containers.
- Do not tint every toolbar control.
- Do not add decorative gradients behind data to make glass visible.
- Do not hide stale or estimated status in a tooltip.
- Do not infer an official Codex quota API from the visual design.

## 20. Acceptance Checklist

A screen is complete only when:

- It uses defined semantic tokens and native components.
- Liquid Glass appears only in navigation, controls, or transient functional layers.
- Every quota value includes its meaning, reset context, and freshness when relevant.
- Loading, empty, stale, offline, unsupported, warning, and exhausted states are handled.
- Keyboard and VoiceOver paths work.
- Light/Dark Mode, Increase Contrast, Reduce Transparency, and Reduce Motion have been tested.
- The window works at minimum and default sizes without horizontal overflow.
- No unsupported data source or precision is implied.

## 21. Agent Prompt Guide

Use this instruction when asking an AI coding agent to build a screen:

> Read `DESIGN.md` before changing UI code. Build a native macOS interface with SwiftUI system components. Treat Liquid Glass as the navigation and control layer, not as a decorative card style. Use only semantic colors and the spacing/components defined here. Preserve explicit live, cached, estimated, unavailable, and unsupported data states. Do not assume an official Codex quota endpoint. After implementation, audit the result against the acceptance checklist and report any intentional deviation.

