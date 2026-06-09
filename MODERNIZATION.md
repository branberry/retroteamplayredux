# Modernizing Retro TeamPlay (noxctf) for today's Garry's Mod

This document details the changes made to bring this gamemode — last actively developed around 2013–2014 — back to a working state on a current build of Garry's Mod.

## Background

The codebase had already received a partial "GMod 13 conversion" (credited to ptown2 in `shared.lua`): it has a proper `noxctf.txt` gamemode manifest, the new `surface.CreateFont` table signature, the GM13 player animation system (`GM:CalcMainActivity` with `ACT_MP_*` activities), and GM13-style `DComboBox`/`DListView` usage. However, a large amount of pre-GM13 API usage survived, most notably the entire networking layer. Some of it was merely deprecated; some of it errors outright on a modern client.

The authoritative references used were the official wiki's [Networking Usage](https://wiki.facepunch.com/gmod/Networking_Usage) page and the deprecation notices on the [`umsg`](https://wiki.facepunch.com/gmod/umsg) / [`usermessage`](https://wiki.facepunch.com/gmod/usermessage) library pages, which state these libraries "may be changed or removed in a future update" and are hard-limited to **256 bytes per message**.

In total, **~120 Lua files** were modified. Every one of the gamemode's 1,164 Lua files was syntax-validated after the conversion.

---

## 1. Networking: `umsg`/`usermessage` → the `net` library

**The biggest change.** The gamemode sent all of its server→client messages through the legacy usermessage system: 42 `umsg.Start`/`umsg.End` blocks across 14 server files, received by 38 `usermessage.Hook` handlers across 14 client files. The `net` library (introduced in GM13) replaces all of it.

### Sending (server)

Broadcast messages — `umsg.Start` with no recipient becomes `net.Start` + `net.Broadcast`:

```lua
-- Before (gamemode/gametypes/blitz.lua)
function self:BallTaken(pl)
    umsg.Start("BallTaken")
        umsg.Entity(pl)
        umsg.Short(pl:GetTeamID())
    umsg.End()
end

-- After
function self:BallTaken(pl)
    net.Start("BallTaken")
        net.WriteEntity(pl)
        net.WriteInt(pl:GetTeamID(), 16)
    net.Broadcast()
end
```

Targeted messages — the recipient moves from `umsg.Start`'s second argument to `net.Send`:

```lua
-- Before (gamemode/sv_obj_player_extend.lua)
function meta:DI(spellid, ttime)
    umsg.Start("DI", self)
        umsg.Short(spellid)
        umsg.Float(ttime)
    umsg.End()
end

-- After
function meta:DI(spellid, ttime)
    net.Start("DI")
        net.WriteInt(spellid, 16)
        net.WriteFloat(ttime)
    net.Send(self)
end
```

### Receiving (client)

`usermessage.Hook` callbacks received a `bf_read` object and read from it; `net.Receive` callbacks read from the global `net` reader instead:

```lua
-- Before (gamemode/cl_init.lua)
usermessage.Hook("FlagReturnEffect", function(um)
    local effectdata = EffectData()
        effectdata:SetOrigin(um:ReadVector())
        effectdata:SetStart(um:ReadVector())
        effectdata:SetScale(um:ReadShort())
    util.Effect("flagreturn", effectdata)
end)

-- After
net.Receive("FlagReturnEffect", function()
    local effectdata = EffectData()
        effectdata:SetOrigin(net.ReadVector())
        effectdata:SetStart(net.ReadVector())
        effectdata:SetScale(net.ReadInt(16))
    util.Effect("flagreturn", effectdata)
end)
```

### Type mapping used

| umsg write | net write | usermessage read | net read |
|---|---|---|---|
| `umsg.Entity(v)` | `net.WriteEntity(v)` | `um:ReadEntity()` | `net.ReadEntity()` |
| `umsg.String(v)` | `net.WriteString(v)` | `um:ReadString()` | `net.ReadString()` |
| `umsg.Short(v)` | `net.WriteInt(v, 16)` | `um:ReadShort()` | `net.ReadInt(16)` |
| `umsg.Long(v)` | `net.WriteInt(v, 32)` | `um:ReadLong()` | `net.ReadInt(32)` |
| `umsg.Char(v)` | `net.WriteInt(v, 8)` | `um:ReadChar()` | `net.ReadInt(8)` |
| `umsg.Float(v)` | `net.WriteFloat(v)` | `um:ReadFloat()` | `net.ReadFloat()` |
| `umsg.Vector(v)` | `net.WriteVector(v)` | `um:ReadVector()` | `net.ReadVector()` |
| `umsg.VectorNormal(v)` | `net.WriteNormal(v)` | `um:ReadVectorNormal()` | `net.ReadNormal()` |
| `umsg.Bool(v)` | `net.WriteBool(v)` | `um:ReadBool()` | `net.ReadBool()` |

