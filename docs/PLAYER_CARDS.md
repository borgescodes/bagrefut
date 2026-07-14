# PlayerCard e abertura do pacote inicial

## Estrutura do componente

```text
src/components/player-card/
  PlayerCard.tsx     — componente visual compartilhado
  player-card.css    — estilos (container queries, paleta por raridade)
  types.ts           — PlayerCardData, DatabasePlayerRecord, props
  adapter.ts         — playerCardFromDatabase, playerImagePath, displaySector, playerCardStats
  index.ts           — barrel de exportação
```

O componente é desacoplado de mercado, pacote e Supabase: recebe um
`PlayerCardData` pronto. A conversão da linha de `public.players` para o
modelo visual é feita por `playerCardFromDatabase(row)`.

Props:

```ts
type PlayerCardProps = {
  player: PlayerCardData;
  variant?: "full" | "compact"; // full: revelação/detalhe; compact: grades
  priceLabel?: string; // rodapé opcional do compact (mercado)
  className?: string;
  priority?: boolean; // eager + fetchPriority=high para a primeira carta
  interactive?: boolean;
  selected?: boolean;
  disabled?: boolean;
};
```

### Variantes

- `full` (padrão): carta completa com trilho lateral (setor/raridade) e a
  grade de 6 atributos. Largura limitada a `min(100%, 21rem)`. Uso:
  revelação do pacote, diálogo/detalhe, visualização ampliada.
- `compact`: foto + nome + overall + posição + setor (e preço opcional),
  aspecto `3/4`, pensada para grades densas (elenco, mercado, resumo do
  pacote). Sem grade de atributos — atributos completos ficam no detalhe.

## Atributos exibidos

Grade inferior com 6 atributos, em duas colunas e três linhas.

Goleiros (`GK`):

```text
GK  = goalkeeping
DRI = dribbling
VEL = velocity
DEF = defending
PAS = passing
PHY = physical
```

Linha (`DEF`, `MID`, `ATA`):

```text
FIN = finishing
DRI = dribbling
VEL = velocity
DEF = defending
PAS = passing
PHY = physical
```

A ordem visual é gerada por `playerCardStats(player)` (testada em
`src/test/player-card.test.ts`).

## Raridades e paletas

```text
peba → aço/grafite
paia → violeta
pika → ouro escuro
```

A paleta é aplicada via `data-rarity` no elemento raiz da carta.

## Nome exibido e chave técnica

- `players.name` é o nome oficial de display. Não existe mapa paralelo de
  nomes no frontend: qualquer troca futura de nomes no banco aparece
  automaticamente, sem alteração de código.
- `players.code` (ex.: `ATA12`) é identificador técnico e chave do asset de
  imagem. **O code nunca é exibido na UI** — nem em textos, labels,
  tooltips, fallbacks ou `aria-label`.

O setor é formatado somente para display (`bela_vista → BELA VISTA`); o
valor persistido não muda.

## Assets das imagens

Convenção obrigatória:

```text
public/players/<players.code>.webp
```

Exemplo:

```text
public/players/ATA12.webp
```

- O asset usa `players.code`, **nunca** `players.id` (UUID).
- `playerImagePath(code)` normaliza (trim + uppercase), aceita somente as
  faixas `GK01-GK12`, `DEF01-DEF18`, `MID01-MID18`, `ATA01-ATA12` e lança
  para UUID ou código malformado.
- Formato final: WebP `1024x1024`, qualidade ~82.
- Jogadores `MID` não têm foto nesta fase e usam o fallback por nome.

### Pipeline de conversão

As fotos brutas (JPEG/JFIF com extensões duplicadas) ficam fora do git em
`./player-images-raw`. O pipeline (`scripts/process-player-images.mjs`, com
`sharp`) extrai o código pelo padrão `^(GK|DEF|MID|ATA)\d{2}`, aplica
autorrotação EXIF, converte para sRGB, remove metadados, recorta em
`1024x1024` (crop por atenção, com overrides manuais em
`scripts/player-image-config.mjs`) e grava o WebP final.

```bash
bun run assets:players   # converte a partir de ./player-images-raw
bun run check:players    # valida os 42 assets (nome, formato real, 1024x1024)
```

`check:players` também roda dentro de `bun run check`.

### Fallback

Imagem ausente ou código inválido nunca mostra ícone quebrado nem o code: a
carta exibe silhueta + iniciais derivadas de `players.name` + posição, com
texto acessível `Sem foto de <nome>` (`role="img"` + `aria-label`).

## Fluxo de abertura (`/abrir-pacote`)

Máquina de estados em `src/domain/pack-opening.ts`:

```text
loading → sealed → opening → revealing → summary
                 ↘ error            ↘ already-opened (pacote já aberto sem sessão)
```

- Backend: `getInitialPackExperience` (GET) e `openInitialPack` (POST) em
  `src/lib/pack.functions.ts`, sempre via `context.supabase` (RLS). A RPC
  transacional `open_initial_pack` continua sendo a única mutação.
- Ordem de apresentação (`sortPackCardsForReveal`): overall crescente →
  raridade crescente (`peba < paia < pika`) → slot crescente. Afeta somente
  a apresentação; sorteio, slots e propriedade não mudam.
- Uma carta por vez, sem autoplay: verso → clique (`Enter`/`Space` também)
  → animação da raridade → carta vira → clique para a próxima.
- Durações aproximadas: peba 500ms, paia 800ms, pika 1300ms. Transições
  inválidas (clique duplo, avanço durante animação, reabertura) são
  ignoradas pela máquina de estados.
- Progresso persiste em `sessionStorage` sob a chave
  `bagrefut:pack-reveal:<pack.id>` com `{ packId, revealedCount, stage }`.
  Refresh na mesma sessão retoma a próxima carta; pacote já aberto sem
  estado de sessão vai direto ao resumo. O conteúdo das cartas nunca é
  armazenado — sempre recarregado do backend.
- Preload: os 10 caminhos WebP são pré-carregados após a resposta, com a
  primeira carta em prioridade alta; assets ausentes caem no fallback sem
  bloquear o fluxo.

## Movimento reduzido

Com `@media (prefers-reduced-motion: reduce)`:

- sem shake do pacote, sem flashes fortes, sem partículas;
- a virada da carta vira uma transição curta;
- o controle por clique permanece — nada é revelado automaticamente.

## Áudio

Sem áudio nesta fase. As animações não estão acopladas a arquivos sonoros;
uma futura camada de som pode observar as mudanças de fase da máquina de
estados.
