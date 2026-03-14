# Pennote Security Audit Report

**Date:** 2026-03-13
**Scope:** pen-backend/ + pen-frontend/
**Auditor:** Claude (pentester role)
**Status:** Audit complet -- aucun fichier modifie

---

## Executive Summary

Le codebase Pennote montre une securite globalement correcte : auth middleware systematique sur les routes sensibles, RBAC admin verifie en DB, rate limiting multicouche, CORS restrictif, helmet en place, chiffrement AES-256-GCM pour les donnees thinking, validation Zod sur les schemas critiques, et protection IDOR sur les jobs et workspaces.

Cependant, l'audit revele **3 findings CRITICAL**, **4 HIGH**, **5 MEDIUM** et **5 LOW** qui necessitent une attention immediate.

---

## CRITICAL

### C-01: SQL Injection via `$queryRawUnsafe` dans le service RAG

- **Severite:** CRITICAL
- **CWE:** CWE-89 (SQL Injection)
- **Fichier:** `pen-backend/src/services/rag/index.ts:827`
- **Description:**
  Le service RAG construit manuellement une requete SQL puis l'execute via `$queryRawUnsafe`. Les IDs sont valides via `assertUUID` et `assertClerkId`, mais le vecteur d'embedding (`embeddingStr`) est injecte directement dans la chaine SQL sans parametrisation.

  Le `queryEmbedding` est un tableau de nombres genere par le service d'embedding OpenAI, donc en pratique le vecteur d'attaque est indirect (il faudrait compromettre la reponse OpenAI). Neanmoins, l'usage de `$queryRawUnsafe` avec interpolation de strings est un anti-pattern dangereux.

- **Exploitabilite:** Difficile (necessite de compromettre la reponse OpenAI ou d'injecter des valeurs non-numeriques dans le tableau d'embedding)
- **Impact:** Lecture/ecriture arbitraire en base de donnees d'embeddings
- **Fix recommande:** Utiliser `$queryRaw` avec des tagged template literals (parametres lies) au lieu de `$queryRawUnsafe`. Valider explicitement que chaque element de `queryEmbedding` est un `number` fini avant interpolation.

---

### C-02: XSS via rendu HTML non sanitise sur contenu genere par IA

- **Severite:** CRITICAL
- **CWE:** CWE-79 (Cross-Site Scripting)
- **Fichiers:**
  - `pen-frontend/src/components/quiz/questions/OpenQuestionComponent.tsx:607`
  - `pen-frontend/src/components/quiz/questions/TrueFalseComponent.tsx:35`
  - `pen-frontend/src/components/quiz/SubjectTaking.tsx:339`
  - `pen-frontend/src/components/quiz/DocumentViewer.tsx:383`
  - `pen-frontend/src/components/editor/blocknotes/email-export/EmailExportButton.tsx:323`
- **Description:**
  Plusieurs composants quiz et document injectent du HTML dans le DOM sans sanitization DOMPurify. Le composant `MultipleChoiceComponent` utilise correctement DOMPurify, mais les autres l'omettent.

  Dans `OpenQuestionComponent.tsx:607`, `result` est construit par des regex de formatage markdown sur du texte AI qui peut contenir du HTML arbitraire. Dans `TrueFalseComponent.tsx:35`, aucun appel a DOMPurify avant injection. Dans `EmailExportButton.tsx:323`, `content` est le contenu de la note converti en HTML.

- **Exploitabilite:** Moyen (un utilisateur pourrait crafter du contenu contenant des balises script ou event handlers qui s'executent quand un autre utilisateur consulte le quiz ou exporte l'email)
- **Impact:** Vol de session (cookies), exfiltration de tokens JWT, defacement, actions au nom de la victime
- **Fix recommande:** Ajouter `DOMPurify.sanitize()` systematiquement avant chaque injection de HTML dans le DOM. Le pattern existe deja dans `MultipleChoiceComponent` -- l'appliquer a tous les fichiers cites.

---

### C-03: IDOR sur pages -- pas de verification de propriete sur write/delete

- **Severite:** CRITICAL
- **CWE:** CWE-639 (Authorization Bypass Through User-Controlled Key)
- **Fichiers:**
  - `pen-backend/src/routes/page.ts:294` (import-html)
  - `pen-backend/src/routes/page.ts:361-362` (blocknote-content write)
  - `pen-backend/src/routes/page.ts:531` (icon update)
