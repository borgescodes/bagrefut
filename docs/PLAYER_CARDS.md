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
  className?: string;
  priority?: boolean; // eager + fetchPriority=high para a primeira carta
  interactive?: boolean;
  selected?: boolean;
  disabled?: boolean;
};
```

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

## Nome exibido

O nome vem direto de `players.name`. Não existe mapa paralelo de nomes no
frontend: qualquer troca futura de nomes no banco aparece automaticamente,
sem alteração de código.

O setor é formatado somente para display (`bela_vista → BELA VISTA`); o
valor persistido não muda.

## Assets das imagens

Convenção obrigatória:

```text
/public/players/<players.id>.webp
```

- A imagem usa `players.id` (UUID), **nunca** `players.code`.
- `playerImagePath(playerId)` valida o UUID antes de montar o caminho e
  lança para valores inválidos.
- Tamanho recomendado: `1024x1024`, formato WebP.
- Exemplo real (CSV de referência): jogador `GK01` →
  `public/players/c35816ce-8471-4ec9-bce7-1eb34cd8e4d6.webp`.

### Fallback

Imagem ausente ou id inválido nunca mostra ícone quebrado: a carta exibe um
fallback coerente com a raridade (silhueta em gradiente) com o `code` do
jogador, mantendo dimensões e acessibilidade (`role="img"` + `aria-label`).

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
