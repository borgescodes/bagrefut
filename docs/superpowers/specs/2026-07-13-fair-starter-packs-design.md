# Pacotes iniciais justos e correção do mercado

Data: 2026-07-13

## Objetivo

Substituir sorteio atual de 10 cartas independentes por 6 pacotes fechados e balanceados. Cada clube recebe aleatoriamente 1 pacote exclusivo. Nenhum pacote pode repetir.

Corrigir mercado para sempre mostrar somente cartas do clube autenticado. Conta admin não pode receber todas as 60 cartas no contador do elenco.

## Estado atual

- `open_initial_pack` seleciona 10 cartas com `ORDER BY random()`.
- Sorteio independente pode formar elencos desequilibrados.
- `loadRoster()` consulta `club_players` sem filtro explícito de `club_id`.
- RLS permite leitura ampla para admin. Resultado: admin pode receber 60 cartas e UI mostra `60/10`.
- Estoque inicial usa `system_market_stock.is_market_eligible = false`.
- Estoque comercial usa `system_market_stock.is_market_eligible = true`.

## Regras

1. Existem exatamente 6 templates de pacote.
2. Cada template contém exatamente 10 jogadores.
3. Cada jogador aparece em exatamente 1 template.
4. Cada clube recebe exatamente 1 template.
5. Cada template pode ser atribuído a no máximo 1 clube.
6. A atribuição ao clube é aleatória entre templates livres.
7. A abertura entrega exatamente cartas do template atribuído.
8. Nenhuma carta comercial pode entrar em pacote inicial.
9. Pacote aberto novamente retorna mesmos itens sem nova mutação.
10. Clube sem pacote livre não pode ser criado.
11. Mercado filtra elenco por `club_id` explicitamente, mesmo para admin.
12. Mercado do sistema filtra `is_market_eligible = true` explicitamente, mesmo para admin.

## Composição dos pacotes

### Pacote 1

- OVR total esperado: 579
- OVR titular informado: 335
- GK: `GK05`, `GK11`
- DEF: `DEF11`, `DEF09`, `DEF03`
- MID: `MID04`, `MID14`, `MID13`
- ATA: `ATA01`, `ATA12`

### Pacote 2

- OVR total esperado: 578
- OVR titular informado: 335
- GK: `GK01`, `GK03`
- DEF: `DEF05`, `DEF02`, `DEF16`
- MID: `MID08`, `MID09`, `MID18`
- ATA: `ATA07`, `ATA08`

### Pacote 3

- OVR total esperado: 579
- OVR titular informado: 336
- GK: `GK02`, `GK12`
- DEF: `DEF10`, `DEF14`, `DEF13`
- MID: `MID05`, `MID06`, `MID15`
- ATA: `ATA04`, `ATA03`

### Pacote 4

- OVR total esperado: 579
- OVR titular informado: 336
- GK: `GK06`, `GK09`
- DEF: `DEF07`, `DEF08`, `DEF18`
- MID: `MID07`, `MID02`, `MID12`
- ATA: `ATA06`, `ATA09`

### Pacote 5

- OVR total esperado: 578
- OVR titular informado: 336
- GK: `GK07`, `GK10`
- DEF: `DEF01`, `DEF17`, `DEF12`
- MID: `MID10`, `MID03`, `MID17`
- ATA: `ATA02`, `ATA11`

### Pacote 6

- OVR total esperado: 579
- OVR titular informado: 336
- GK: `GK04`, `GK08`
- DEF: `DEF04`, `DEF06`, `DEF15`
- MID: `MID01`, `MID11`, `MID16`
- ATA: `ATA05`, `ATA10`

## Modelo de dados

### `starter_pack_templates`

Campos:

- `id uuid primary key`
- `code text not null unique`, valores `PACK01` a `PACK06`
- `expected_total_overall smallint not null`
- `expected_starter_overall smallint not null`
- `created_at timestamptz not null default now()`

Tabela sem leitura para `anon` ou `authenticated`. Acesso direto somente `service_role`. RPCs `SECURITY DEFINER` usam tabela internamente.

### `starter_pack_template_items`

Campos:

- `template_id uuid not null references starter_pack_templates(id) on delete cascade`
- `player_id uuid not null references players(id) on delete restrict`
- `slot smallint not null check (slot between 1 and 10)`
- chave primária `(template_id, slot)`
- `unique(player_id)`

`unique(player_id)` garante que mesma carta não aparece em dois pacotes.

### `initial_packs`

Adicionar:

- `starter_pack_template_id uuid references starter_pack_templates(id) on delete restrict`
- `unique(starter_pack_template_id)`

Após backfill, coluna fica `not null`.

## Seed e validação da migração

Migração forward-only.

Preflight deve falhar antes de alterar contratos quando qualquer condição ocorrer:

- mais de 6 clubes;
- algum pacote já aberto;
- algum clube com carta;
- qualquer código esperado ausente;
- código esperado duplicado;
- quantidade diferente de 60 códigos únicos;
- qualquer carta esperada fora do sistema;
- qualquer carta esperada reservada;
- qualquer carta esperada com `is_market_eligible = true`;
- soma de `players.overall` diferente de OVR total esperado do pacote.

`expected_starter_overall` é metadado de auditoria fornecido pelo balanceamento. Não altera seleção automática nem motor de partida.

Seed resolve `player_id` pelo `players.code`. Slots seguem ordem GK, DEF, MID, ATA listada neste documento.

