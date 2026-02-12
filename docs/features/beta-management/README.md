# Beta Management System

> **Status:** Design validé | **Date:** 2026-02-05

---

## Vue d'ensemble

Système de gestion des bêta-testeurs avec places limitées, tracking d'activité et waitlist automatique.

### Objectifs

- **100 places max** pour la beta privée
- **Engagement réel** : kick automatique des inactifs après 7 jours
- **Waitlist FIFO** : premier inscrit = premier servi quand une place se libère
- **Pas de gaming** : tracking silencieux (l'utilisateur ne voit pas les critères exacts)

---

## Fonctionnement

```
NOUVEAU USER ──► Places dispo ? ──► OUI ──► Clerk Sign-up ──► ACTIF
                     │
                     ▼
                    NON ──► Formulaire Waitlist ──► EN ATTENTE
                                                        │
                                                        ▼
                                                   Place dispo
                                                        │
                                                        ▼
                                                   Email + 7j délai
                                                        │
                                              ┌────────┴────────┐
                                              ▼                 ▼
                                           Réactive         SUPPRIMÉ
                                              │
                                              ▼
                                           ACTIF

USER ACTIF ──► 7j inactif ──► DÉSACTIVÉ ──► Revient ? ──► Place dispo ? ──► ...
```

---

## Critères d'activité (silencieux)

L'utilisateur doit satisfaire **3 critères sur 4** en 7 jours :

| Critère | Seuil |
|---------|-------|
| Sessions | ≥ 3 connexions |
| Temps actif | ≥ 15 minutes |
| Contenu | ≥ 1 page avec >100 caractères |
| Features | ≥ 1 utilisation AI ou Quiz |

---

## Documentation

| Document | Description |
|----------|-------------|
| [DOC.md](./DOC.md) | Spécifications techniques complètes |
| [ROADMAP.md](./ROADMAP.md) | Plan d'implémentation |

---

## Stack technique

| Composant | Technologie |
|-----------|-------------|
| Auth | Clerk |
| DB | Prisma + PostgreSQL |
| Jobs | BullMQ + Redis |
| Emails | À définir |
| Tracking temps | Heartbeat 30s custom |
