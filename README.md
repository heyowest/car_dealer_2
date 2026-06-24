# car_dealer_2

A daily-rotating NPC car dealership for **QBox** with a cinematic **3D showroom**:
walk up to the dealer, orbit each car with your mouse, sit inside, and buy it
through a clean confirm dialog. Every purchase is fully server-authoritative and
the car is a real, garage-managed owned vehicle.

![Premium Deluxe Motorsport](https://static.wikia.nocookie.net/gtawiki/images/1/1d/PremiumDeluxeMotorsport-GTAOe-Logo.png/revision/latest?cb=20220804174006)

---

Click here to watch the demo video: [**Demo Video**](https://www.youtube.com/watch?v=w8cnl8wpGVQ)

Join Our Discord Server: https://discord.gg/GtDWhu9d6T

---

## Features

- 🏎️ **3D showroom preview** — an orbit camera frames the selected car; look
  around with the mouse, scroll to zoom, switch cars with the arrows, and sit
  inside with a keypress.
- 🎨 **Branded NUI overlay** — dark/gold glass HUD showing the model, class,
  live performance bars (pulled from the vehicle's real handling data) and price,
  with a styled "are you sure?" confirm dialog.
- 🗓️ **Daily rotation** — a fresh, duplicate-free line-up is generated every real
  day, weighted so rare/expensive cars show up less often.
- 📉 **Limited stock** — each car is a single unit. Buying one removes it from the
  lot, and the lot stays in sync **live** for everyone currently browsing.
- 🔒 **Server-authoritative & exploit-safe** — the server validates the purchase,
  charges the player, creates the owned vehicle, spawns it itself and hands over
  the keys. The client never decides money, items, or which vehicle it receives.
- 🚗 **Proper ownership** — vehicles are created via `qbx_vehicles`, so they show
  up in the garage with a matching plate and work with persistence.
- 🌍 **Localised** — ships with English, Turkish, French, German, Italian and
  Russian (ox_lib locale); easy to add more.

---

## Dependencies

- [qbx_core](https://github.com/Qbox-project/qbx_core)
- [ox_lib](https://github.com/overextended/ox_lib)
- [ox_target](https://github.com/overextended/ox_target)
- [oxmysql](https://github.com/overextended/oxmysql)
- [qbx_vehiclekeys](https://github.com/Qbox-project/qbx_vehiclekeys)
- `qbx_vehicles` (server-only; ships with QBox — **do not** add it to
  `dependencies{}`, the client can't see server-only resources)

No SQL to import — it uses the standard QBox `player_vehicles` table.

---

## Installation

1. Drop the `car_dealer_2` folder into your `resources` (e.g. `[custom]`).
2. Ensure it **after** its dependencies in `server.cfg`:
   ```cfg
   ensure ox_lib
   ensure oxmysql
   ensure qbx_core
   ensure ox_target
   ensure qbx_vehiclekeys
   # ...
   ensure car_dealer_2
   ```
3. (Optional) Edit `config.lua` and `server_config.lua` to taste.
4. `restart car_dealer_2` and walk up to the dealer.

---

## Configuration

Config is split so players can't read sensitive data from their game cache:

**`config.lua`** — shared, **client-visible** (only safe-to-see values):

| Key | Description |
|-----|-------------|
| `NPCCoords` | Where the dealer ped stands (vector4). |
| `NPCModel` / `NPCType` | Dealer ped model + type. |
| `PreviewCoords` | Where the showroom preview car is placed. Point it at a clean/interior spot for a true showroom look. |
| `CameraSensitivity` | Mouse-look speed in the showroom (default `8.0`). |

**`server_config.lua`** — **server-only**, never sent to clients (keeps rarity
odds and the full line-up hidden):

| Key | Description |
|-----|-------------|
| `DailyMaxCars` | How many distinct cars are offered per day (default `4`). |
| `CoordsToSpawnTheCar` | Where a purchased car is delivered (vector4). |
| `CarPool` | The full pool with `spawn`, `label`, `price`, `weight`. Higher `weight` = more likely to appear (a probability, not a quantity). |

> Players still see each car's name/price **in the showroom** (that's the
> catalog), but they can't see the weights, the daily algorithm, or cars that
> aren't in today's line-up.

---

## Showroom controls

| Input | Action |
|-------|--------|
| Mouse | Look around the car |
| Scroll | Zoom in / out |
| ← / → | Previous / next car |
| `F` | Sit inside / get out |
| `E` | Buy (opens confirm dialog) |
| `Backspace` | Exit the showroom |

---

## Languages

Ships with **English, Turkish, French, German, Italian, Russian**. ox_lib picks
the file in `locales/` matching your server's locale convar:

```cfg
setr ox:locale "fr"   # en / tr / fr / de / it / ru
```

To add another language, copy `locales/en.json`, translate the values (keep the
`%s` placeholders), and save it as `<code>.json`.

---

## Admin commands

Both are restricted to `group.admin` (and usable from the server console).

| Command | Description |
|---------|-------------|
| `/restockdealer` | Re-rolls today's lineup using the weighted algorithm. |
| `/adddealercar <model> <price>` | Adds one specific car to today's lineup without touching the random pool — e.g. `/adddealercar sultan 50000`. The model is validated against the framework's vehicle list. |

Both broadcast a refresh so open showrooms update.

---

## Persistence

The daily lineup is snapshotted to **FiveM KVP** (a server-side key/value store —
no SQL table needed). On boot the saved lineup is restored **if it's still the
same day**, so restarting the server mid-day keeps the exact same cars and
remembers what's already been sold. The lineup only re-rolls when the real
calendar day changes (checked once a minute, server local time) or when an admin
runs `/restockdealer`.

---

## How a purchase works (trust boundary)

```
Client: open showroom → preview locally → press E → confirm in NUI
        → lib.callback 'car_dealer_2:buyCar' (sends only the unit id)
Server: validate unit is in stock & unreserved → reserve it (atomic)
        → check + take bank funds → CreatePlayerVehicle (DB, unique plate)
        → spawn server-side from DB props → give keys → mark sold
        → broadcast 'onSold' so every open showroom drops the unit
Client: success notification; the real car is spawned and you're warped in
```

The client only ever sends a stock id. Money, ownership, the plate, the spawn and
the keys are all decided and performed on the server.

---

## Credits

Created by **heyowest**. Built on the QBox / ox stack. Free to use — credit
appreciated. If you ship a modified version, keep this README's credit line.
