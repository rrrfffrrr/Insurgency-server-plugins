# rrrfffrrr's insurgency plugins
#### Plugin list
* [Announcement](#Announcement)
* [Challenge](#Challenge)
* [AutoKick](#AutoKick)
* [RespawnBots](#RespawnBots)
* [CheckpointRespawn](#CheckpointRespawn)
* [Medic](#Medic)
* [SuicideBomber](#SuicideBomber)

#### Why?
[Jaredballou's plugins](https://github.com/jaredballou/insurgency-sourcemod) are don't work on my server.  
So i made this with some codes from jaredballou's.

## Announcement
Show a line that contain in [announcement.txt](announcement.txt).

#### Plugins
[announcement.smx](plugins/announcement.smx)

#### Sources
[announcement.sp](scripting/announcement.sp)

#### Cvars
```
"sm_announce_enabled"	"1"		// Enable announcement
"sm_announce_delay"		"45"	// Announcement delay
```

#### Cmds
```
"sm_announce_reload"	// Reload announce text
```

## Challenge
Show text when connect.  
I didn't change name to connect message because i'm too lazy.

#### Plugins
[Challenge.smx](plugins/Challenge.smx)

#### Sources
[Challenge.sp](scripting/Challenge.sp)

#### Cvars
```
"sm_challenge_enabled"	"0"		// Enable connect message
```

#### Cmds
```
"sm_challenge_reload"	// Reload connect message
```

## AutoKick
Kick everyone who connect.  
For maintenance.

#### Plugins
[AutoKick.smx](plugins/AutoKick.smx)

#### Sources
[AutoKick.sp](scripting/AutoKick.sp)

#### Cvars
```
"sm_autokick_enabled"	"0"		// Kick everyone who connect if it's true
```

## RespawnBots
Respawn bots which isn't alive.  
Optimized version of CheckpointRespawn.
Default cvars not correct.

#### Plugins
[RespawnBots.smx](plugins/RespawnBots.smx)

#### Sources
[RespawnBots.sp](scripting/RespawnBots.sp)

#### Dependencies
[insurgency.games.txt](gamedata/insurgency.games.txt)

#### Cvars
```
"sm_botrespawn_enabled"			"0"		// Enable respawn bots.
"sm_botrespawn_delay"			"1"		// Delay to respawn, 0 will disable respawn.
"sm_botrespawn_rp"				"5"		// Default respawn point. Bot num is (Alive bot number) + sm_botrespawn_rp + (Player number) * sm_botrespawn_rp_add
"sm_botrespawn_rp_add"			"5"		// How many respawn point increase per players
"sm_botrespawn_display"			"1"		// Enable display how many bots remain. (Include respawn number)
"sm_botrespawn_display_delay"	"1"		// Display delay
```

## CheckpointRespawn
Respawn bots which isn't alive.  
It's prototype so having problem with performance.  
Use RespawnBots instead.
Default cvars not correct.

#### Plugins
[CheckpointRespawn.smx](plugins/CheckpointRespawn.smx)

#### Sources
[CheckpointRespawn.sp](scripting/CheckpointRespawn.sp)

#### Dependencies
[insurgency.games.txt](gamedata/insurgency.games.txt)

#### Cvars
```
"sm_botrespawn_enabled"			"0"		// Enable respawn.
"sm_botrespawn_delay_ins"			"1"		// Delay to respawn bots, 0 will disable respawn.
"sm_botrespawn_rp_ins"				"5"		// Default respawn point. Bot num is (Alive bot number) + sm_botrespawn_rp + (Player number) * sm_botrespawn_rp_add
"sm_botrespawn_rp_add_ins"			"5"		// How many respawn point increase per players
"sm_botrespawn_delay_sec"			"1"		// Delay to respawn player, 0 will disable respawn.
"sm_botrespawn_rp_sec"				"5"		// Player respawn point.
"sm_botrespawn_display"			"1"		// Enable display how many respawn point remain. (0 = don't display, 1 = display teams, 2 = display all)
"sm_botrespawn_display_delay"	"1"		// Display delay
```

## Medic
Make it medic that can revive other player.

#### Plugins
[Medic.smx](plugins/Medic.smx)

#### Sources
[Medic.sp](scripting/Medic.sp)

#### Dependencies
[insurgency.games.txt](gamedata/insurgency.games.txt)

#### Cvars
```
"sm_medic_enabled"			"1"			// Enable medic.
"sm_medic_class"			"breacher"	// Class that is medic. (recon, rifleman, specialist, breacher, support, demolition, marksman, sniper, ...)
"sm_medic_delay"			"10"		// Delay to revive player. (sec)
"sm_medic_rp"				"8"			// Max revive number per object.
"sm_medic_distance"			"100"		// Max revive distance from dead position to medic.
"sm_medic_item"				"kabar"		// Revive item.
"sm_medic_score"			"50"		// Get score when revive.
```

## SuicideBomber
Make a bot suicidebomber.

#### Plugins
[SuicideBomber.smx](plugins/SuicideBomber.smx)

#### Sources
[SuicideBomber.sp](scripting/SuicideBomber.sp)

#### Cvars
```
"sm_suicide_enabled"			"1"				// Enable medic.
"sm_suicide_bomber"				"sharpshooter"	// A class that will be bomber. ("" is all bot is bomber... with "ins_bot_knives_only" "0" ... zombie...)
"sm_suicide_detonate_range"		"600"			// Max range to detonate. I recommend 125.
"sm_suicide_resist"				"20"			// Bomber health multiply. Default health is 2000...
"sm_suicide_delay"				"0.01"			// Wrong cvar... why i make this???? make sure this value is 1.
```

## By the way...
Many plugins should be fixed but i'm too lazy...
