# v1.0.0.0 — Initial Release

Bi-Directional Pallets turns every refillable tool into a two-way pallet hub. Empty pallets into your tool, OR pour leftover product back into nearby empty/partial pallets so nothing is wasted.

## Features

- **Pull-fill** — chain-load any tool (seeders, sprayers, trailers) from a stack of pallets or big-bags with a single command. When one drains, the mod automatically chains to the next compatible pallet.
- **Push-fill** — pour leftover product from your tool back into nearby empty or partially-filled pallets. Great for emptying a sprayer at the end of a job without dumping product on the ground.
- **Multi-Pallet Mode** — when on, push-fill spreads the transfer across every eligible pallet at once, and pull-fill drains additional compatible pallets in parallel with the picked one. Off by default for steady, single-pallet transfers.
- **On-screen overlay** — floating labels above each nearby pallet show selection order, fill percentage, and current/capacity in litres (e.g. `#1  47%` / `2350 / 5000 L`). Colourblind palette included.
- **Manual selection** — cycle the pick to choose which pallet a chain starts from.
- **Per-tool toggles, persisted with savegame** — pull-fill and push-fill on/off are remembered per vehicle.
- **Multiplayer-aware** — all transfers are server-authoritative via dedicated event classes.

## Controls

Three keybindings, all under the **Vehicle** category, **unbound by default** (assign them in Options → Controls):

- **Bi-Dir: Toggle Pull-Fill** — load tool from pallets
- **Bi-Dir: Toggle Push-Fill** — empty tool into pallets
- **Bi-Dir: Cycle Pallet Selection** — wraps forward; only active while the overlay is on and you're not currently filling

## Settings

In General Settings → "Bi-Directional Pallets":

- **Pallet Selection Overlay** — On / Off (default On)
- **Push-Fill Rate** — 150 / 300 / 600 / 1000 / 1500 / 2500 L/s (default 600 L/s)
- **Multi-Pallet Mode** — On / Off (default Off)

Settings are saved per-player to `modSettings/BiDirPalletsSettings.xml`.

## Languages

English, German, French. Other languages fall back to English.

## Compatibility

- FS25
- Multiplayer supported
- Auto-attaches to every vehicle type that has a fillable tool — no per-vehicle XML edits needed
- Excluded by design: tractors, locomotives, train trailers, receiving hoppers, balers, tedders, pallets themselves
