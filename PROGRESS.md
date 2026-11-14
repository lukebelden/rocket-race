# Rocket Race: Progress

A Godot 4.7 arcade game: steer a rocket up through asteroid fields, dock at stations
for mods, and race other players online. Runs in the browser (web export) and on desktop.

Last updated: 2026-11-14

## Project layout

```
scenes/              game.tscn (the main scene)
scripts/
  autoload/          Profile (accounts, progress), Sound (synth audio), Net (multiplayer socket)
  game/              game loop, rocket, asteroids, stations, planets, stars, rivals, race intro,
                     mod definitions, colour palette
  ui/                profile/hangar/shop screens, pilot cards and portraits, cockpit HUD,
                     caution light, mod icons, hangar background, pause input
sprites/             pilot portraits and rocket sprites used in-game
art/                 art sources and generator scripts (ignored by Godot)
catalog.json         ships, mods, paint, pilots, levels, rewards: read by the game AND the server
server/              Node server: serves build/web, accounts API, multiplayer rooms, admin page
build/web/           the exported web build (committed; the server and Docker image serve it)
deploy/              DigitalOcean Droplet setup: Caddy HTTPS, cloud-init, deploy.sh
design-preview/      screenshots of design ideas (not in git)
```

## Running it locally

1. Start the server: `"C:\Program Files\nodejs\node.exe" index.js` from `server\`
   (Node isn't on PATH on this machine, so use the full path).
2. Open http://localhost:8080 (Firefox).
3. After changing code, re-export the web build before testing in the browser:
   `Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-release Web build/web/index.html`

## Done

### Gameplay
- [x] Steer (A/D) and boost (W / Shift) up through falling asteroids; mouse and touch controls too
- [x] Works on any keyboard layout (keys matched by position)
- [x] Planet levels, droppable boosters, missiles, cockpit HUD with segmented gauges
- [x] Stations on even levels: dock to pick up ship mods
- [x] Mods: radar, hull, RCS, thruster, healing, missile
- [x] Ship computer tips (can be switched off)
- [x] Pause menu (also pauses when the window loses focus)

### Progression and accounts
- [x] Accounts: sign up, log in with username or email, guest play (single player only)
- [x] Separate Single Player and Multiplayer levels, XP and credits
- [x] Hangar: pick pilot, ship, paint, and fitted mods; Shop opens at level 2
- [x] Ships: Scout (1 slot), Cruiser (2 slots, level 10), Hauler (3 slots, level 25)
- [x] 7 paint designs; 10 pilots (Titan is a restricted DEV pilot)
- [x] Email password reset, change email/password, delete account
- [x] Scoreboard tabs (single player / multiplayer)
- [x] Report a problem (bug, player, idea): stored on the server, optionally emailed

### Multiplayer
- [x] Race rooms with room codes over WebSockets, 5 levels per race
- [x] Ready-up room with Hangar, Shop, Ready toggle and Leave
- [x] Pre-race intro: each racer's ship on a launch pad, pilot monitor, airlock that seals on READY
- [x] 5-second launch window and 5-second race countdown
- [x] Race ghosts: see-through copies of each racer's real ship build

### Admin
- [x] /admin page: player reports (tickets) with status and notes
- [x] Player tools: search, give/take XP and credits, unlock/remove items, grant restricted pilots
- [x] Test accounts (create/delete), staff-like usernames blocked at sign-up

### Look and sound
- [x] Gritty sci-fi restyle: gunmetal UI theme, steel palette
- [x] Pixel-art rockets (with paint recolour and animated flame) and 10 pixel-art pilot portraits
- [x] All sound synthesised in code: effects, engine rumble, alarms, button click/hover, menu music
- [x] Music in menus only; volume sliders for Master, Music, Effects

### Hosting
- [x] DigitalOcean Droplet with Docker + Caddy (HTTPS); accounts in SQLite

## Recent changes (2026-11-14)
- Login page: one "Username / email" field; Sign Up opens its own Create Account page
- Web audio: threaded build (audio mixes off the main thread) so typing and resizing
  no longer cause a buzz; the server sends the COOP/COEP headers threads require
- Menu music: removed the clicks between notes and the pops at chord changes
- Sound goes silent when the game loses focus (other window, tab, app) and comes back on return
- Files organised into `scenes/` and `scripts/` (autoload, game, ui); removed the unused starter cube scene

## To do / ideas
- [ ] Redeploy to the Droplet so the live site gets the threaded build and new server headers
- [ ] Merge the `redesign` branch into `main`
- [ ] Check the threaded web build on phones (iOS Safari, Android Chrome)

<!-- Add new items here as the game grows. -->