Reads inside expression lists keep their order because Lua evaluates arguments left-to-right, so calls like `self:BallScored(net.ReadEntity(), net.ReadInt(16), net.ReadEntity(), net.ReadEntity())` remain correct.

### Network string pooling (new requirement)

Unlike usermessages, every `net` message name must be registered server-side with `util.AddNetworkString` before it can be sent. A pooling block was added to `gamemode/init.lua` covering all 37 message names used by the gamemode:

```lua
-- gamemode/init.lua
local NetworkStrings = {
    "BallDropped", "BallReset", "BallScored", "BallTaken",
    "DI", "EndG",
    "FCap", "FDro", "FRet", "FTak", "FlagReturnEffect",
    "NextRespawn",
    "PlayerKilled", "PlayerKilledByPlayer", "PlayerKilledByPlayers", "PlayerKilledSelf",
    "RecDSD", "RecFlagInfo", "RecGameState", "RecInfo", "RecVD", "RecVehTimer",
    "SI", "SLM",
    "cusges", "lm", "lmg", "lmr",
    "openslotwindow", "recgtnumvotes", "recturrettarget",
    "resetluaanim", "setluaanim", "sp", "stopallluaanim", "stopluaanim", "stopluaanimgp",
}
for _, name in ipairs(NetworkStrings) do
    util.AddNetworkString(name)
end
```

Relatedly, `umsg.PoolString("Auto-return")` in `init.lua` was deleted — string pooling for message payloads is a usermessage-era optimization that has no `net` equivalent (and needs none).

### The `ENT:Info()` streaming pattern

The gamemode has an RPC-ish pattern where the client requests info about an entity (`ReqInfo` concommand), the server replies with a `RecInfo` message, and the client handler forwards the *message object* into the entity so it can read its own payload:

```lua
-- Before (gamemode/cl_init.lua)
usermessage.Hook("RecInfo", function(um)
    local ent = um:ReadEntity()
    if ent:IsValid() and ent.Info then
        ent:Info(um)            -- entity reads the rest of the message itself
    end
end)

-- Before (entities/entities/prop_jumppad/cl_init.lua)
function ENT:Info(um)
    local str = um:ReadString()
    ...
end
```

Because `net` reads come from a global reader rather than a passed object, the message object no longer needs to be threaded through. The handler and all ~25 client-side `ENT:Info` implementations were updated:

```lua
-- After (gamemode/cl_init.lua)
net.Receive("RecInfo", function()
    local ent = net.ReadEntity()
    if ent:IsValid() and ent.Info then
        ent:Info()
    end
end)

-- After (entities/entities/prop_jumppad/cl_init.lua)
function ENT:Info()
    local str = net.ReadString()
    ...
end
```

Beyond correctness, this migration removes the usermessage system's 256-byte ceiling (net messages allow ~64 KB) and its risk of future removal.

---

## 2. `self.Entity` → `self` (141 occurrences, 45 files)

Pre-GM13, scripted entities and effects accessed their underlying entity through `self.Entity`. Since GM13, `self` *is* the entity. This survived mostly in **client-side effects** (`entities/effects/*/init.lua`), where `self.Entity` is `nil` on a modern client and every call through it is a hard Lua error — a major reason effects "largely did not work":

```lua
-- Before (entities/effects/flagreturn/init.lua) — runtime error today
self.Entity:SetPos(MySelf:GetShootPos() + MySelf:GetAimVector() * 12)

-- After
self:SetPos(MySelf:GetShootPos() + MySelf:GetAimVector() * 12)
```

The replacement used a word-boundary match so member names like `self.EntityTakeDamage` (a method on `status_ruin`) were untouched.

---

## 3. Removed globals: `ValidPanel`/`ValidEntity` → `IsValid`

GM13 removed `ValidEntity()` and `ValidPanel()` in favor of the universal, nil-safe `IsValid()`:

