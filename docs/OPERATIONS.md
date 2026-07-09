# Operacoes

## Processamento automatico de rodadas

O processamento operacional roda uma vez por minuto e chama:

```sql
SELECT public.process_due_rounds(now());
```

A migration `20260709170000_operational_automation.sql` tenta habilitar
`pg_cron` e registra o job unico `bagrefut-process-due-rounds` com agenda:

```cron
* * * * *
```

Se o ambiente nao permitir `pg_cron`, a camada DB continua funcional. Use um
scheduler externo chamando o endpoint server-only equivalente:

```http
POST /api/internal/jobs/process-due-rounds
Authorization: Bearer <INTERNAL_JOB_SECRET>
```

## Timeline diaria

Os horarios abaixo sao gerados nas linhas de `rounds` e devem ser lidos do
banco, nunca hardcoded no scheduler:

- `lineup_lock_at`: normalmente 21:55 America/Belem; marca
  `rounds.lineups_locked_at`.
- `starts_at`: normalmente 22:00 America/Belem; simula as 3 partidas da rodada
  e credita `match_reward`.
- `ends_at`: normalmente 22:10 America/Belem; valida 3 partidas `finished`,
  marca `rounds.is_processed = true` e preenche `rounds.finalized_at`.

O processador suporta atraso. Se o servidor voltar as 22:07, a mesma chamada
executa o lock pendente e a simulacao pendente.

## Retries e dead jobs

Cada etapa cria ou reutiliza uma linha em `operational_job_runs` com chave unica:

```sql
(job_type, target_id, scheduled_for)
```

Fluxo:

- primeira tentativa: `attempt_count = 1`
- falha: `status = failed`, `last_error` preenchido e `next_retry_at` calculado
- backoff: 1 min, 2 min, 4 min, 8 min, 16 min
- quinta falha: `status = dead`

Falhas de uma etapa rodam em subtransacao. Eventos, snapshots, estatisticas e
ledger criados durante uma tentativa que falha sao revertidos antes de gravar o
erro do job.

## Recuperacao manual

Admins approved consultam as ultimas execucoes pela UI ou pela RPC:

```sql
SELECT *
FROM public.admin_list_operational_job_runs(50, NULL);
```

Jobs `failed` e `dead` podem ser reenfileirados pela UI admin. O navegador nao
recebe `INTERNAL_JOB_SECRET`; a UI chama uma server function autenticada como
admin, e o servidor usa service role.

O endpoint interno de retry aceita o mesmo tipo de recuperacao para automacao:

```http
POST /api/internal/jobs/retry
Authorization: Bearer <INTERNAL_JOB_SECRET>
Content-Type: application/json

{ "job_run_id": "00000000-0000-0000-0000-000000000000" }
```

## Segredos

Variaveis necessarias no servidor:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `INTERNAL_JOB_SECRET`

Opcional para desenvolvimento/teste:

- `INTERNAL_JOBS_ALLOW_NOW_OVERRIDE=true`

Nunca exponha `SUPABASE_SERVICE_ROLE_KEY` ou `INTERNAL_JOB_SECRET` no client,
em logs de resposta ou em arquivos `.env` versionados.

## Verificacoes manuais

Ver cron registrado:

```sql
SELECT jobid, jobname, schedule, command, active
FROM cron.job
WHERE jobname = 'bagrefut-process-due-rounds';
```

Ver execucoes do cron:

```sql
SELECT jobid, status, start_time, end_time, return_message
FROM cron.job_run_details
WHERE jobid IN (
  SELECT jobid
  FROM cron.job
  WHERE jobname = 'bagrefut-process-due-rounds'
)
ORDER BY start_time DESC
LIMIT 20;
```

Ver jobs operacionais:

```sql
SELECT job_type, target_id, scheduled_for, status, attempt_count, next_retry_at,
       started_at, finished_at, last_error
FROM public.operational_job_runs
ORDER BY created_at DESC
LIMIT 50;
```
