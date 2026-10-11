# Saronite: WotLK raid planner

Raid and roster builder for Wrath of the Lich King Classic (3.3.5).

## Run it

```bash
npm install
cp .env.example .env
# Edit .env with the Supabase project URL and publishable/anon key.
npm run dev                   # http://localhost:3000
```

Requires Node 22+.

### Supabase setup

1. Create a Supabase project.
2. In the Supabase Dashboard, open **SQL Editor**. On a fresh project, run the migration files in order: `202610070001_guild_raid_schema.sql`, `202610090001_loot_priority_board.sql`, `202610100001_permanent_guild_loot_board.sql`, `202610110001_loot_priority_ties.sql`, and `202610110002_public_roster_loot_share.sql`. If the earlier migrations are already applied, run only the new migration(s).
3. Copy `.env.example` to `.env`. Set `NUXT_PUBLIC_SUPABASE_URL` from **Project Settings → API → Project URL**, and `NUXT_PUBLIC_SUPABASE_ANON_KEY` to the project's **publishable key** (or legacy anon key). Restart Nuxt after editing.
4. In **Authentication → URL Configuration**, set the local Site URL to `http://localhost:3000` and allow that URL for redirects. Configure email/password sign-up and email confirmation to match your preference.
5. Run `npm run dev` and sign up. The first account creates this project's single guild workspace and becomes its owner. Officers invite members with a generated code; only owners/admins can issue officer invites.

Members can view raids and the shared roster. Owners, admins, and officers can edit raids and roster data; those restrictions are enforced by Postgres RLS, not just the UI. Characters added to a saved raid are also synchronized into the guild-wide player library and can be reused in another raid.

### Loot attribution

Open **Loot attribution** from the raid planner. This is one permanent board for the guild; loot awards and history are not tied to a raid session. Officers can add players directly to the shared roster by name, class, spec, and role—or import a player already entered in the raid planner—without requiring those players to have Saronite accounts. Officers can rank candidates per item, tie candidates at the same priority with **Tie**, and split a tie with **Split**. When tied players are the highest eligible rank, roll among them and record the winner next to that player. A player who wins loot is skipped for other items for the rest of the current round. Once no pending item has an eligible candidate, an officer can start the next round. Overrides and award corrections require a reason and are preserved in the all-time history.

Officers can generate a public, read-only roster-and-loot link from **Guild roster**. Anyone with the link can view both pages without registering. The token grants read access to that guild's roster and loot history; rotating or revoking the link invalidates the previous URL. Treat it like a password and share it only with people you trust.

The optional Discord server ID is metadata only; Discord OAuth, automatic server membership checks, and a bot are not included. Only the Supabase URL and public publishable/anon key belong in Nuxt. **Never put the service-role key in `.env` values prefixed with `NUXT_PUBLIC_` or in browser code.**

## What phase 1 does

- 10 / 25-player raid builder with 5-slot groups
- Drag and drop on desktop, tap-to-pick then tap-to-place on mobile (tap an occupied slot to swap)
- Bench with add/remove characters; hybrids (feral, DKs) can switch role by tapping the role icon
- Live buff and debuff board (20 buffs, 10 debuffs) that understands party-only effects (totems, Fel Intelligence, Blood Pact)
- Suggestions: groups missing party-only buffs, one-shaman air totem conflicts, paladin blessing limits, missing key classes
- Role balance against suggested ranges
- Supabase Auth, a shared guild workspace, and role-based raid editing
- Saved raids and reusable guild characters in Supabase Postgres
- Guild loot attribution with per-item priorities, round fairness, and award audit history
- Separate guild roster page for managing/importing players without cluttering the loot board
- LocalStorage fallback for the current raid when Supabase is unavailable
- Shareable links (the whole raid is encoded in `?raid=`)

The Nuxt app talks directly to Supabase using the public client and relies on RLS for every data operation. `npm run generate` creates a static frontend; set the two Supabase public environment variables at build/deploy time and add the deployed site's URL to Supabase Auth's allowed redirect URLs.

## Project layout

```
shared/types.ts          Domain types (Character, Effect, RaidState…)
app/data/classes.ts      Classes, specs, class colors, role targets
app/data/effects.ts      Buff/debuff catalogue: the backbone of the app
app/data/demo.ts         Example ICC roster
app/utils/coverage.ts    Coverage engine + suggestion rules (pure functions)
app/utils/share.ts       Share-link encoding
app/composables/useGuild.ts  Supabase Auth, workspace, membership, and invites
app/composables/useRaid.ts  Planner state and Supabase persistence
app/pages/players.vue       Guild roster management (no player accounts required)
supabase/migrations/     PostgreSQL schema, RPCs, and RLS policies
app/components/          UI
```

## Roadmap

| Phase | Feature | Notes |
|---|---|---|
| 1 ✅ | Roster builder, buff board, hints, share links | This build |
| 2 ✅ | Accounts, guild workspace, saved raids | Supabase Auth + Postgres RLS; owner/officer writes |
| 3 | Expanded guild roster, mains/alts, signups calendar | Statuses: accepted, tentative, late, bench |
| 4 | Discord bot | Signup embeds with buttons, posts final comp |
| 5 | Boss templates + assignments board | Per-encounter roles for Naxx → RS; export to raid chat |
| 6 | Cooldown planner | Timeline per boss; export as an in-game import string |
| 7 | Companion addon | Roster export / group arrangement via LibSerialize + LibDeflate strings |
| 8 | Loot: soft-res, priority lists, history, attendance | Loot priority/award history implemented; soft-res and attendance remain |
| 9 | Warcraft Logs integration | Parses and trends per player |