- **Description:**
  Les routes d'ecriture sur les pages (`POST /:pageId/import-html`, `POST /:pageId/blocknote-content`, `PATCH /:id/icon`) ne verifient **pas** que l'utilisateur authentifie a acces a la page qu'il modifie. Seul `authenticateToken` est applique au niveau du router, puis le `pageId` provient des params URL sans verification d'appartenance.

  En revanche, la route de lecture `GET /:pageId/blocknote-content` (ligne 462) verifie correctement l'acces via une requete workspace.

  Un attaquant authentifie peut ecraser le contenu de n'importe quelle page en connaissant son UUID.

- **Exploitabilite:** Facile (il suffit de deviner/enumerer un UUID de page)
- **Impact:** Modification ou destruction de contenu d'autres utilisateurs
- **Fix recommande:** Ajouter une verification d'acces au workspace avant chaque operation d'ecriture, comme c'est deja fait pour la route GET.

---

## HIGH

### H-01: Quiz SSE streaming expose sans authentification

- **Severite:** HIGH
- **CWE:** CWE-306 (Missing Authentication for Critical Function)
- **Fichier:** `pen-backend/src/routes/quiz.ts:15`
- **Description:**
  La route SSE de streaming quiz est explicitement exemptee du middleware d'authentification car EventSource ne supporte pas les headers. Quiconque avec un `sessionId` valide peut recevoir le contenu du quiz d'un autre utilisateur.

- **Exploitabilite:** Moyen (necessite de deviner un UUID de session valide actif dans les dernieres minutes)
- **Impact:** Fuite de contenu de quiz genere pour d'autres utilisateurs
- **Fix recommande:** Passer le token JWT via query parameter (`?token=...`) et le verifier dans le handler SSE, comme c'est deja fait pour les connexions WebSocket.

---

### H-02: Paddle SDK initialise avec fallback vide sur API key manquante

- **Severite:** HIGH
- **CWE:** CWE-636 (Not Failing Securely)
- **Fichier:** `pen-backend/src/services/billing/paddleBilling.ts:25`
- **Description:**
  Si `PADDLE_API_KEY` n'est pas definie, le SDK Paddle est initialise avec une chaine vide au lieu de crasher. Meme pattern pour `PADDLE_PREMIUM_PRICE_ID` (ligne 18).

