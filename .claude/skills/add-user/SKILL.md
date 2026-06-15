---
name: add-user
description: Create an Orbit user account (or reset an existing user's password) directly in the database. Use this whenever someone needs to add/provision a user, create a login, or reset a password — Orbit has no self-registration UI, so accounts are created with this skill.
---

# Add an Orbit user

Self-registration was removed from Orbit, so user accounts are provisioned by
inserting them into the database. This skill runs `add-user.mjs`, which hashes
the password exactly like the API server (`scrypt`, stored as `salt:key` hex —
see `src/apiserver/src/common/crypto.util.ts`) and writes the `User` row via
Prisma.

## How to use

1. Collect the **email** (required). Ask for **name** (defaults to the email
   local-part) and **password** (optional — if omitted a strong random one is
   generated and printed).
2. Run the script from the repo root:

   ```bash
   node .claude/skills/add-user/add-user.mjs --email user@example.com --name "Jane Doe" --password "s3cret123"
   ```

   - Omit `--password` to auto-generate one (it is printed once on success):
     ```bash
     node .claude/skills/add-user/add-user.mjs --email user@example.com
     ```
   - Pass `--force` to reset the password of a user that already exists:
     ```bash
     node .claude/skills/add-user/add-user.mjs --email user@example.com --password new-pass --force
     ```

3. Report the created email/id back to the user. If a password was generated,
   share it (it is shown only once and stored only as a hash).

## Requirements

- The database must be reachable. `DATABASE_URL` is read from the environment or
  the repo-root `.env` (`npm run db:up` starts the local Postgres).
- The Prisma client must be generated (`npm run prisma:generate`) and migrations
  applied (`npm run prisma:migrate`).

## Notes

- Without `--force`, adding a duplicate email fails loudly rather than silently
  overwriting an existing account.
- The script has no npm dependencies of its own; it reuses the root
  `@prisma/client` and the generated client.
