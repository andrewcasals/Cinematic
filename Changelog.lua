-- What's new > New features: the changes worth telling players about, each
-- added by hand (with the user's OK) as it's committed. Newest first by date
-- on the page, whatever the order here.
--   date    when it went in (YYYY-MM-DD)
--   title   a few words; text: a sentence or two, for players
--   page    the settings page it's on (English name, as ns.OpenOptions takes
--           it), for its icon and a Show me button; nil for none
--   client  "forever" or "retail": only listed on that client
-- Title and text go through L like the rest, so add them to esES.lua too.
-- (Every commit is on the All changes page, from ChangelogCommits.lua.)
local _, ns = ...

ns.CHANGELOG_FEATURES = {
	{ date = "2026-10-19", page = "Minimap", title = "Minimap Reveal",
		text = "The faded minimap comes up when ore, herbs or treasure show on it, a quest of yours is " ..
		"done, or another icon appears - with a ping on the node if you like." },
	{ date = "2026-10-19", page = "Nameplates", title = "Role icons",
		text = "A tank, healer or damage icon beside your group members' health bars. Tank and healer " ..
		"icons, and enemy class icons, now show by default." },
	{ date = "2026-10-19", page = "Unit Frames", title = "More unit frame parts",
		text = "Your pet's frame has a row in the Unit frame parts grid, and the PvP icon, the frames' " ..
		"other icons and the target's buffs and debuffs have columns of their own." },
	{ date = "2026-10-17", page = "3rd Party Frames", title = "WeakAuras support",
		text = "WeakAuras' auras fade in CineMode; auras anchored to another frame fade with that frame." },
	{ date = "2026-10-17", page = "3rd Party Frames", title = "Questie support",
		text = "Questie's quest tracker and its quest item buttons fade with the Quest tracker row." },
	{ date = "2026-10-17", page = "Mouseover groups", title = "Mouseover group icons",
		text = "Every Mouseover group has its own icon, in a row at the top of the page: click one to go " ..
		"to that group. Groups you make get an icon you pick." },
	{ date = "2026-10-17", page = "Standard Frames", title = "Minimap header pieces",
		text = "The zone name, tracking button, calendar and clock over the minimap fade on rows of their " ..
		"own, and the frame behind the tracking button goes with the header bar." },
	{ date = "2026-10-17", page = "Unit Frames", title = "Unit frame parts",
		text = "Pick which parts of your frame and the target and focus frames show - portrait, name, " ..
		"level, frame art - for you and each kind of unit, to keep just the bars." },
	{ date = "2026-10-17", page = "Chat", title = "Update notices",
		text = "After an update with new features, a line in chat at login says so, with a link to " ..
		"What's new. Turn it off on the Chat page." },
	{ date = "2026-10-17", page = "3rd Party Frames", title = "Horizon Suite support",
		text = "Horizon Suite's quest tracker fades with the Quest tracker row, without flickering on zone changes." },
	{ date = "2026-10-17", page = "New features", title = "What's new",
		text = "The last settings page lists new features, newest first, and every change made to Cinematic." },
	{ date = "2026-10-17", page = "Quest tracker", title = "Quest tracker stays up longer",
		text = "Accepting a quest, or progress on one, can keep the tracker up for the Calm Timer " ..
		"instead of the mouseover time." },
	{ date = "2026-10-17", page = "Unit Frames", title = "Misc page",
		text = "Your portrait, durability figure and pet happiness options have a page of their own " ..
		"in UI Manager." },
	{ date = "2026-10-17", page = "UI Manager", title = "Settings in hubs",
		text = "UI Manager, Camera and Quality of life hold their pages behind a row of icons, " ..
		"with one search box for all of them." },
	{ date = "2026-10-17", page = "3rd Party Frames", title = "More of EllesmereUI fades",
		text = "Its range text, QoL displays (stats, FPS, battle res, Bloodlust, crosshair), combat text " ..
		"and Forever Essentials frames get rows of their own." },
	{ date = "2026-10-17", page = "Standard Frames", title = "Pet portrait and minimap header rows",
		text = "Your pet's portrait and the bar behind the zone name over the minimap fade on their own " ..
		"rows, so the zone name can float by itself." },
	{ date = "2026-10-16", page = "General", client = "forever", title = "Talents button when inspecting",
		text = "A button on the inspect window opens the player's talents, and one on the talents " ..
		"window takes you back." },
	{ date = "2026-10-16", page = "Chat", title = "Speech you can see as a bubble",
		text = "Says and yells whose chat bubble is on screen no longer bring up chat in CineMode." },
	{ date = "2026-10-16", page = "Nameplates", title = "Class icons on nameplates",
		text = "Plate Parts gets Class Icon rows: a class icon beside players' health bars, friendly, " ..
		"enemy or both." },
	{ date = "2026-10-16", page = "Chat bubbles", title = "Outlined bubble text",
		text = "A black outline round the bubbles' letters so they stand out against the world, thin or thick." },
	{ date = "2026-10-16", page = "Graphics+", title = "Graphics+",
		text = "The game's own graphics settings one by one, past what its Graphics menu allows: " ..
		"ground clutter, view distance and more." },
	{ date = "2026-10-16", page = "Nameplates", title = "Duel Vision",
		text = "In CineMode the two players in a duel near you get their nameplates, each duel with its " ..
		"own colour border and class icons." },
	{ date = "2026-10-16", page = "Chat", title = "Attacks on the screen",
		text = "\"Dun Algaz is under attack!\" shows in red where the zone name appears, with your " ..
		"faction's city bell." },
	{ date = "2026-10-16", page = "Chat", title = "Your own messages stay quiet",
		text = "Your own emotes and say, party or guild lines no longer bring up chat in CineMode." },
	{ date = "2026-10-16", page = "General", title = "Windows you can move",
		text = "The game's windows open in the middle of the screen, can be dragged by their title bar " ..
		"and open where you last dropped them. The backpack too." },
	{ date = "2026-10-16", page = "Nameplates", title = "Plate Parts",
		text = "A grid that shows or hides each part of the nameplates in CineMode: health bar, name, " ..
		"cast bar, buffs, level and more." },
	{ date = "2026-10-16", title = "Reset addon",
		text = "A button on the main page puts Cinematic back to a fresh install." },
	{ date = "2026-10-15", page = "Nameplates", title = "Target nameplate grid",
		text = "Choose which target's nameplate shows: enemy, neutral or friendly, players and NPCs apart." },
	{ date = "2026-10-15", page = "Keybinds", title = "Menu wheel",
		text = "Hold a key for a ring of the game's menus: character, spellbook, bags and the rest." },
	{ date = "2026-10-15", page = "General", title = "Drag to equip",
		text = "Picking up a piece of gear opens the character window, ready to drop it on." },
	{ date = "2026-10-15", page = "Hunter", client = "forever", title = "Hunter helpers",
		text = "Right-click pulls with Auto Shot, a smart attack key, smallest ammo stack first, and a " ..
		"Fill quiver button at vendors." },
	{ date = "2026-10-15", page = "Unit Frames", client = "forever", title = "Unhappy pet",
		text = "A hunter's pet frame stays up while the pet isn't happy." },
	{ date = "2026-10-15", page = "Camera Settings", title = "Camera Settings page",
		text = "Each camera's own settings in one place, a section apiece." },
	{ date = "2026-10-15", page = "Keybinds", title = "Camera wheel",
		text = "Hold a key to pick a camera from a ring of icons." },
	{ date = "2026-10-14", page = "General", title = "Campfire Sit button",
		text = "By a campfire a button lets you sit, kneel or lie down, with a cozy camera of its own." },
	{ date = "2026-10-14", page = "Chat bubbles", title = "Chat bubbles page",
		text = "Hide chat bubbles by place, show just their text, and set its size." },
	{ date = "2026-10-14", page = "Profiles", title = "Share profiles",
		text = "Export a profile as a line of text for a friend to import." },
	{ date = "2026-10-14", title = "Ten languages",
		text = "Spanish, German, French, Russian, Portuguese, Italian, Korean and Chinese, with a " ..
		"Language choice on the main page." },
	{ date = "2026-10-14", page = "Standard Frames", title = "Stay up after a fight",
		text = "Frames shown in combat can stay up for the Calm Timer after the fight." },
	{ date = "2026-10-14", page = "Swing timer", client = "forever", title = "Swing timer",
		text = "The game's swing timer fades between fights, with a ranged bar on top." },
	{ date = "2026-10-14", page = "Standard Frames", title = "Party and raid frames",
		text = "Party frames get their own section with role icons and names; raid frames a threat " ..
		"highlight row; the cast bar a row of its own." },
	{ date = "2026-10-13", page = "Tooltips", title = "Tooltips page",
		text = "Hide tooltips in combat or in CineMode, with a key to hold that shows them anyway." },
	{ date = "2026-10-13", page = "CineMode", title = "Hide all floating text",
		text = "An option on the CineMode page hides XP, damage and healing numbers." },
	{ date = "2026-10-13", page = "Quest tracker", title = "Durability figure",
		text = "The armor figure by the minimap shows in CineMode while your gear is damaged or broken." },
	{ date = "2026-10-13", page = "Camera Triggers", title = "Events can start CineMode",
		text = "Tick an event in the CineMode column and it brings CineMode on while its camera runs." },
	{ date = "2026-10-13", page = "Cooldown Manager", title = "Cooldowns when ready",
		text = "In combat the Cooldown Manager can show spells only once they're ready, or early, spell by spell." },
	{ date = "2026-10-12", page = "3rd Party Frames", title = "Plater support",
		text = "Plater's nameplates fade in CineMode like the game's own." },
	{ date = "2026-10-12", page = "3rd Party Frames", title = "Add mode and Bartender4",
		text = "Add any addon's frame by clicking it, and Bartender4's bars fade too." },
	{ date = "2026-10-12", page = "Cooldown Manager", title = "Cooldown Manager page",
		text = "The game's Cooldown Manager fades in CineMode, with an Immersive (CDM) profile." },
	{ date = "2026-10-12", page = "Profiles", title = "Profiles",
		text = "Built-in profiles to start from, picked in a welcome window, and as many of your own as you like." },
	{ date = "2026-10-12", page = "Camera Triggers", title = "Stand still camera",
		text = "Standing still for a while can start a camera, like a screensaver." },
	{ date = "2026-10-12", page = "Minimap", title = "Minimap pings",
		text = "A group member pinging the minimap brings it up, and it can stay open indoors." },
	{ date = "2026-10-12", page = "Mouseover groups", title = "Mouseover groups",
		text = "Frames that come up together when you mouse over any of them." },
	{ date = "2026-10-11", page = "Chat", title = "Whispers keep chat up",
		text = "An unread whisper keeps the chat window up in CineMode." },
	{ date = "2026-10-11", page = "Fishing", title = "Fishing",
		text = "A fishing camera and settings of its own." },
	{ date = "2026-10-11", page = "Gamepad", client = "forever", title = "Gamepad mode",
		text = "WoW Forever's gamepad mode fades with the rest, with a page of its own." },
	{ date = "2026-10-10", page = "3rd Party Frames", title = "EllesmereUI support",
		text = "EllesmereUI's frames fade in CineMode." },
	{ date = "2026-10-10", page = "Quest tracker", title = "Quest tracker page",
		text = "The quest tracker and quest timer fade, and come up when you accept a quest." },
	{ date = "2026-10-09", page = "Camera Modes", title = "Steer while you walk",
		text = "Steer with the mouse while the auto-run and RP walk cameras run." },
	{ date = "2026-10-09", page = "Camera Triggers", title = "Music for AFK and quest givers",
		text = "Going AFK or talking to a quest giver can start a fresh song." },
	{ date = "2026-10-09", page = "Standard Frames", title = "Keep chosen frames up",
		text = "Tick a frame in the CineMode column to keep it shown all through CineMode." },
	{ date = "2026-10-09", page = "Visual Effects", title = "Letterbox and tint by situation",
		text = "The letterbox bars and the tint can be set for each situation." },
	{ date = "2026-10-09", page = "3rd Party Frames", title = "Details! and Cooldown Manager Centered",
		text = "Both fade with the rest of the UI in CineMode." },
	{ date = "2026-10-08", page = "Camera Modes", title = "Tele Cam",
		text = "Hearthstones and teleports get a camera move of their own." },
	{ date = "2026-10-08", page = "Camera Modes", title = "Flight camera",
		text = "Flights get a cinematic camera, with a fly-by and an arrival shot." },
	{ date = "2026-10-08", title = "Retail too",
		text = "One Cinematic for WoW Forever and retail." },
	{ date = "2026-10-08", page = "Camera Modes", title = "Quest cam",
		text = "Talking to a quest giver brings the camera in close, drifting gently once settled." },
	{ date = "2026-10-06", page = "CineMode", title = "Cinematic",
		text = "The UI fades and letterbox bars come in between fights. Combat, casting and opening " ..
		"windows bring it back." },
}
