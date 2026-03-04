# Corporate Theater

A dark, narrative-driven simulation hacking game built in Godot 4.

## Premise

You are a lone hacker who doesn't buy the story. **ClosedAI** — a powerful AI company — publicly preaches transparency, freedom, and the greater good. Their CEO floods social media platform **Z** with inspirational posts. Their press releases glow with optimism. Their government contracts promise a better world.

You're not convinced.

Using a combination of terminal hacking, social media analysis, fake news investigation, and network infiltration, you must dig through the layers of corporate performance to uncover the dark truth: ClosedAI will do *anything* to dominate the AI market. Anything.

## Gameplay

- **Cinematic intro** — A scripted desktop simulation: a late-night Z Messenger conversation with an inside source sets the stage before you reach the desktop
- **Terminal** — Type commands to scan, connect, and exfiltrate data across four network nodes (`localhost`, `closedai-pub.net`, `closedai-internal.net`, `clearsky-relay.gov`)
- **Network Map** — Visual graph of servers and nodes; click to inspect, states driven by discovered clues
- **Z Messenger** — Encrypted messaging with three contacts (Elena Vasquez, Marcus Tull, Priya Nair); branching conversations, typing indicators, attachment bubbles
- **NEXUS Browser** — Four sites (The Warden, CNX Tech, Redit, DarkPulse); DarkPulse is locked until you dig deep enough
- **Clue System** — 19 clues hidden across the network, news, and social feeds; each one unlocks deeper access or new contacts
- **Notes** — Tabbed investigation journal that logs and severity-sorts every discovery
- **Audio** — Procedural ambient drone and pre-baked SFX (clue sting, contact unlock, terminal keypress)

## Tech Stack

- **Engine:** Godot 4 (GDScript)
- **Export:** HTML5 / WebAssembly
- **Deploy:** GitHub Pages (auto via GitHub Actions)

## Fake World

| Real World | In-Game |
|---|---|
| X / Twitter | Z |
| OpenAI | ClosedAI |
| The Guardian | The Warden |
| CNN | CNX |
| Reddit | Redit |
| iPhone | iSphere |
| Government surveillance | Project Clear Sky / Horizon |
| OpenAI model (secret) | VEIL |
| Maxwell (CEO name) | Maxwell Holt |

## Project Structure

```
corporatetheater/
├── scenes/
│   ├── menus/      # Main menu, cinematic intro sequence
│   └── ui/         # Desktop, terminal, browser, messenger, notes, network map
├── scripts/
│   ├── core/       # Game state, audio, desktop, browser, notes, network map, intro
│   ├── hacking/    # Terminal and network simulation
│   └── social/     # Z Messenger conversation system
└── data/
    ├── lore/       # Intro sequence data
    ├── news/       # Browser site content (4 sites)
    └── posts/      # Z posts and messenger conversation trees
```

## Play

Live at: https://mhsbrian.github.io/corporatetheater

## License

All rights reserved.
