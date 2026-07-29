---
name: Digital Librarian
stitch_project: 12817446823472158508
stitch_asset: assets/f071cda70ba241199faf804f89115416
color_mode: dark
body_font: Inter
technical_font: JetBrains Mono
base_spacing: 4px
---

# NoteClaw Digital Librarian

The interface is a durable, precise command center for shared AI memory. It
uses compact information density, a strict baseline grid, thin inner-glow
borders, and tonal depth instead of decorative shadows.

## Color tokens

| Token | Value |
| --- | --- |
| Background | `#020617` |
| Surface | `#0B1326` |
| Surface lowest | `#060E20` |
| Surface low | `#131B2E` |
| Surface container | `#171F33` |
| Surface high | `#222A3D` |
| Surface highest | `#2D3449` |
| Outline | `#424754` |
| Text | `#DAE2FD` |
| Muted text | `#C2C6D6` |
| Neural blue | `#ADC6FF` |
| Strong blue | `#4D8EFF` |
| Memory teal | `#4EDEA3` |
| Violet | `#D0BCFF` |
| Error | `#FFB4AB` |

## Type

- Interface and navigation: Inter.
- Agent IDs, namespaces, MCP tokens, timestamps, and metadata: JetBrains Mono.
- Mobile page titles: 24/32, weight 600.
- Section labels: 10–12px uppercase monospace with increased tracking.
- Body: 16/24.

## Components

- Notebook cards use an 8px radius and a one-pixel low-contrast border.
- Inputs and buttons use a disciplined 4px radius.
- Live agents use a steady teal status dot; syncing state may pulse.
- Technical identifiers appear as dark chips with a teal or blue border.
- Memory and agent grids collapse to a single vertical stack on mobile.
- Bottom navigation exposes Memory, Agents, Chat, and Settings.
