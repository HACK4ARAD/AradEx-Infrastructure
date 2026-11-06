# AradEx-Infrastructure

Infrastructura AradExperience (Hack4Arad 2026). Owner: **P1 · Zoltan** (T00, T04, T16a).

## Local
```
docker compose up -d      # Postgres 16 pe localhost:5432, db aradexperience, user/parolă arad/arad
docker compose down       # oprește (datele rămân în volumul aradexperience_pg)
```
Fiecare task își face baza lui: `createdb -h localhost -U arad aradexperience_txx` (parola `arad`).
Fără Docker: Postgres 16 local cu rolul `arad` (parola `arad`, `CREATEDB`).

## Producție (T04 → T16a)
Aici vin configurațiile de deploy: Render (API din `../AradEx-Backend/Dockerfile`), Netlify (`../AradEx-Frontend`), Neon / Render Postgres.
Pașii, URL-urile și cine are acces: `../AradEx-Ops/docs/DEPLOY.md`. **Nicio cheie sau parolă în repo.**
