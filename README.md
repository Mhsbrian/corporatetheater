# Corporate Theater

A dark, narrative-driven simulation hacking game built in Godot 4.

## Premise

You are a lone hacker who doesn't buy the story. **ClosedAI** — a powerful AI company — publicly preaches transparency, freedom, and the greater good. Their CEO floods social media platform **Z** with inspirational posts. Their press releases glow with optimism. Their government contracts promise a better world.

You're not convinced.

Using a combination of terminal hacking, social media analysis, fake news investigation, and network infiltration, you must dig through the layers of corporate performance to uncover the dark truth: ClosedAI will do *anything* to dominate the AI market. Anything.

## Gameplay

- **Terminal** — Type commands to scan, connect, crack, and exfiltrate data from ClosedAI's internal network
- **Network Map** — Visual graph of servers and nodes to infiltrate
- **Z Feed** — Fake social media platform; read between the lines of the CEO's posts
- **Phone & Browser** — Browse fake news sites, read leaked documents, follow clues
- **Clue System** — Hidden patterns across public media unlock deeper network access

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
| Government surveillance | Project Clear Sky |

## Project Structure

```
corporatetheater/
├── assets/         # Fonts, sounds, images, music
├── scenes/         # Godot scenes (UI, world, menus)
├── scripts/        # GDScript (core, hacking, social, narrative)
└── data/           # JSON content (missions, news, posts, lore)
```

## Play

Coming soon at: https://mhsbrian.github.io/corporatetheater

## License

All rights reserved.
