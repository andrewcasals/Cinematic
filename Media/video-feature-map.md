# Cinematic - video feature map

Everything the addon does, grouped into segments for the video. Each feature has
**what to show** and **how to get it on camera** (keybind, slash command or in-game
event). `[F]` = WoW Forever only, `[R]` = retail only. The Media folder isn't
packaged, so this file never ships.

Tick `[x]` as you record.

---

## Recording toolkit

Ways to start things on demand instead of waiting for them:

| Want | Do |
|---|---|
| Toggle CineMode | Keybind *Toggle CineMode*, or `/cine` |
| Hide UI but keep the look (clean B-roll) | Keybind *Hide the UI (keep the look)*, or `/cine hideui` |
| AFK / Cozy / Vista / Fish / Tele cam now | Keybinds *Start the ... camera* |
| Death cam without dying | `/cine deathtest [seconds]` (or the *Test the death camera* keybind) - stand still |
| Fly-by mid-flight | `/cine flyby` |
| Time-of-day title | `/cine timetest dusk`, or `/cine timetest all` (every phase, 8 s each) |
| Every time-of-day tint, with its title | `/cine tinttest [seconds each]` (8 s each, Dawn to Night, AFK camera circling; again to stop) |
| Depth of field on screen | `/cine doftest [seconds]`, `/cine doftest strength 40` |
| Death song | `/cine songtest` (again to stop) |
| Switch the whole setup | Profiles page, or the minimap button |

Tip: record on the **Immersive** profile, then switch profile only for the
segment that compares them.

---

## 1. Cold open (no talking, 20-40 s)

- [ ] Flight take-off -> sway -> fly-by looking back -> settle -> landing, music fading in
- [ ] Campfire at dusk, cozy cam close and swaying, warm tint, vignette
- [ ] Hearthstone tele cam spin-out -> arrival behind you
- [ ] Cut to a fight: UI snaps back the moment you pull

## 2. The core idea: CineMode

- [ ] **UI fades between fights**, letterbox bars slide in (show before/after side by side)
- [ ] **Comes straight back** on combat, targeting an enemy, opening a window
- [ ] **Calm Timer**: frames hold for a while after a fight, then fade
- [ ] **Turns itself off where you'd rather have the full UI** - open world, inns, cities, dungeons, raids, PvP, groups (CineMode page)
- [ ] Letterbox size: `/cine size 0-40`

## 3. Smart reveals (the UI when you need it)

- [ ] **Hover anything** to see it (unit frames, bars, minimap)
- [ ] **Mouseover groups**: hovering one frame brings up its group (Mouseover page)
- [ ] **Chat pops up** on a new message - choose message types and channels; only for windows you can see; whisper tabs keep chat up until read
- [ ] Chat peeks on group loot rolls, level-up, skill-up, guild members
- [ ] **Portrait** shows while you recover (health/mana)
- [ ] **Buffs flash up** when gained; debuffs peek separately
- [ ] **Durability** figure shows while gear is damaged or broken
- [ ] **Quest tracker** reveals on objective progress and new quests; quest timer
- [ ] **Minimap stays up while tracking** herbs/minerals/treasure/fish; reveals on a minimap ping
- [ ] Combat text / floating text: option to hide all floating text (XP, damage, healing)

## 4. Stay cinematic in combat

- [ ] Choose which frames show in fights / enemy target / friendly target (**Standard Frames** grid)
- [ ] Letterbox and tint can stay or step aside during fights
- [ ] Cast bar row: hide in CineMode except for fights, no flash
- [ ] **Cooldown Manager** `[R]`: spells shown only when ready in combat, *Show Early* per spell, fade in over half a second
- [ ] **Swing timer** bars (ranged bar on top, per class)
- [ ] Extra action button always shown in CineMode `[R]`
- [ ] Raid/party frames: role icons, names, threat glow fade; out-of-range dimming kept

## 5. Names and nameplates

- [ ] Hide names and plates in CineMode
- [ ] Per kind (mobs, NPCs, your faction, other faction, pets, totems) x place (fights, open world, cities, inns, dungeons, raids, PvP flagged / BGs & arenas)
- [ ] *Always* column; target and group switches
- [ ] Plater support - its plates fade too

## 6. The cameras (the big segment - one shot each)

Each hands over to the next seamlessly; worth one shot that chains two.

- [ ] **Flight Cam** - swing behind at take-off, sway, settle before landing. Learns each route's timing (mention Frequent Flier). **Fly-bys** turn round to look back.
- [ ] **AFK Cam** - stand still or go AFK: slow orbit, drifting in and out
- [ ] **RP Walk Cam** - auto-walk: gentle sway, holds through turns then glides round; steer with the mouse
- [ ] **Auto-run Cam** - looks ahead down the road; on skyriding mounts `[R]`; gamepad auto-run `[F]`
- [ ] **Cozy Cam** - campfire, `/sit`, `/sleep`, `/dance`, `/kneel`, chair/bench, drawing your weapon (hero shot), logout countdown away from an inn
- [ ] **Tele Cam** - Hearthstone/teleport: spins faster as it zooms in, swings behind on arrival; cancel the cast and it unwinds
- [ ] **Vista Cam** - `/stare`: lines up behind, lowers, takes in the view
- [ ] **Fish Cam** - bobber in view; right-click (or gamepad button) to recast
- [ ] **Quest Cam** - eases in to a dialogue shot past your shoulder; slow zoom out after, quick when you walk off; over-the-shoulder (experimental)
- [ ] **Death Cam** - rises and circles your body, cold dimmed screen, its own song
- [ ] **Depth of field** haze round the edges, per camera
- [ ] **Indoor limits** - camera stays out of walls in buildings and caves

