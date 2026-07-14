# PlayerCard e abertura do pacote inicial

## Estrutura do componente

```text
src/components/player-card/
  PlayerCard.tsx     - componente visual compartilhado
  player-card.css    - estilos (container queries, paleta por raridade)
  types.ts           - PlayerCardData, DatabasePlayerRecord, props
  adapter.ts         - playerCardFromDatabase, playerImagePath, displaySector, playerCardStats
  index.ts           - barrel de exportação
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
  pacote). Sem grade de atributos - atributos completos ficam no detalhe.

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
peba -> aço/grafite
paia -> violeta
pika -> ouro escuro
```

A paleta é aplicada via `data-rarity` no elemento raiz da carta.

## Nome exibido e chave técnica

- `players.name` é o nome oficial de display. Não existe mapa paralelo de
  nomes no frontend: qualquer troca futura de nomes no banco aparece
  automaticamente, sem alteração de código.
- `players.code` (ex.: `ATA12`) é identificador técnico e chave do asset de
  imagem. **O code nunca é exibido na UI** - nem em textos, labels,
  tooltips, fallbacks ou `aria-label`.

O setor é formatado somente para display (`bela_vista -> BELA VISTA`); o
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
- Formato final: WebP `1024x1024`, qualidade 82.
- Cobertura total: 60 jogadores e 60 fotos (`GK` 12, `DEF` 18, `MID` 18,
  `ATA` 12).

### Pipeline de conversão

As fotos brutas (JPEG/JFIF/WebP, inclusive em subdiretórios) ficam fora do git
em `./player-images-raw`. O pipeline (`scripts/process-player-images.mjs`, com
`sharp`) extrai o código pelo padrão `^(GK|DEF|MID|ATA)\d{2}`, aplica
autorrotação EXIF, converte para sRGB, remove metadados, recorta em
`1024x1024` (crop por atenção, com overrides manuais em
`scripts/player-image-config.mjs`) e grava o WebP final.

```bash
bun run assets:players   # converte a partir de ./player-images-raw
bun run assets:players -- --source <dir> --position MID
bun run check:players    # valida os 60 assets (nome, formato real, 1024x1024)
```

`check:players` também roda dentro de `bun run check`.

### Fallback

Erro de carregamento, imagem ausente ou código inválido nunca mostra ícone
quebrado nem o code: como mecanismo de resiliência, a carta exibe silhueta +
iniciais derivadas de `players.name` + posição, com texto acessível
`Sem foto de <nome>` (`role="img"` + `aria-label`).

## Composição dos pacotes

A composição não é sorteada carta por carta. Banco possui seis templates
privados, `PACK01` a `PACK06`, com 10 jogadores cada:

- 2 goleiros;
- 3 defensores;
- 3 meio-campistas;
- 2 atacantes.

Cada jogador aparece em exatamente um template. Cada template pode ser
associado a somente um clube por `initial_packs.starter_pack_template_id
UNIQUE`.

`create_club` escolhe aleatoriamente um template livre e o reserva na mesma
transação que cria clube, crédito inicial e pacote fechado. Conteúdo não é
revelado antes da abertura.

## Fluxo de abertura (`/abrir-pacote`)

Máquina de estados em `src/domain/pack-opening.ts`:

```text
loading -> sealed -> opening -> revealing -> summary
                 \-> error             \-> already-opened
```

- Backend: `getInitialPackExperience` (GET) e `openInitialPack` (POST) em
  `src/lib/pack.functions.ts`, sempre via `context.supabase` (RLS). A RPC
  transacional `open_initial_pack` continua sendo a única mutação.
- A RPC transfere exatamente as 10 cartas do template associado ao pacote.
- Estoque comercial (`is_market_eligible = true`) nunca é consumido.
- Repetir a RPC após abertura retorna os mesmos 10 itens, sem duplicar posse
  ou `initial_pack_items`.
- Ordem de apresentação (`sortPackCardsForReveal`): overall crescente ->
  raridade crescente (`peba < paia < pika`) -> slot crescente. Afeta somente
  apresentação; composição e posse não mudam.
- Uma carta por vez, sem autoplay: verso -> clique (`Enter`/`Space` também)
  -> animação da raridade -> carta vira -> clique para próxima.
- Durações aproximadas: peba 500ms, paia 800ms, pika 1300ms. Transições
  inválidas são ignoradas pela máquina de estados.
- Progresso persiste em `sessionStorage` sob a chave
  `bagrefut:pack-reveal:<pack.id>` com `{ packId, revealedCount, stage }`.
  Refresh na mesma sessão retoma próxima carta; pacote já aberto sem estado
  de sessão vai direto ao resumo. Conteúdo das cartas nunca é armazenado -
  sempre recarregado do backend.
- Preload: 10 caminhos WebP são pré-carregados após resposta, com primeira
  carta em prioridade alta; asset ausente cai no fallback sem bloquear fluxo.

## Movimento reduzido

Com `@media (prefers-reduced-motion: reduce)`:

- sem shake do pacote, flashes fortes ou partículas;
- virada da carta vira transição curta;
- controle por clique permanece, sem revelação automática.

## Áudio

Sem áudio nesta fase. Animações não estão acopladas a arquivos sonoros;
camada futura pode observar mudanças de fase da máquina de estados.
