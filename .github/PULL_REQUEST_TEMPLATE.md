<!--
  Volcán Migration — Pull Request

  Title format (Conventional Commits):
    <type>(<optional scope>): <subject>
  See `.github/COMMIT_CONVENTION.md` for the full list of types.
-->

## Tipo de cambio

<!-- Marcá el o los que apliquen. Debe coincidir con el `<type>` del título. -->

- [ ] `feat`     — nueva funcionalidad
- [ ] `fix`      — corrección de bug
- [ ] `docs`     — solo documentación
- [ ] `chore`    — cambios de tooling / mantenimiento
- [ ] `refactor` — refactor sin cambios de comportamiento
- [ ] `test`     — agrega o ajusta tests
- [ ] `ci`       — cambios al pipeline de CI
- [ ] `style`    — formato/estilo (no afecta lógica)

## Descripción

<!-- ¿Qué cambia y POR QUÉ? Foco en motivación, no en mecánica. -->

## Tasks relacionadas

<!-- Linkear tasks de specs/<feature>/tasks.md (ej. T045, T102b) y/o issues. -->

- T...
- Closes #...

## Checklist de release-readiness (Constitution §XI)

- [ ] PHPCS (WordPress ruleset) verde
- [ ] PHPStan nivel 5 verde
- [ ] Plugin Check oficial sin warnings
- [ ] PHPUnit verde en la matriz PHP 7.4 / 8.0 / 8.1 / 8.2 / 8.3
- [ ] Tests nuevos para la lógica crítica de la feature
- [ ] Strings de UI traducibles (sin hardcoded en `__()` / `esc_html__`)
- [ ] `readme.txt` y `CHANGELOG.md` actualizados si aplica
- [ ] Sin `error_log`, `var_dump`, `print_r`, `die` en código mergeado
- [ ] Sin secretos commiteados
- [ ] Probado manualmente en al menos un sitio real (multisite si aplica)

## Compliance constitucional

<!-- §IV (WP.org) y §V (Seguridad) son no negociables. Documentá el chequeo. -->

- [ ] §IV (WP.org compliance): _confirmá explícitamente_
- [ ] §V (Seguridad — capability + nonces + sanitización + escapado + zip-slip): _confirmá explícitamente_
