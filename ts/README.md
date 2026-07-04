Anki's TypeScript and Sass dependencies. Some TS/JS code is also stored
separately in `../qt/aqt/data/web/`.

Use the root `just` recipes as the command surface:

```bash
just web-watch
just rebuild-web
just test-ts
just lint
```

Dependency-update helper scripts from upstream are not present in this checkout;
add or update packages through the repo's package manager files and verify with
`just test-ts` / `just check`.
