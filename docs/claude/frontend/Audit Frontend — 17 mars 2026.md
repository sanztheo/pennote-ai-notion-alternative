---

# Audit Frontend — 17 mars 2026

## 1. RÉSUMÉ

5 commits : nouveau **BetaGuard** bloquant les utilisateurs kicked/expired, amélioration de l'auto-scroll du chat, bannière beta sur l'onboarding, i18n des catégories du changelog, revalidation périodique du statut beta (2 min).

---

## 2. PERFORMANCES DE RENDU & OPTIMISATION (Objectif 10k)

- **PennoteChatMessages** : la liste de messages utilise `AnimatePresence` sans virtualisation. Pour un chat classique (~100-200 messages/conversation), c'est acceptable. Si une conversation dépasse ~500 messages, envisager `react-window` ou un lazy-load des anciens messages. **Risque faible à moyen terme.**
- Le `handleScroll` est correctement wrappé dans `useCallback` avec deps vides — pas de re-création à chaque render. RAS.
- **useBetaStatus** : polling toutes les 2 min (`setInterval`) — charge réseau négligeable (~1 req/2min/user). L'interval est nettoyé via `clearInterval` dans le cleanup du `useEffect`. RAS.
- **ChangelogPage** : rend toutes les versions d'un coup sans pagination. Avec <20 versions c'est négligeable. À surveiller si le fichier grossit au-delà de 50+ versions.
- **Locales** : ajout de 2 clés par fichier (9 langues). Impact bundle : ~2 KB total, négligeable.

---

## 3. ROBUSTESSE UX & ÉTATS LIMITES

- **BetaGuard** : bonne gestion — attend `hasFetchedOnce` (réponse API réelle) avant de bloquer. Évite les faux positifs sur cache stale. Loader affiché pendant l'attente. RAS.
- **⚠️ BetaGuard L40 — side effect dans le render** : `window.location.href = ...` est exécuté directement dans le corps du composant. C'est un **anti-pattern React** — un side effect dans `render` peut s'exécuter plusieurs fois en StrictMode. **Devrait être dans un `useEffect`.**

```tsx
// Actuel (problématique) :
if (betaStatus && BLOCKED_STATUSES.has(betaStatus)) {
  window.location.href = `${WEBSITE_URL}/fr/join`;  // ← side effect en render
  return <Loader />;
}

// Recommandé :
useEffect(() => {
  if (hasFetchedOnce && betaStatus && BLOCKED_STATUSES.has(betaStatus)) {
    window.location.href = `${WEBSITE_URL}/fr/join`;
  }
}, [hasFetchedOnce, betaStatus]);
```

- **BetaGuard** : la redirection est hardcodée vers `/fr/join`. Pour un utilisateur japonais ou arabe, ça redirige quand même vers la version française. **Mineur mais à noter.**
- **ChangelogPage** : `AbortController` + cleanup dans le `useEffect`. Bonne gestion. RAS.
- **PennoteChatMessages** : scroll conditionnel bien implémenté avec le seuil de 100px. RAS.

---

## 4. SÉCURITÉ CLIENT

- **BetaGuard** : la vérification est côté client uniquement. Un utilisateur peut contourner le blocage en modifiant le state React ou le localStorage. Ce n'est **pas une faille** si le backend vérifie aussi le statut beta sur chaque endpoint protégé (ce qui devrait être le cas). Client-side guard = UX, pas sécurité.
- **BetaGuard L30** : texte hardcodé en français (`"Vérification de votre accès…"`, `"Redirection…"`) au lieu d'utiliser `t()`. Pas une faille de sécurité, mais **incohérence i18n**.
- **ChangelogPage** : le contenu du CHANGELOG.md est rendu en texte brut (`{item}` dans JSX). React échappe par défaut — pas de risque XSS. RAS.
- Pas de manipulation de tokens ou secrets dans les diffs. RAS.

---

## 5. QUALITÉ & TESTS

- **Tests mis à jour** : `BetaFloatingWidget.test.tsx` et `useBetaProgress.test.ts` ajoutent `hasFetchedOnce: true` aux mocks. Bonne cohérence avec le changement de l'interface.
- **⚠️ Pas de test pour BetaGuard** : nouveau composant critique (bloque l'accès à l'app entière) sans test unitaire. **Devrait avoir des tests couvrant** : (1) affiche loader quand `hasFetchedOnce=false`, (2) redirige quand `betaStatus="inactive"`, (3) rend les children quand `betaStatus="active"`.
- **Changelog i18n** : le refactoring `CATEGORY_LABELS → CATEGORY_KEYS` avec `t()` est propre et type-safe via `TranslationKeys`. RAS.
- **Code smell mineur** : `BetaGuard` importe `logger` mais utilise `logger.log` au lieu de `logger.info` pour un événement métier important (accès bloqué). Convention du projet = `logger.info()` sur les actions critiques.

---

## Récap des actions recommandées

| Priorité | Fichier | Action |
|----------|---------|--------|
| **Haute** | `BetaGuard.tsx` | Ajouter des tests unitaires (composant bloquant critique) |
| **Moyenne** | `BetaGuard.tsx:40` | Déplacer `window.location.href` dans un `useEffect` |
| **Basse** | `BetaGuard.tsx:30,45` | Utiliser `t()` au lieu du texte français hardcodé |
| **Basse** | `BetaGuard.tsx:39` | `logger.info` au lieu de `logger.log` |
| **Basse** | `BetaGuard.tsx:40` | Rendre la locale de redirection dynamique (`/fr/join` → `/${locale}/join`) |