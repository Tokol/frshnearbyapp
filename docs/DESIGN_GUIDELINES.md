# FRSH nearby Design Guidelines

Design system for the production FRSH nearby app, extracted and cleaned up from the
prototype (`lib/core/theme/app_theme.dart` + `lib/features/marketing/presentation/marketing_tokens.dart`).

Brand personality: **fresh, natural, trustworthy, friendly**. Green-first palette,
soft off-white backgrounds, rounded shapes, bold headings.

---

## 1. Colors

### Brand greens (primary)

| Token | Hex | Use |
|---|---|---|
| `primary` | `#2F6B45` | Main brand green. Buttons, links, active states, Material 3 seed color |
| `primaryDeep` | `#184D31` | Dark green. Hero backgrounds, footer, emphasis panels |
| `primaryContainer` | `#DCEBDD` | Light green fill. Selected nav indicator, chips, soft highlights |

### Neutrals

| Token | Hex | Use |
|---|---|---|
| `ink` | `#183326` | Primary text (dark green-black, not pure black) |
| `muted` | `#647267` | Secondary text, captions, placeholders |
| `background` | `#F9FAF5` | App/scaffold background (warm off-white) |
| `paper` | `#F7F8F1` | Alternate section background (landing) |
| `mist` | `#EFF4E9` | Tinted surface — cards on paper, soft green wash |
| `line` | `#E2E8DD` | Borders, dividers, input outlines |
| `surface` | `#FFFFFF` | Cards, sheets, app bar |

### Accents (use sparingly, < 10% of any screen)

| Token | Hex | Use |
|---|---|---|
| `harvestGold` | `#E9CD7A` | Decorative highlights, ratings, badges |
| `amber` | `#E09A24` | Warnings, "low stock" states, deal tags |
| `amberDeep` | `#B36B18` | Text on amber-tinted backgrounds |
| `lakeBlue` | `#315A87` | Informational accents, secondary illustrations |
| `olive` | `#6E7255` | Illustration/scenery tone only — not for UI controls |

### Semantic

| Token | Hex | Use |
|---|---|---|
| `success` | `#2F6B45` | Reuse primary — confirmations, "in stock" |
| `warning` | `#E09A24` | Caution, expiring deals |
| `error` | `#BA1A1A` | Errors, destructive actions (Material 3 error from seed) |

### Rules

- Dark text (`ink`) on light backgrounds; white text only on `primary`/`primaryDeep`.
- `muted` is for secondary text only — never for text smaller than 12sp on tinted backgrounds.
- Never place `primary` text on `mist`/`primaryContainer` for body copy; use `ink`.
- Keep generating the Material 3 scheme with `ColorScheme.fromSeed(seedColor: Color(0xFF2F6B45))` so all derived roles (error, outline, etc.) stay consistent.

---

## 2. Typography

The prototype used `Arial` as a placeholder. **For production, switch to a real
brand font.** Recommended: **Nunito Sans** (friendly, rounded — fits the brand) or
**Inter** (neutral, extremely legible). Both are free on Google Fonts and support
Swedish characters (å ä ö).

The prototype leans heavily on `w800`/`w900` headings — keep that as the brand voice:
**headings are bold and chunky, body is regular.**

### Type scale

| Style | Size | Weight | Use |
|---|---|---|---|
| Display | 36 | w900 | Landing hero headline only |
| Headline | 32 | w900 | Screen hero titles |
| Title L | 22 | w800 | Screen/app-bar titles |
| Title M | 18 | w800 | Card titles, section headers |
| Title S | 16 | w700 | List item titles, dialog titles |
| Body L | 16 | w400 | Primary body text |
| Body M | 14 | w400 | Default body, descriptions |
| Label L | 14 | w700 | Buttons, tabs |
| Label M | 12 | w600 | Chips, badges, nav labels |
| Caption | 12 | w400 | Timestamps, helper text, `muted` color |

### Rules

- Line height ~1.4 for body, ~1.15 for headings.
- Minimum text size 12; never below 11.
- Avoid mid-weights (w500/w600) for headings — the brand look is w700+ or w400, not in-between.
- Prices and quantities: use `w800` + `ink` so they stand out from labels.

---

## 3. Spacing & layout

Use a **4px base grid**. Standard steps: `4, 8, 12, 16, 20, 24, 32, 48`.

