# Imagens dos jogadores

Formato obrigatório do nome do arquivo:

```text
<players.id>.webp
```

Exemplo:

```text
c35816ce-8471-4ec9-bce7-1eb34cd8e4d6.webp
```

- `players.id` é o UUID da tabela `public.players`.
- Tamanho recomendado: 1024x1024, formato WebP.
- Imagem ausente cai no fallback visual da carta (sem ícone quebrado).

Não usar:

```text
<players.code>.webp        (ex.: GK01.webp)
<club_players.id>.webp
nome do jogador.webp
```
