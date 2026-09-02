# Thinspace — icon design brief

A specification for the application icon and the menu bar icon. Written to be
executed without access to the conversation that produced it.

## Context

The app is a native macOS wrapper around the Claude, Gemini and ChatGPT web
apps. It is deliberately minimal: one shared WebView, one main window, and a
floating **Chat Bar** — a wide, shallow panel summoned by a global hotkey, which
appears over whatever you are doing and disappears again.

It is being renamed from *AI Chat* to **Thinspace**. The icon should be designed
for the new name; do not carry anything over from the current icon, which is a
chat bubble.

Positioning, and the thing the icon has to argue:

> Big AI. Very little app.

## The idea

A **thin space** (U+2009) is a real typographic character: the narrowest
deliberate gap in typesetting, roughly a fifth of an em. The name therefore says
three things at once — the smallest possible amount of space, a slim strip of
screen, and thin rather than bloated.

So the mark does something most icons do not: **it draws an absence.** The
subject is the gap, not the shapes on either side of it. That is the whole
concept, and every decision below follows from it.

## The mark: a split capsule

One shallow horizontal capsule, divided into two unequal pieces by a razor-thin
vertical gap.

- A **short** piece on the left, a **longer** piece on the right.
- The overall silhouette echoes the Chat Bar's real proportions — wide and low.
- The gap between them is the thin space.

**The asymmetry is load-bearing.** Two equal halves read as a pause button, which
is the single most likely way this design fails. Short-plus-long avoids that
read, and carries a second meaning: a small input becoming a longer answer.

As built:

| | value |
|---|---|
| canvas | 1024 × 1024 pt |
| capsule | 724 × 286 pt, centred |
| corner radius | fully rounded (143 pt) |
| split position | 32% along the capsule's length |
| gap width | 22 pt |

The slice is **perfectly vertical**. An angled cut was tried and removed: it
reads as a rendering artifact rather than intent, and it is invisible at menu
bar size anyway.

The capsule sits centred, with generous empty space around it. Do not fill the
canvas.

## Application icon

Authored in **Icon Composer** at `Resources/AppIcon.icon/` — an `icon.json`
manifest plus PNG layers under `Assets/`.

**The slice must be the highest-contrast element in the frame.** This is the
constraint that keeps the concept intact: if the slabs out-contrast the slice,
they become the subject and the idea inverts.

### Three layers, back to front

**The artwork is flat silhouettes only** — no baked gradients, no painted
highlights. Icon Composer's glass renderer supplies all shading, and hand-painted
shading fights it.

| layer | asset | role |
|---|---|---|
| Bloom | `bloom.png` | soft blurred bar behind everything — light spilling out of the slice, and the thing the translucent slabs refract |
| Slice | `gap.png` | crisp bar, drawn wider than the void so the slabs clip it and no antialiasing seam appears at the join |
| Capsule | `capsule.png` | the two slabs, `glass: true` |

The bloom is what makes the glass worth having. Without something behind it a
translucent layer has nothing to refract, and the icon reads flat.

### Appearance variants

The mark is **achromatic and inverts with the system appearance**, so the slice
is always the highest-contrast element.

| | light | dark |
|---|---|---|
| ground | near-white → cool grey gradient | deep blue-graphite → near-black |
| slabs | white glass | `#3A3D47` glass |
| slice | `#0C0D11` | white |
| bloom | cool slate at 16% | white at 80% |

Tinted and clear renditions are derived by the system from these; both were
checked and need no explicit specialization.

Provider colours (Claude orange, Gemini blue, ChatGPT neutral) already tint the
Chat Bar's glass rim at runtime. They must not touch the icon.

### Glass settings

Group level: `lighting: combined`, `specular: true`, `blur: 0.5`,
`translucency: 0.72`, `shadow: neutral @ 0.55`.

## Menu bar icon

**Redraw this. Do not scale the app icon down.** It is a different drawing of the
same idea, at a size where almost nothing survives.

The menu bar uses a **template image**: macOS reads only the alpha channel and
tints the result itself, rendering it dark on light backgrounds and white when
the menu is open or the system is in dark mode. Every colour decision above is
therefore discarded here, along with gradients, shadows and translucency. What
remains is silhouette.

At 18×18 pt:

- Capsule ~16 pt wide, ~6 pt tall, corner radius 3 pt.
- Short piece ~5 pt, long piece ~9 pt, preserving the asymmetry.
- **Gap optically enlarged to ~2 px.** Scaled proportionally from the app icon it
  would land under a pixel and vanish. It must be visibly a gap.
- **Straight vertical slice** — no incline.
- No enclosing squircle, no shadow, no glow, no colour, no offset.

### Two things dropped from earlier drafts

An earlier version lifted the longer piece microscopically higher with a hairline
shadow, as if it had just slid out. It looks good at 1024 px and fails at 18 px,
where a one-pixel offset reads as a misalignment bug. The asymmetry alone already
carries the "something slid out" idea.

An angled cut was also tried, to stop the mark reading as a battery indicator.
It was removed — the asymmetry does that job on its own, and the incline just
looked like a mistake.

## Optional: state through the gap

If menu bar state is wanted later, express it by changing **the gap**, never by
adding a badge — added detail is what destroys legibility at this size, whereas
modifying negative space survives it.

- idle → gap at its narrowest
- Chat Bar open → gap widens one step
- private chat → pieces drawn hollow or dashed

This also implies the product's motion language: everything begins as the short
left segment, a thin gap of light appears, the longer segment slides outward and
expands into the Chat Bar; dismissing compresses it back to the mark. The icon
does what the app does.

## Do not

- No letters, chat bubbles, brains, sparkles, orbs, or provider logos.
- No symmetry between the two pieces.
- No accent colour in the mark — it is achromatic and appearance-adaptive.
- No baked gradients or painted highlights in the layer art; `glass` does that.
- No scaled-down app icon in the menu bar.
- No lift, shadow, or incline in the template version.

## Deliverables

**App icon** — `Resources/AppIcon.icon/` (`icon.json` + `Assets/bloom.png`,
`gap.png`, `capsule.png`, each 1024×1024).

**Toolchain note:** the `ictool` on this machine reports **1.6**, so this must
stay an Icon Composer **1.x** document. Do not add `features`, `refractivity`,
`blur-material`, or `specular-highlight-placement` — Icon Composer refuses to
open a document declaring a feature it does not recognise. Use `blur`, not
`blur-material`.

**Menu bar icon** — `Resources/Assets.xcassets/MenuBarIcon.imageset/`, template
PNGs at 18 / 36 / 54 px with `"template-rendering-intent": "template"`. Consumed
at `App/AIChatApp.swift:193` via `Image(Constants.menuBarIcon)` with
`.renderingMode(.template)`.

If it is ever reauthored as vector, a PDF or a Symbol Set works equally well; the
call site does not change.

**Also rename** the `AI Chat` strings and the bundle display name as part of the
same change, so the icon does not ship attached to the old identity.

## Left open

Decisions deliberately not made here, for whoever executes this:

- Whether the light appearance wants more separation between the white glass
  capsule and the near-white ground; currently it is carried by the shadow alone.
- Whether the bloom should be tighter in dark mode — it is generous now, which
  looks good large but softens below 32 px.
- Whether the alternative mark is worth prototyping: two opposing bracket shapes
  with a narrow opening between them, reading as a portal rather than a panel.
  It is the fallback if the capsule tests as a status indicator, but the capsule
  is the stronger idea because its silhouette is the actual product.