- Screen edge padding: **16** (mobile), **24** (tablet/web).
- Between cards in a list: **12**.
- Inside cards: **16** padding.
- Between a section header and its content: **12**.
- Between sections: **24–32**.
- Max content width on web/tablet: **720** for forms, **1100** for landing/marketing.

---

## 4. Shape (corner radius)

| Radius | Use |
|---|---|
| **14** | Buttons, text fields (matches `InputDecorationTheme` / `ElevatedButtonTheme`) |
| **18–20** | Cards, images, bottom sheets (prototype standard: 18 for tiles, 20 for `CardTheme`) |
| **999** (pill) | Chips, tags, filter pills |
| **8** | Small inline elements: badges, thumbnails |

Rule: pick from this set only. Don't introduce 6, 10, 13, etc. — the prototype drifted; the real project should not.

---

## 5. Elevation & borders

- **Flat design**: cards use `elevation: 0` with either a `line` (`#E2E8DD`) border or a tinted background (`mist`) to separate from the page — not shadows.
- Shadows only for floating elements: dialogs, bottom sheets, FABs, dropdowns. Use soft black at ~13% opacity (`0x22000000`), blur 12–24, no hard offsets.
- App bar: flat (`elevation: 0`), `surface` background, `ink` foreground.

---

## 6. Components

### Buttons
- Primary: filled `primary`, white text, height **48**, radius 14, label w700.
- Secondary: outlined, `primary` text + `line` border, same metrics.
- Text button: `primary` text, no background — inline actions only.
- Loading state: replace label with a 20px spinner, disable the button (see `AppButton`).
- One primary button per screen region.

### Text fields
- Filled white, radius 14, `line` border; `primary` border when focused (2px).
- Label above or floating; helper/error text below at 12sp.

### Cards
- White (or `mist` on white pages), radius 18–20, padding 16, no shadow.
- Product/listing cards: image top with radius matching card, title w800, price w800 `ink`, meta in `muted`.

### Navigation
- Bottom `NavigationBar`: height **72**, indicator `primaryContainer` (`#DCEBDD`), labels always visible, 12sp w600.
- Active icon/label: `primary`-tinted; inactive: `muted`.

### Chips / badges
- Pill shape, 12sp w600. Neutral: `mist` bg + `ink` text. Status: amber family for warnings/deals, `primaryContainer` + `ink` for positive.

### States
- Empty / error / loading states use the shared widgets (`empty_state.dart`, `error_state.dart`, `loading_state.dart`) — consistent icon + title (w800) + `muted` body + optional action button.

---

## 7. Iconography & imagery

- Icons: Material Symbols (rounded style preferred to match soft shapes), 20–24px, `ink` or `muted`; `primary` only when interactive/active.
- Photos: real produce/farm photography, warm and bright; radius 18 to match cards; always provide a `mist`-colored placeholder while loading (see `AppImage`/`FarmAvatar`).
- Illustration accents (farm scene style) use `deepGreen`, `olive`, `harvestGold`, `lakeBlue` — keep illustrations out of functional UI.

---

## 8. Accessibility

- Contrast: `ink` on `background`/`paper`/`mist` and white on `primary`/`primaryDeep` all pass WCAG AA. Do **not** use `harvestGold` or `muted` for text on white below 14sp.
- Touch targets: minimum **48×48** (button height already enforces this).
- Never rely on color alone for status — pair with an icon or label (e.g. "Low stock" text next to amber dot).
- Support Swedish and English string lengths — buttons and chips must tolerate ~30% longer text without truncating meaning.

---

## 9. Dark mode (future)

The prototype is light-only. When adding dark mode, generate it from the same seed
(`ColorScheme.fromSeed(seedColor: 0xFF2F6B45, brightness: Brightness.dark)`) rather
than hand-picking colors, and map: `background → #121712`, `ink → #E3E8E0`,
`line → #3A423A`, keep accents desaturated ~20%.

---

## 10. Do / Don't

**Do**
- Keep screens mostly neutral (off-white + white + green) with one accent at a time.
- Use bold (w800/w900) headings — it's the brand voice.
- Reuse the shared widgets in `lib/core/widgets/` instead of restyling per screen.

**Don't**
- Don't introduce new hex values outside this file — add a token first.
- Don't use pure black (`#000000`) for text or pure grey for borders.
- Don't mix radius values on one card (image, card, and buttons inside should feel related: 14/18 family).
- Don't use more than one gold/amber element per card.
