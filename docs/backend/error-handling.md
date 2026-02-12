# Error Handling & Logging - Backend

Documentation de la strategie d'erreurs et du systeme de logging du backend Pennote.

---

## 1. Classification des Erreurs

| Code | Type | Usage |
|------|------|-------|
| 400 | Bad Request | Validation echouee, parametres manquants |
| 401 | Unauthorized | Token manquant, invalide ou expire |
| 403 | Forbidden | Acces refuse (workspace, ressource) |
| 404 | Not Found | Ressource inexistante |
| 500 | Internal Error | Erreur serveur non prevue |

**Structure de reponse erreur:**
```typescript
{
  error: "Message lisible",
  code: "ERROR_CODE"  // Optionnel, pour identification frontend
}
```

---

## 2. Codes d'Erreur Standards

| Code | Signification |
|------|---------------|
| `MISSING_TOKEN` | Token d'authentification absent |
| `INVALID_TOKEN` | Token invalide ou expire |
| `USER_SYNC_FAILED` | Synchronisation utilisateur echouee |
| `CREDITS_EXHAUSTED` | Quota AI epuise |
| `INVALID_TEST_SECRET` | Secret de test invalide (dev) |

---

## 3. Logger Service (`lib/logger.ts`)

Le Logger intercepte `console.*` et ecrit dans des fichiers rotatifs.

```typescript
import { Logger } from "@/lib/logger";
Logger.init();  // Au demarrage du serveur

// Apres init, console.* est intercepte automatiquement
console.log("Message");   // Ecrit en fichier + console
console.error("Erreur");  // Idem avec niveau ERROR
```

**Initialisation:** Appelee dans `index.ts` au demarrage.

---

## 4. Niveaux de Log

| Niveau | Methode | Usage |
|--------|---------|-------|
| LOG | `console.log()` | Informations generales |
| INFO | `console.info()` | Evenements applicatifs |
| WARN | `console.warn()` | Alertes non-bloquantes |
| ERROR | `console.error()` | Erreurs recuperables |
| FATAL | Automatique | `uncaughtException`, `unhandledRejection` |

---

## 5. Format de Log Structure

```
[2024-01-15T10:30:45.123Z] [LOG  ] [filename.ts:42][MEM:128MB] Message
```

| Champ | Description |
|-------|-------------|
| Timestamp | ISO-8601 |
| Level | LOG, INFO, WARN, ERROR, FATAL |
| File:Line | Source extraite de la stack trace |
| MEM | Heap usage en MB |
| Message | Arguments formates |

---

## 6. Logging Securise (`SecureLogger`)

Classe pour filtrer les donnees sensibles.

```typescript
import SecureLogger from "@/middlewares/secureLogging";

// Log avec sanitisation
SecureLogger.log("Action", { userId, token });  // token masque

// Erreur minimale en production
SecureLogger.error("Echec", error);

// Audit toujours visible
SecureLogger.audit("Action critique", { userId, action: "delete" });
```

**Champs masques automatiquement:**
- `password`, `token`, `key`, `secret`, `credential`
- `content`, `prompt`, `messages`, `response`

---

## 7. Contexte dans les Logs

**Pattern recommande:**
```typescript
console.log("[SERVICE_NAME] Action:", {
  userId,
  workspaceId,
  duration: `${Date.now() - start}ms`
});

console.error("[AUTH] Echec:", {
  error: error.message,
  code: error.code,
  userId
});
```

**Prefixes standards:** `[AUTH]`, `[PADDLE]`, `[RAG]`, `[QUIZ]`, `[AGENT]`, `[MONITORING]`

---

## 8. Gestion des Erreurs - Patterns

**Middleware auth:**
```typescript
try {
  const user = await AuthService.verifyToken(token);
  if (!user) {
    return res.status(401).json({ error: "Token invalide", code: "INVALID_TOKEN" });
  }
} catch (error) {
  console.error("[AUTH] Erreur middleware:", error);
  return res.status(500).json({ error: "Erreur interne", code: "AUTH_ERROR" });
}
```

**Service avec throw:**
```typescript
if (!process.env.REQUIRED_VAR) {
  throw new Error("Variable manquante: REQUIRED_VAR");
}
```

---

## 9. Monitoring (`lib/monitoring.ts`)

```typescript
import { getSystemStats, checkHealthThresholds } from "@/lib/monitoring";

// Metriques systeme
const stats = await getSystemStats();
// { memory, cpu, uptime, queues, pid, nodeVersion }

// Detection seuils critiques
const health = checkHealthThresholds();
// { healthy: boolean, warnings: [] }
```

**Seuils d'alerte:**
| Metrique | Warning | Critical |
|----------|---------|----------|
| Heap usage | >70% | >85% |
| RSS | >3GB | >4GB |

---

## 10. Rotation des Logs

- Fichiers: `logs/server-YYYY-MM-DDTHH-MM-SS.log`
- Retention: 10 derniers fichiers
- Nettoyage automatique au demarrage

```typescript
// API disponible
Logger.getLogFiles();        // Liste les fichiers
Logger.readLogFile(name);    // Lit un fichier
Logger.getCurrentLogFile();  // Fichier actuel
```

---

## 11. Checklist Implementation

- [ ] `Logger.init()` appele au demarrage (`index.ts`)
- [ ] Erreurs avec `code` pour le frontend
- [ ] Prefixes `[SERVICE]` dans les logs
- [ ] `SecureLogger` pour donnees sensibles
- [ ] Contexte (userId, workspaceId) dans les erreurs
- [ ] Pas de `console.log` sans prefixe