## Backfill de clubes atuais

Todos clubes atuais estão resetados e sem pacote aberto.

Migração:

1. cria 6 templates;
2. cria 60 itens;
3. embaralha clubes existentes;
4. embaralha templates livres;
5. associa por `row_number()`;
6. valida 1 template por clube e nenhuma repetição;
7. aplica `not null` em `initial_packs.starter_pack_template_id`.

Templates restantes ficam livres quando existem menos de 6 clubes.

## Criação de clube

`create_club` passa a reservar template dentro da mesma transação.

Fluxo:

1. valida usuário, liga, nome, sigla e escudo;
2. seleciona 1 template não usado com ordem aleatória;
3. usa `FOR UPDATE SKIP LOCKED` para concorrência;
4. cria clube;
5. credita saldo inicial;
6. cria `initial_packs` com template reservado;
7. retorna clube.

Sem template livre: erro `starter_pack_templates_exhausted`. Exceção reverte clube e crédito.

Restrição `unique(starter_pack_template_id)` funciona como defesa final contra corrida.

## Abertura do pacote

`open_initial_pack(_club_id)` não usa `random()` para cartas.

Fluxo:

1. autentica e valida usuário aprovado;
2. bloqueia clube e pacote;
3. valida dono e liga em setup;
4. se pacote já aberto, retorna itens existentes na ordem de slot;
5. para pacote fechado, exige elenco vazio;
6. carrega 10 itens do template na ordem de slot;
7. bloqueia `club_players` e `system_market_stock` correspondentes;
8. exige carta no sistema, não reservada e `is_market_eligible = false`;
9. remove cartas do estoque inicial;
10. transfere `club_players.club_id` ao clube;
11. grava `initial_pack_items` preservando slot;
12. marca `opened_at`;
13. retorna mesmos 10 itens.

Falhas possíveis:

- `starter_pack_template_missing`
- `starter_pack_template_invalid`
- `starter_pack_card_unavailable`
- erros existentes de auth, clube, liga e pacote

Qualquer falha reverte transação completa.

## Correção do mercado

### Elenco

Alterar helper para receber clube explícito:

```ts
loadRoster(supabase, clubId)
```

Consulta inclui:

```ts
.eq("club_id", clubId)
```

`getMarketWorkspace` primeiro resolve clube do usuário. Depois carrega elenco com `club.id`.

`getMyRoster` também resolve clube do usuário antes de consultar cartas.

RLS continua ativa, mas não define escopo funcional da tela.

### Mercado do sistema

`loadSystemMarket()` inclui filtro explícito:

```ts
.eq("is_market_eligible", true)
```

Conta admin vê somente estoque comercial na tela pública. Pool inicial permanece invisível.

### UI

Contador continua:

```text
Elenco {roster.length}/10
```

Com filtro correto, clube fechado mostra `0/10`; após abertura mostra `10/10`.

## Segurança e concorrência

- Templates sem SELECT para cliente.
- Atribuição somente por RPC `SECURITY DEFINER`.
- Abertura somente por RPC `SECURITY DEFINER`.
- Locks impedem dois clubes de receber mesmo template.
- Locks impedem duas aberturas de consumir mesma carta.
- Constraints impedem repetição mesmo se lógica falhar.
- Nenhuma decisão de composição ocorre no frontend.

## Testes SQL

Adicionar teste dedicado para:

- 6 templates;
- 10 itens por template;
- 60 jogadores únicos;
- composição exata por código;
- posições `2 GK`, `3 DEF`, `3 MID`, `2 ATA` por template;
- soma de OVR `578` ou `579` conforme pacote;
- associação única entre clube e template;
- criação concorrente sem template repetido;
- sétimo clube falha sem template livre;
- abertura entrega códigos exatos;
- duas chamadas retornam mesmos itens;
- pacote não consome estoque comercial;
- falha atômica quando uma carta do template fica indisponível.

Atualizar testes existentes de `open_initial_pack`, concorrência e economia fechada.

## Testes TypeScript

Adicionar cobertura para:

- `loadRoster` recebe e aplica `clubId`;
- admin não recebe cartas de outros clubes;
- admin não recebe pool inicial como mercado do sistema;
- workspace antes da abertura mostra 0 cartas;
- workspace após abertura mostra 10 cartas;
- invalidadores do React Query continuam funcionando após abertura.

## Documentação

Atualizar:

- `docs/RULES.md`
- `docs/PLAYER_CARDS.md`
- `docs/MARKET.md`
- tipos Supabase gerados quando schema mudar

## Fora de escopo

- alterar atributos ou OVR dos jogadores;
- alterar fórmula de preço;
- alterar treino;
- alterar formações ou simulador;
- criar mais de 6 pacotes;
- permitir escolha manual de pacote;
- revelar composição antes da abertura;
- reset automático de dados incompatíveis.

## Critérios de aceite

1. Seis clubes recebem seis pacotes diferentes.
2. Cada clube abre exatamente composição definida.
3. OVR total por pacote corresponde metadado esperado.
4. Nenhuma carta aparece em dois pacotes.
5. Nenhuma carta comercial entra em pacote.
6. Mercado mostra `0/10` antes e `10/10` após abertura.
7. Admin nunca vê `60/10` no próprio elenco.
8. Testes SQL e TypeScript passam.
9. `npm run check` passa.
