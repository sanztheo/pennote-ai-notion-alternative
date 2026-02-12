# RAG System - Analyse et Améliorations

> **Date:** 4 février 2026
> **Status:** Analyse complète, implémentation en attente
> **Priorité:** Moyenne (système fonctionnel, optimisations optionnelles)

---

## 1. Architecture RAG Actuelle

### Flux de traitement

```
User sélectionne pages (1-30)
       ↓
[Vérification cache] → Skip si déjà embedded + non modifié
       ↓
[Chunking] → Split par sections (headers) puis paragraphes
       ↓
[Embedding] → OpenAI text-embedding-3-small (1536 dim)
       ↓
[Stockage] → PostgreSQL + pgvector
       ↓
[Recherche] → Vector similarity search
       ↓
[Contexte] → Top 5-10 chunks → Prompt LLM
       ↓
[Génération] → Questions de quiz
```

### Fichiers clés

| Fichier | Rôle |
|---------|------|
| `src/services/rag/index.ts` | Moteur RAG principal (~2000 lignes) |
| `src/services/rag/userPages.ts` | Processing des pages utilisateur |
| `src/controllers/quiz/content/ragController.ts` | API endpoints RAG |
| `src/services/quiz/intelligence/smartContentSelector.ts` | Sélection intelligente du contexte |

### Configuration actuelle

| Paramètre | Valeur | Fichier |
|-----------|--------|---------|
| Chunk size max | 1200 chars | `userPages.ts:392` |
| Chunks récupérés | 5-10 | `ragController.ts:246` |
| Similarity threshold | 0.2 | `rag/index.ts:760` |
| Embedding concurrency | 2 | `RAG_EMBEDDING_CONCURRENCY` env |
| Token budget contexte | 8000 | `smartContentSelector.ts` |

---

## 2. Points forts du système

| Aspect | Implémentation | Verdict |
|--------|---------------|---------|
| **Chunking par sections** | Split par headers puis paragraphes | Bon |
| **Score de qualité** | Pénalités/bonus selon longueur (0.6-1.1x) | Bon |
| **Cache intelligent** | Skip si déjà embedded + non modifié | Excellent |
| **Concurrency** | Configurable via env var | Bon |
| **Filtrage sources** | Par userId, workspaceId, specificSourceIds | Solide |
| **Diversification** | Round-robin pour éviter concentration | Bon |
| **Detection type query** | RESUME / EXPLICATION / FACTUELLE | Bon |

---

## 3. Améliorations recommandées

### 3.1 Overlap dans le chunking (PRIORITÉ 1)

**Problème actuel :**
```
[chunk1: "...fin phrase A"][chunk2: "Début phrase B..."]
         ↑ Coupure nette = perte de contexte aux frontières
```

**Solution :**
```typescript
// userPages.ts - Ajouter overlap de 200 chars
const overlap = 200;

// Nouveau chunking avec chevauchement
[chunk1: "...fin phrase A + début B"][chunk2: "début B... milieu"][chunk3: "milieu... fin"]
```

**Impact :** Meilleure retrieval des infos aux frontières de chunks
**Effort :** 30 minutes
**Fichier à modifier :** `src/services/rag/userPages.ts` (méthode `chunkLongText`)

---

### 3.2 Reranker Cohere (PRIORITÉ 2)

**Problème actuel :**
```
Query → Vector search → Top 10 → Prompt
                        ↑ Résultats approximatifs
```

**Solution avec reranker :**
```
Query → Vector search → Top 30 → Cohere Rerank → Top 10 → Prompt
                                       ↑ Précision +15-20%
```

**Implémentation :**
```typescript
import { CohereClient } from 'cohere-ai';

const cohere = new CohereClient({ token: process.env.COHERE_API_KEY });

async function rerankResults(query: string, documents: string[]): Promise<string[]> {
  const response = await cohere.rerank({
    model: 'rerank-english-v3.0',  // ou rerank-multilingual-v3.0
    query,
    documents,
    topN: 10,
  });

  return response.results.map(r => documents[r.index]);
}
```

**Coût :** ~$0.001 par 1000 documents (quasi gratuit)
**Impact :** Amélioration significative de la pertinence
**Effort :** 2 heures
**Fichier à modifier :** `src/services/rag/index.ts` (méthode `search`)

---

### 3.3 Augmenter le nombre de chunks récupérés (PRIORITÉ 3)

**Changement simple :**
```typescript
// ragController.ts ligne 246
// AVANT
limit: scopeMode === "pages_only" ? 5 : 10

// APRÈS
limit: scopeMode === "pages_only" ? 10 : 20
```

