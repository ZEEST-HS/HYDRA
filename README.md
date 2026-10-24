# HYDRA — Hydra POS

Application Flutter de caisse et de gestion de boutique (Android, hors ligne,
arabe RTL / français LTR, montants en MAD).

- `hydra_pos/` — code source de l'application (Flutter).
- `repo_audit/` — copie de référence d'un projet Flutter public utilisée pendant
  l'audit initial ; ce n'est pas le code de production.
- `off_*.json` — réponses d'API Open Food Facts conservées pour l'audit du
  catalogue externe.

## Démarrage

```powershell
cd hydra_pos
flutter pub get
flutter analyze
flutter test
flutter run
```

Documentation détaillée : [`hydra_pos/docs/STATUS.md`](hydra_pos/docs/STATUS.md)
et [`hydra_pos/docs/TESTING.md`](hydra_pos/docs/TESTING.md).