### Camera control pages

- [ ] **Camera Triggers**: pick which camera each event starts (or none), music per event, and the **CineMode column** - "screensaver" mode: normal UI while playing, CineMode once idle
- [ ] **Camera Modes** grid: turn each camera off per place; per-camera Calm Timer
- [ ] Per-camera pages: starting, rotation, height, turning, DoF sliders (show one briefly)

## 7. Colour and mood

- [ ] **Screen tints**: warm, cool, night, dusk, sepia, dreamy, custom + vignette; strength drifts gently
- [ ] **Time of day**: moonlit blue -> dawn pink -> golden hour (`/cine timetest all` for the title cards); game time or your clock; tune each phase
- [ ] **Time-of-day title** under the zone name with a sound (rooster, bells, frogs, owl, wolf)
- [ ] **Zone moods**: snowfields, deserts, plaguelands, smoky Ironforge, golden Westfall; every expansion on retail (Hellfire, Voidstorm); smooth fades at borders; sub-areas like Theramore; set any zone yourself
- [ ] **Inn glow** - step inside and it warms up
- [ ] **Weather** greys/colours the scene (clients that report weather)
- [ ] Effects outside CineMode too (Visual Effects grid with *Always*)

## 8. Music and atmosphere

- [ ] Music fades in as a camera starts, out when the UI returns
- [ ] Which cameras start music (per trigger)
- [ ] No music while away (unless you want it)
- [ ] Pause when leaving camera modes; mute in combat / cities / inns / instances / PvP
- [ ] **Music fatigue** - not again too soon
- [ ] Your sound settings always restored, even after a crash

## 9. Quality of life `[F]`

- [ ] **Campfire Sit button** - hover a campfire, click the icon at the cursor to sit (no `/sit`); has its own camera trigger
- [ ] **Stand up with Camp Benefits** - stands you up when the buff lands
- [ ] **Fishing**: cast with right-click or a gamepad button, CineMode or not

## 10. Chat bubbles and tooltips

- [ ] **Chat bubbles** page: hide by place, text only (no bubble art), text size
- [ ] **Tooltips** page (advanced, off by default): hide tooltips in CineMode/combat/camera modes, "But still show" exceptions; hold-key keybind to show them, toggle keybind

## 11. Works with your setup

- [ ] **Gamepad mode** `[F]`: its bars, button hints and reticle fade like any frame
- [ ] **3rd Party Frames**: Details!, Bartender4, Plater, EllesmereUI, Cooldown Manager Centered, Forever Enhanced Cooldown Manager - supported out of the box
- [ ] **Custom frames**: fade any addon frame or keep it visible - **Add mode** / `/cine add` to click-pick one (e.g. ChatCopyPaste's button)
- [ ] **Hide the UI, keep the look** keybind - great for screenshots (show a screenshot being taken)

## 12. Easy to set up

- [ ] **Welcome window** for new players: pick a profile on first login
- [ ] **Profiles**: Immersive, Immersive (CDM), Lite, VFX Only, Camera Only, Solo Explorer, Pure Cinema, or your own
- [ ] **Share profiles**: Export a string, Import a friend's (show copy -> paste)
- [ ] **Minimap button**: quick tint/vignette strength, music, turn off in combat, pause timer
- [ ] **Reset page** button on every settings page
- [ ] **Keybinds** page
- [ ] **10 languages**: English, Español, Deutsch, Français, Русский, Português, Italiano, 한국어, 简体中文, 繁體中文 - flick the Language dropdown on camera
- [ ] Runs on every client, retail to Classic; made first for WoW Forever; settings only show where they apply

## 13. Outro

- [ ] Bug reports: `/cine log` -> Ctrl+C -> paste; `/cine panic` / `/cine resume`
- [ ] CurseForge link, feedback welcome
- [ ] Closing shot: AFK cam orbit at night with the UI gone

---

## Shot list by location (to batch recording)

- **A flight path** (long, scenic): Flight Cam, fly-bys, music, time-of-day tint
- **A campfire**: Sit button, cozy cam, Camp Benefits stand-up, inn-less logout countdown
- **An inn**: inn glow, CineMode turning off/on per place, chat bubbles
- **A city** (Ironforge for the smoky tint): zone mood, nameplates per place, chat pops
- **Water**: Fish Cam, right-click recast
- **Open-world mobs**: UI snap-back, combat frames, Calm Timer, Cooldown Manager / swing timer
- **A scenic overlook**: `/stare` vista, AFK cam, DoF, letterbox size
- **Any quest hub**: Quest Cam, quest tracker reveals
- **Zone border** (e.g. Westfall <-> Elwynn, Dun Morogh snow): zone tint fade
- **Settings UI**: profiles, share, triggers grid, language swap, Add mode
