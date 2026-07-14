# Assets de jogadores

Contrato obrigatório:

```text
public/players/<players.code>.webp
```

Exemplo:

```text
public/players/ATA12.webp
```

- A chave do asset é `players.code` (ex.: `GK01`, `DEF18`, `MID18`, `ATA12`) —
  **nunca** `players.id` (UUID) e nunca nomes com espaço, extensão dupla ou
  caixa baixa.
- Formato: WebP real, `1024x1024`, qualidade 82, sem metadados.
- Cobertura: 60 jogadores e 60 fotos — `GK01-GK12` (12), `DEF01-DEF18`
  (18), `MID01-MID18` (18) e `ATA01-ATA12` (12).
- `players.code` é técnico e nunca aparece na UI; o display usa
  `players.name`.
- O fallback por nome é somente um mecanismo de resiliência para erro de
  carregamento ou asset ausente.

## Gerar e validar

```bash
bun run assets:players   # converte ./player-images-raw → public/players/*.webp
bun run assets:players -- --source <dir> --position MID
bun run check:players    # valida contagem, nomes, formato real e dimensões
```

O pipeline vive em `scripts/process-player-images.mjs`; overrides de crop
por código ficam em `scripts/player-image-config.mjs`.
