# Scale Roadmap

Optimisations a declencher selon le nombre d'utilisateurs concurrent.
Chaque fichier = un palier avec les actions a faire.

| Palier | Fichier | Trigger |
|--------|---------|---------|
| 500 concurrent | [500-concurrent/](500-concurrent/) | Pool exhaustion, latence chat > 500ms |
| 2000 concurrent | [2000-concurrent/](2000-concurrent/) | DB saturee, Redis bottleneck |
| 10000 concurrent | [10000-concurrent/](10000-concurrent/) | Horizontal scaling, infra redesign |