**Impact :** Plus de contexte disponible pour le LLM
**Effort :** 5 minutes
**Note :** Faire attention au token budget (8000 tokens)

---

### 3.4 Chunking sémantique (PRIORITÉ 4)

**Problème actuel :**
```typescript
const maxChunkSize = 1200;  // Arbitraire, coupe au milieu des idées
```

**Solution avec LangChain :**
```typescript
import { RecursiveCharacterTextSplitter } from 'langchain/text_splitter';

const splitter = new RecursiveCharacterTextSplitter({
  chunkSize: 1000,
  chunkOverlap: 200,
  separators: ['\n\n', '\n', '. ', ' ', ''],  // Priorité aux séparateurs naturels
});

const chunks = await splitter.splitText(content);
```

**Impact :** Chunks plus cohérents sémantiquement
**Effort :** 4 heures
**Dépendance :** `npm install langchain`

---

### 3.5 Query expansion / HyDE (PRIORITÉ 5 - Optionnel)

**Concept :** Enrichir la query avant la recherche

**HyDE (Hypothetical Document Embeddings) :**
```typescript
// Générer un "document hypothétique" qui répondrait à la query
const hypotheticalDoc = await llm.generate(`
  Écris un paragraphe de cours qui répondrait à: "${query}"
`);

// Utiliser l'embedding de ce doc hypothétique pour la recherche
const embedding = await embed(hypotheticalDoc);
```

**Impact :** Meilleure correspondance sémantique
**Effort :** 1 jour
**Coût :** +1 appel LLM par recherche

---

## 4. Améliorations NON recommandées

| Technique | Raison |
|-----------|--------|
| **Hybrid search BM25 + Vector** | Complexité excessive pour le gain |
| **Fine-tuning embeddings** | Pas assez de données d'entraînement |
| **GraphRAG** | Overkill pour des quiz, complexité maintenance |
| **Multi-vector retrieval** | Complexité inutile pour le use case |
| **Embedding personnalisés** | text-embedding-3-small suffit |

---

## 5. Métriques de performance actuelles

### Temps de traitement estimé (30 pages)

| Phase | Temps | Notes |
|-------|-------|-------|
| Content extraction | 100-200ms | Parse BlockNote x 30 |
| Chunking | 200-300ms | Split + analyse x 30 |
| Embedding (si cache miss) | 3-4s | ~135 chunks / 2 concurrency |
| DB batch inserts | 1-2s | 135 chunks / 100 batch |
| RAG search | 500-800ms | pgvector similarity |
| Context building | 100-200ms | Format chunks |
| Question generation | 3-5s | LLM completion |
| **TOTAL** | **8-15s** | Cache hit: ~5-10s |

### Consommation tokens

| Composant | Tokens |
|-----------|--------|
| Contexte RAG | ~3000-4000 |
| System prompt | ~500-800 |
| Output questions | ~2000 max |
| **TOTAL par quiz** | **~5000-7000** |

**Coût estimé :** ~$0.02-0.04 par quiz (GPT-4)

---

## 6. Plan d'implémentation suggéré

### Phase 1 : Quick wins (1-2 jours)
- [ ] Ajouter overlap 200 chars dans `userPages.ts`
- [ ] Augmenter limite chunks à 15-20
- [ ] Tester impact sur qualité des questions

### Phase 2 : Reranking (1 jour)
- [ ] Intégrer Cohere Rerank API
- [ ] Modifier `rag/index.ts` pour rerank après vector search
- [ ] A/B test avec/sans reranker

### Phase 3 : Optimisation avancée (optionnel)
- [ ] Chunking sémantique avec LangChain
- [ ] Query expansion si besoin détecté
- [ ] Métriques de retrieval quality

---

## 7. Variables d'environnement à ajouter

```bash
# Reranker Cohere (Phase 2)
COHERE_API_KEY=xxx

# Tuning RAG (optionnel)
RAG_CHUNK_OVERLAP=200
RAG_SEARCH_LIMIT=20
RAG_RERANK_ENABLED=true
```

---

## 8. Références

- [OpenAI Embeddings](https://platform.openai.com/docs/guides/embeddings)
- [Cohere Rerank](https://docs.cohere.com/docs/rerank)
- [LangChain Text Splitters](https://js.langchain.com/docs/modules/data_connection/document_transformers/)
- [pgvector Documentation](https://github.com/pgvector/pgvector)

---

## 9. Verdict

**Score actuel : 7/10** - Système fonctionnel et bien architecturé.

**Avec les améliorations prioritaires : 8.5/10**
- Overlap chunking (+0.5)
- Reranker Cohere (+1.0)

**ROI :** Les 2 premières améliorations (3h de travail) apportent 80% du gain potentiel.