- **Exploitabilite:** Difficile (erreur de configuration, pas un vecteur d'attaque externe)
- **Impact:** Operations de billing silencieusement defaillantes, possibilite d'accorder des abonnements premium sans paiement reel
- **Fix recommande:** Utiliser le pattern `requireEnv("PADDLE_API_KEY")` deja etabli dans `rateLimiting.ts` pour fail-fast au demarrage.

---

### H-03: Token JWT stocke dans localStorage -- vulnerable au XSS

- **Severite:** HIGH
- **CWE:** CWE-922 (Insecure Storage of Sensitive Information)
- **Fichiers:**
  - `pen-frontend/src/contexts/ClerkAuthContext.tsx:222,297`
  - `pen-frontend/src/services/apiClient.ts:56,60`
  - Multiple hooks et utils qui lisent `localStorage.getItem("pen_saas_token")`
- **Description:**
  Le token d'authentification Clerk est stocke dans `localStorage` sous la cle `pen_saas_token`. `localStorage` est accessible a tout code JavaScript executant dans le meme origin, y compris du code injecte via XSS (voir C-02). Si une faille XSS est exploitee, l'attaquant peut exfiltrer le token et usurper l'identite de la victime.

- **Exploitabilite:** Facile si une faille XSS existe (voir C-02)
- **Impact:** Vol de session complet, acces a toutes les donnees de l'utilisateur
- **Fix recommande:** Migrer vers des cookies httpOnly pour le transport du token. En attendant, corriger toutes les failles XSS (C-02) est la priorite immediate.

---

### H-04: Impersonation permet des actions destructives (suppression de donnees)

- **Severite:** HIGH
- **CWE:** CWE-269 (Improper Privilege Management)
- **Fichier:** `pen-backend/src/middlewares/auth.ts:136`
- **Description:**
  L'impersonation est correctement exclue des routes `/api/admin`, mais pas des routes destructives utilisateur comme :
  - `DELETE /api/content/pages/:id` (suppression de page)
  - `DELETE /api/content/projects/:id` (suppression de projet)
  - `DELETE /api/beta/account` (suppression de compte)
  - `POST /api/billing/cancel` (annulation d'abonnement)

  Un admin impersonant un utilisateur pourrait accidentellement ou volontairement supprimer ses donnees.

- **Exploitabilite:** Facile (l'admin a deja les droits d'impersonation)
- **Impact:** Destruction de donnees utilisateur par un admin impersonant
- **Fix recommande:** Ajouter une liste de routes destructives exclues de l'impersonation, ou ajouter un flag `readOnly` a l'impersonation.

---

## MEDIUM

### M-01: DOMPurify UpdateModal autorise iframe -- risque de clickjacking/phishing

- **Severite:** MEDIUM
- **CWE:** CWE-1021 (Improper Restriction of Rendered UI Layers)
- **Fichier:** `pen-frontend/src/components/updates/UpdateModal.tsx:168-171`
- **Description:**
  DOMPurify est configure avec `ADD_TAGS: ["iframe"]`. L'ouverture d'iframe permet d'embarquer une page externe (phishing, formulaire malicieux) dans le modal de mise a jour.

- **Exploitabilite:** Moyen
- **Impact:** Phishing, vol de credentials via faux formulaire dans un iframe
- **Fix recommande:** Restreindre les URLs autorisees via une allowlist (YouTube, Vimeo) au lieu d'autoriser tous les iframes.

---

### M-02: Logs verbeux en dev exposent des donnees sensibles

- **Severite:** MEDIUM
- **CWE:** CWE-532 (Information Exposure Through Log Files)
- **Fichiers:**
  - `pen-backend/src/routes/upload.ts:126-133` (log publicId + headers)
  - `pen-backend/src/routes/page.ts:303-306` (log htmlPreview du contenu)
  - `pen-backend/src/routes/ai.ts:346-349` (log apiKeyConfigured)
- **Description:**
  De nombreux logs en dev affichent des previews de contenu utilisateur et des informations de configuration. Le `SecureLogger` sanitise en production mais pas en dev.

- **Exploitabilite:** Difficile (necessite acces aux logs du serveur)
- **Impact:** Fuite d'informations personnelles, contenu utilisateur
- **Fix recommande:** Reduire la verbosity meme en dev. Ne jamais logger des previews de contenu utilisateur.

---

### M-03: `PUT /api/content/projects/:id` ne verifie pas l'appartenance du projet

- **Severite:** MEDIUM
- **CWE:** CWE-639 (IDOR)
- **Fichier:** `pen-backend/src/routes/content.ts:243`
- **Description:**
  La route PUT pour mettre a jour un projet fait directement `prisma.project.update({ where: { id } })` sans condition sur `createdBy: userId`. Les routes DELETE et PATCH/pin verifient correctement `createdBy: userId`.

- **Exploitabilite:** Facile
- **Impact:** Modification du nom/description de projets d'autres utilisateurs
- **Fix recommande:** Ajouter `where: { id, createdBy: userId }` ou une verification prealable d'appartenance.

---

### M-04: Debug route exposee en production

- **Severite:** MEDIUM
- **CWE:** CWE-489 (Active Debug Code)
- **Fichier:** `pen-backend/src/routes/quiz.ts:77`
- **Description:**
  La route `POST /api/quiz/sequence/:sequenceId/debug/force-reset` n'est protegee que par `authenticateToken` (pas de verification admin). Tout utilisateur authentifie peut potentiellement reset l'etat d'une sequence de quiz.

- **Exploitabilite:** Facile
- **Impact:** Reset de l'etat de quiz d'autres utilisateurs
- **Fix recommande:** Supprimer la route ou la proteger avec `requireAdmin`. Ajouter une verification d'appartenance du `sequenceId`.

---

### M-05: Configuration CORS autorise requests sans Origin en dev

- **Severite:** MEDIUM
- **CWE:** CWE-346 (Origin Validation Error)
- **Fichier:** `pen-backend/src/index.ts:138-145`
- **Description:**
  En mode developpement, les requetes sans header `Origin` sont autorisees. Si `NODE_ENV` est accidentellement absent ou mal configure, le comportement par defaut est permissif.

- **Exploitabilite:** Moyen
- **Impact:** Bypass CORS pour des requetes cross-origin en cas de misconfiguration
- **Fix recommande:** Bloquer par defaut (no origin = blocked) sauf pour les paths exempts (health, webhooks).

---

## LOW

### L-01: Upload config expose publiquement sans auth

- **Severite:** LOW
- **CWE:** CWE-200 (Information Exposure)
- **Fichier:** `pen-backend/src/routes/upload.ts:210`
- **Description:**
  La route `GET /api/upload/config` est accessible sans authentification et expose la configuration d'upload.

- **Fix recommande:** Proteger avec `authenticateToken` ou supprimer.

---

### L-02: Article quotidien servi sans auth -- risque de scraping

- **Severite:** LOW
- **CWE:** CWE-306
- **Fichier:** `pen-backend/src/routes/dailyArticle.ts:26`
- **Description:**
  `GET /api/daily-article` est public. Pas de rate limiting specifique.

- **Fix recommande:** Ajouter un rate limiting specifique.

---

### L-03: `DailyArticle.refresh` protege par IP -- contournable derriere un reverse proxy

- **Severite:** LOW
- **CWE:** CWE-290 (Authentication Bypass by Spoofing)
- **Fichier:** `pen-backend/src/routes/dailyArticle.ts:9-22`
- **Description:**
  Verification par IP qui peut etre contournee derriere un load balancer.

- **Fix recommande:** Utiliser un secret header ou un token d'API interne.

---

### L-04: Absence de Content-Security-Policy (CSP) explicite

- **Severite:** LOW
- **CWE:** CWE-1021
- **Fichier:** `pen-backend/src/index.ts:131`
- **Description:**
  `helmet()` avec defauts mais pas de CSP personnalisee.

- **Fix recommande:** Definir une CSP explicite adaptee aux besoins de Pennote.

---

### L-05: WebSocket token passe en query string -- visible dans les logs

- **Severite:** LOW
- **CWE:** CWE-598 (Use of GET Request Method With Sensitive Query Strings)
- **Fichier:** `pen-backend/src/index.ts:564`
- **Description:**
  Le token JWT est passe comme query parameter dans l'URL WebSocket. Limitation connue du protocole.

- **Fix recommande:** Utiliser des tokens a courte duree de vie specifiques aux WebSocket, ne pas logger les URLs avec query parameters.

---

## Resume des actions par priorite

| # | Severite | Finding | Effort de fix |
|---|----------|---------|---------------|
| C-01 | CRITICAL | SQL injection `$queryRawUnsafe` dans RAG | Moyen |
| C-02 | CRITICAL | XSS rendu HTML non sanitise | Faible |
| C-03 | CRITICAL | IDOR ecriture pages sans verification d'acces | Faible |
| H-01 | HIGH | SSE quiz sans auth | Moyen |
| H-02 | HIGH | Paddle SDK silent fail sur key manquante | Faible |
| H-03 | HIGH | Token JWT dans localStorage | Eleve |
| H-04 | HIGH | Impersonation permet des actions destructives | Faible |
| M-01 | MEDIUM | DOMPurify autorise iframes | Faible |
| M-02 | MEDIUM | Logs verbeux | Faible |
| M-03 | MEDIUM | IDOR update project | Faible |
| M-04 | MEDIUM | Debug route en production | Faible |
| M-05 | MEDIUM | CORS permissif sans origin en dev | Faible |
| L-01 | LOW | Upload config sans auth | Faible |
| L-02 | LOW | Article quotidien sans rate limit | Faible |
| L-03 | LOW | IP-based auth contournable | Faible |
| L-04 | LOW | Pas de CSP explicite | Moyen |
| L-05 | LOW | WS token en query string | Faible |

---

## Points positifs notes

- Auth middleware (`authenticateToken`) applique systematiquement sur toutes les routes sensibles
- Rate limiting multicouche (global, auth, AI, quiz, assistant, admin, beta) avec Redis store
- RBAC admin verifie en base de donnees a chaque requete (`requireAdmin`)
- Impersonation avec TTL 15 min, audit log, interdiction d'impersonate un admin
- Validation UUID sur les IDs de page (`validateUUID` middleware)
- Workspace access verification middleware (`verifyWorkspaceAccess`, `verifyWorkspaceOwnership`)
- Webhook Paddle avec verification de signature HMAC et idempotence
- Chiffrement AES-256-GCM pour les donnees thinking
- `SecureLogger` avec sanitization des donnees sensibles en production
- Error handler global qui ne fuit pas les stack traces en production
- `helmet()` active par defaut
- Pas de secrets hardcodes dans le code source (tout en env vars via Infisical)
- `.gitignore` exclut correctement `.env` et `.env.*`
- Test auth safeguards multicouche (5 conditions independantes pour activer le mode test)
- Job results protege par verification d'ownership
- Aucun usage de `eval()` ou constructeur Function dynamique dans le codebase
- Pas de `child_process` / command injection vectors
- Pas de SSRF (le seul `fetch` externe cible des URLs fixes : OpenAI API)
- Body size limit (`10mb`) configure sur `express.json()`
- WebSocket max payload limite a 1MB