```lua
-- Before (gamemode/modules/animationsapi/cl_animeditor.lua)
if ValidPanel(v) && v:IsVisible() then

-- After
if IsValid(v) && v:IsVisible() then
```

A related fix in `entities/entities/vehicle_tpbase/init.lua`: `ENT:OnRemove` called `seat:IsValid()` directly on `self.PilotSeat` (which errors if the seat was never created); it now uses the nil-safe `IsValid(seat)`.

---

## 4. Deprecated networked variables: `SetNetworked*` → `SetNW*` (63 occurrences, 19 files)

The `Entity:SetNetworkedInt`-style functions are deprecated aliases slated for removal. All call sites were renamed to the modern `NW` equivalents (`SetNWInt`, `GetNWFloat`, `SetNWString`, `GetNWEntity`, etc.):

```lua
-- Before (entities/entities/vehicle_noxvulture/cl_init.lua)
function ENT:SetThrust(fThrust)
    self:SetNetworkedFloat("thrust", fThrust)
end

-- After
function ENT:SetThrust(fThrust)
    self:SetNWFloat("thrust", fThrust)
end
```

---

## 5. ConVar access: `GetConVarNumber` → `GetConVar`

`GetConVarNumber` is deprecated; ConVar objects are the supported interface:

```lua
-- Before (gamemode/cl_deathnotice.lua)
local Death = {time = RealTime() + GetConVarNumber("hud_deathnotice_time"), ...

-- After
local Death = {time = RealTime() + GetConVar("hud_deathnotice_time"):GetFloat(), ...
```

---

## 6. `file` library: mount-relative paths

GM13 changed the `file` library to take an explicit search-path argument and removed `..`-style relative paths. Most calls had already been converted (`file.Read(..., "DATA")` etc.); one stragglers remained:

```lua
-- Before (gamemode/nox_maplist.lua) — silently broken
if not file.Exists("../maps/"..maptab[1]..".bsp") then

-- After
if not file.Exists("maps/"..maptab[1]..".bsp", "GAME") then
```

---

## 7. Gamemode manifest cleanup: removed stale `info.txt`

GM12 gamemodes were described by `info.txt`; GM13 gamemodes use `<gamemode>.txt` (here, `noxctf.txt`, which already existed and is correct). The leftover `info.txt` in the gamemode root was actually a misplaced *addon* metadata file produced by a GMA extractor — it served no purpose and was deleted. The working manifest is:

```text
-- gamemodes/noxctf/noxctf.txt
"noxctf"
{
    "base"     "base"
    "title"    "Retro TeamPlay"
    "maps"     "^gm_build_noxctf_|^nox_|^noxctf_|^noxtp_|^noxnb_"
    ...
}
```

---

## What was checked and intentionally left alone

While researching, several other GM13-era breaking changes were audited and found to be **already handled** or **not applicable**:

- **`surface.CreateFont`** — all 17 calls already use the modern `(name, {table})` signature.
- **Player animations** — already on the GM13 system (`GM:CalcMainActivity`, `ACT_MP_*`, gesture slots).
- **`GM:EntityTakeDamage`** — the only implementations (`status_ruin`) already use the new `(ent, dmginfo)` signature.
- **`DComboBox` / `DListView`** — already converted to the GM13 API (`AddChoice`, `OnSelect`).
- **`datastream`/`glon`** — not used anywhere (GM13's most famous removals).

Some APIs remain that are *deprecated but fully functional*, left as-is deliberately to avoid behavioral risk:

- **`Player:UniqueID()`** — used extensively as a key for timers and team-lock tables. Replacing it with `SteamID64` would break for bots (which have no SteamID64), so it stays.
- **`DPanelList`** — deprecated VGUI panel, still shipped with the game and working.
- **`SendLua`/`BroadcastLua`** — used for gametype initialization; still supported.

## Verification

- All ~120 modified files, and subsequently **all 1,164 Lua files** in the gamemode, were run through a syntax check (GLua's `&&`/`||`/`!`/`!=`/C-comments translated to vanilla Lua, then `luac -p`). Zero failures.
- A final sweep confirmed zero remaining references to `umsg`, `usermessage`, `ValidEntity`, `ValidPanel`, `self.Entity`, `Set/GetNetworked*`, or `GetConVarNumber` outside of comments.
