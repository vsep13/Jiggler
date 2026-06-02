# Jiggler Knowledgebase & Design System

This file serves as a persistent record of the user's design preferences, requirements, and rules for the Jiggler application. All agents working on this project must refer to this document first before proposing or implementing changes.

---

## 🎨 App Icon & Aesthetics
- **Style**: Modern macOS Big Sur squircle style.
- **Base**: Borderless deep dark/black squircle with a clean glassmorphic texture and subtle purple-blue neon gradients glowing behind the central logo.
- **Symbol**: A perfect white circular ring enclosing a sharp white navigation/location pointer pointing North-North-West (NNW). 
- **Outer Border**: Absolutely NO outer silver/white metallic frame, border, or stroke on the squircle boundary.

## 🎛️ Menubar Icon
- **Style**: Standard macOS Template icon (`isTemplate = true`) that dynamically and automatically renders in pure white on dark/blue wallpapers and black on light wallpapers.
- **Symbol**: A clean, line-drawn circle enclosing a bold, filled NW pointer, perfectly matching the core App Icon design with mathematically perfect diagonal symmetry (Tip at 4.5, 13.5; Wings at 13.5, 9.5 and 8.5, 4.5; Indent at 10.0, 8.0) which occupies the circular space elegantly.
- **State Indicators**:
  - **OFF (Inactive)**: Dynamic template rendering of the circle outline and bold filled NW pointer.
  - **ON (Active)**: A gorgeous, subtle 18% opacity template fill inside the circle, showing a premium semi-transparent white glow on dark/blue menubars and a semi-transparent black glow on light menubars.
  - **Warning (Battery Guard)**: Warning theme rendering with a thicker (2.0px) circle stroke to denote a paused state.

## ⚙️ Compilation & Build Workflow
- Built in pure Swift using the system's `swiftc` compiler.
- Target Output: `Jiggler` executable and the `Jiggler.app` bundle structure.
- Deprecated declarations are accepted (e.g., using `NSUserNotification` for backward compatibility reasons, matching the simple structure of the app).
