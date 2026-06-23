# PROJECT.md — car_dealer_2

Per-resource spec. See the root `CLAUDE.md` for server-wide conventions.

## Purpose

An NPC car dealership where the offered cars rotate daily. The player interacts
with a dealer ped, browses the day's cars in a 3D showroom (orbit camera + NUI
overlay), and buys one through a confirm dialog. Purchases are server-authoritative
and produce real garage-managed owned vehicles.

## Stack

QBox (`qbx_core`), ox_lib, ox_target, oxmysql, qbx_vehicles (server-only),
qbx_vehiclekeys. NUI is plain HTML/CSS/JS (no build step).

## File map

| File | Role |
|------|------|
| `config.lua` | **Shared (client-visible)** tuning: dealer/preview coords, camera sensitivity. |
| `server_config.lua` | **Server-only** tuning: car pool + weights, daily count, delivery coords (hidden from clients). |
| `client.lua` | Spawns the dealer ped + ox_target; opens the showroom. |
| `showroom.lua` | Orbit camera, input loop, NUI bridge, buy flow, live stock sync. |
| `server.lua` | Authority: daily stock, validation, payment, vehicle creation/spawn, keys, stock broadcasts. |
| `ui/` | `index.html` / `style.css` / `app.js` — the showroom overlay. |
| `locales/` | `en.json`, `tr.json` (ox_lib locale). |

## Data flow

- **Stock** is owned by the server (`DailyStock`, array of `{id, spawn, label,
  price}`). Each entry is a single purchasable unit identified by a monotonic
  `id`. It's snapshotted to **FiveM KVP** (`car_dealer_2:stock` = `{date, seq,
  stock}`) on every change. On boot the snapshot is restored if `date == today`,
  otherwise a fresh lot is rolled. It also rolls when the date changes (1-min
  check) or via `/restockdealer`. `reserved` is not persisted (nothing is
  mid-purchase across a restart).
- Client fetches available stock via `car_dealer_2:getDailyStock` (hides
  reserved/sold units).
- Buying calls `car_dealer_2:buyCar(stockId)`. The server reserves the unit
  **synchronously before any await** (atomic against races), validates funds,
  `qbx_vehicles:CreatePlayerVehicle`, reads the row back (exports copy table args,
  so the generated plate only exists in the DB — must re-read), `qbx.spawnVehicle`
  from those props, links `state.vehicleid`, gives keys, removes the unit, and
  broadcasts `car_dealer_2:onSold` to all clients.
- `car_dealer_2:onRefresh` is broadcast on daily rollover to close open showrooms.

## Trust boundary

The client only ever sends a `stockId`. The server owns: stock membership,
reservation, identity (from `source`), funds, plate, DB row, spawn, and keys. The
preview vehicle is a **local** (`isNetwork=false`) entity, so concurrent viewers
never collide and the preview can never become the real purchase.

## Concurrency

- Double-buy of the same unit: blocked by `reserved[id]` (set before awaits) +
  per-citizen `purchaseInProgress` lock.
- Concurrent viewers: `onSold`/`onRefresh` broadcasts keep every open showroom's
  stock list in sync; a viewer on a just-sold car is slid to a valid one.

## Status

**v1.0.0 — feature complete.** Done: daily rotation, weighted dedup pool, limited
stock with live sync, KVP persistence (restart-safe), 3D showroom
(orbit/zoom/switch/sit-inside), branded NUI + confirm dialog, server-authoritative
purchase with matching plate + keys, admin commands (`/restockdealer`,
`/adddealercar`), EN/TR locales.

### Possible future work
- Optional dedicated interior/bucket for the preview so the backdrop is controlled.
- Test-drive mode before buying.
- Discord webhook log of purchases.
