import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createFileRoute, Link } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import {
  canSubmitMarketAction,
  createListingInputSchema,
  createTransferOfferInputSchema,
  filterAndSortMarketCards,
  formatMarketPrice,
  invalidateMarketQueries,
  projectBalanceAfter,
  projectTradeRosters,
  type MarketCardSummary,
  type MarketFilters,
  type P2PMarketListing,
  type PlayerAttributes,
  type RosterMarketCard,
  type SystemMarketCard,
  type TradeTarget,
  type TransferOfferCard,
  type TransferOfferSummary,
} from "@/domain/market";
import { PLAYER_ATTRIBUTE_KEYS, PLAYER_SECTORS } from "@/domain/enums";
import type { PlayerAttributeKey } from "@/domain/enums";
import {
  acceptTransferOffer,
  buyMarketListing,
  buyPlayerFromSystem,
  cancelMarketListing,
  cancelTransferOffer,
  createMarketListing,
  createTransferOffer,
  getMarketWorkspace,
  getTradeTargetRoster,
  listMyTransferOffers,
  listP2PMarket,
  listTradeTargets,
  rejectTransferOffer,
  sellPlayerToSystem,
  trainClubPlayer,
} from "@/lib/market.functions";
import { mapMarketErrorMessage } from "@/lib/market-errors";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";

export const Route = createFileRoute("/_authenticated/mercado")({
  component: MarketPage,
});

type MarketTab = "system" | "roster" | "p2p" | "offers";
type OfferTab = "incoming" | "outgoing" | "create";

const DEFAULT_FILTERS: MarketFilters = {
  search: "",
  position: null,
  rarity: null,
  sector: null,
  minOverall: null,
  maxOverall: null,
  sortBy: "name",
  sortDirection: "asc",
};

function MarketPage() {
  const queryClient = useQueryClient();
  const workspaceFn = useServerFn(getMarketWorkspace);
  const listingsFn = useServerFn(listP2PMarket);
  const offersFn = useServerFn(listMyTransferOffers);
  const targetsFn = useServerFn(listTradeTargets);
  const [tab, setTab] = useState<MarketTab>("system");
  const [filters, setFilters] = useState<MarketFilters>(DEFAULT_FILTERS);
  const [feedback, setFeedback] = useState<{ tone: "success" | "error"; text: string } | null>(
    null,
  );

  const workspace = useQuery({
    queryKey: ["myClub"],
    queryFn: () => workspaceFn(),
  });
  const listings = useQuery({
    queryKey: ["p2pListings"],
    queryFn: () => listingsFn({ data: {} }),
    enabled: Boolean(workspace.data?.club),
  });
  const offers = useQuery({
    queryKey: ["transferOffers"],
    queryFn: () => offersFn(),
    enabled: Boolean(workspace.data?.club),
  });
  const targets = useQuery({
    queryKey: ["tradeTargets"],
    queryFn: () => targetsFn(),
    enabled: Boolean(workspace.data?.club),
  });

  async function refreshMarket() {
    await invalidateMarketQueries(queryClient);
  }

  function reportSuccess(text: string) {
    setFeedback({ tone: "success", text });
  }

  function reportError(error: unknown) {
    setFeedback({ tone: "error", text: readableMarketError(error) });
  }

  if (workspace.isLoading) {
    return <MarketShell loadingMessage="Carregando mercado e saldo..." />;
  }
  if (workspace.error) {
    return <MarketShell errorMessage={readableMarketError(workspace.error)} />;
  }
  if (!workspace.data?.club) {
    return (
      <MarketShell>
        <EmptyState text="Crie um clube antes de usar o mercado e o treino." />
        <Link to="/criar-clube" className="mt-4 inline-flex min-h-11 items-center underline">
          Criar clube
        </Link>
      </MarketShell>
    );
  }

  const { club, roster, systemMarket } = workspace.data;

  return (
    <MarketShell>
      <header className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <p className="text-sm text-slate-400">
            {club.name} ({club.abbreviation})
          </p>
          <h1 className="mt-1 text-2xl font-bold">Mercado e treino</h1>
        </div>
        <div className="rounded-md border border-slate-700 px-4 py-3 text-right">
          <p className="text-xs uppercase tracking-wide text-slate-400">Saldo atual</p>
          <p className="mt-1 text-lg font-semibold tabular-nums">
            {formatMarketPrice(club.balance_cents)}
          </p>
        </div>
      </header>

      <div className="mt-6 overflow-x-auto" role="tablist" aria-label="Áreas do mercado">
        <div className="flex min-w-max gap-2 border-b border-slate-800 pb-2">
          {(
            [
              ["system", "Sistema"],
              ["roster", "Meu elenco"],
              ["p2p", "P2P"],
              ["offers", "Ofertas"],
            ] as const
          ).map(([value, label]) => (
            <button
              key={value}
              type="button"
              role="tab"
              aria-selected={tab === value}
              onClick={() => setTab(value)}
              className={`min-h-11 rounded-md px-4 py-2 text-sm font-medium focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-slate-100 ${
                tab === value
                  ? "bg-slate-100 text-slate-950"
                  : "border border-slate-700 text-slate-200"
              }`}
            >
              {label}
            </button>
          ))}
        </div>
      </div>

      {feedback && (
        <p
          aria-live="polite"
          className={`mt-4 rounded-md border p-3 text-sm ${
            feedback.tone === "success"
              ? "border-emerald-800 bg-emerald-950/30 text-emerald-200"
              : "border-red-800 bg-red-950/30 text-red-200"
          }`}
        >
          {feedback.text}
        </p>
      )}

      <section className="mt-6" role="tabpanel">
        {tab === "system" && (
          <SystemTab
            cards={systemMarket}
            rosterSize={roster.length}
            balanceCents={club.balance_cents}
            filters={filters}
            setFilters={setFilters}
            refreshMarket={refreshMarket}
            reportSuccess={reportSuccess}
            reportError={reportError}
          />
        )}
        {tab === "roster" && (
          <RosterTab
            cards={roster}
            balanceCents={club.balance_cents}
            refreshMarket={refreshMarket}
            reportSuccess={reportSuccess}
            reportError={reportError}
          />
        )}
        {tab === "p2p" && (
          <P2PTab
            listings={listings.data ?? []}
            isLoading={listings.isLoading}
            error={listings.error}
            roster={roster}
            rosterSize={roster.length}
            balanceCents={club.balance_cents}
            filters={filters}
            setFilters={setFilters}
            refreshMarket={refreshMarket}
            reportSuccess={reportSuccess}
            reportError={reportError}
          />
        )}
        {tab === "offers" && (
          <OffersTab
            offers={offers.data ?? []}
            offersLoading={offers.isLoading}
            offersError={offers.error}
            targets={targets.data ?? []}
            targetsLoading={targets.isLoading}
            roster={roster}
            balanceCents={club.balance_cents}
            refreshMarket={refreshMarket}
            reportSuccess={reportSuccess}
            reportError={reportError}
          />
        )}
      </section>
    </MarketShell>
  );
}

function SystemTab(props: {
  cards: SystemMarketCard[];
  rosterSize: number;
  balanceCents: number;
  filters: MarketFilters;
  setFilters: (filters: MarketFilters) => void;
  refreshMarket: () => Promise<void>;
  reportSuccess: (text: string) => void;
  reportError: (error: unknown) => void;
}) {
  const buyFn = useServerFn(buyPlayerFromSystem);
  const [selected, setSelected] = useState<SystemMarketCard | null>(null);
  const visibleCards = useMemo(
    () => filterAndSortMarketCards(props.cards, props.filters),
    [props.cards, props.filters],
  );
  const mutation = useMutation({
    mutationFn: (card: SystemMarketCard) => buyFn({ data: { clubPlayerId: card.clubPlayerId } }),
    onSuccess: async () => {
      setSelected(null);
      props.reportSuccess("Carta comprada do sistema com sucesso.");
      await props.refreshMarket();
    },
    onError: props.reportError,
  });

  return (
    <div>
      <SectionHeading
        title="Estoque do sistema"
        description="Compra por 100% do valor de referência."
      />
      <MarketFilterPanel filters={props.filters} setFilters={props.setFilters} />
      {props.cards.length === 0 ? (
        <EmptyState text="Nenhuma carta disponível no sistema." />
      ) : visibleCards.length === 0 ? (
        <EmptyState text="Nenhuma carta atende aos filtros escolhidos." />
      ) : (
        <div className="mt-4 grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {visibleCards.map((card) => {
            const reason = !card.isAvailable
              ? "Carta indisponível"
              : props.rosterSize >= 15
                ? "Elenco com 15 cartas"
                : props.balanceCents < card.priceCents
                  ? "Saldo insuficiente"
                  : null;
            return (
              <PlayerMarketCard key={card.clubPlayerId} card={card} priceLabel="Preço de compra">
                <button
                  type="button"
                  disabled={Boolean(reason) || mutation.isPending}
                  onClick={() => setSelected(card)}
                  className={primaryButtonClass}
                >
                  {mutation.isPending ? "Comprando..." : (reason ?? "Comprar")}
                </button>
              </PlayerMarketCard>
            );
          })}
        </div>
      )}

      <ConfirmDialog
        open={selected !== null}
        title="Confirmar compra do sistema"
        description={
          selected
            ? `${selected.name}: ${formatMarketPrice(selected.priceCents)}. Saldo atual ${formatMarketPrice(
                props.balanceCents,
              )}; após a compra ${formatMarketPrice(
                projectBalanceAfter(props.balanceCents, selected.priceCents),
              )}.`
            : ""
        }
        pending={mutation.isPending}
        confirmLabel="Confirmar compra"
        onCancel={() => setSelected(null)}
        onConfirm={() => selected && mutation.mutate(selected)}
      />
    </div>
  );
}

function RosterTab(props: {
  cards: RosterMarketCard[];
  balanceCents: number;
  refreshMarket: () => Promise<void>;
  reportSuccess: (text: string) => void;
  reportError: (error: unknown) => void;
}) {
  const sellFn = useServerFn(sellPlayerToSystem);
  const trainFn = useServerFn(trainClubPlayer);
  const [sale, setSale] = useState<RosterMarketCard | null>(null);
  const [training, setTraining] = useState<{
    card: RosterMarketCard;
    attribute: PlayerAttributeKey;
  } | null>(null);
  const [attributes, setAttributes] = useState<Record<string, PlayerAttributeKey>>({});
  const sellMutation = useMutation({
    mutationFn: (card: RosterMarketCard) => sellFn({ data: { clubPlayerId: card.clubPlayerId } }),
    onSuccess: async () => {
      setSale(null);
      props.reportSuccess("Carta vendida ao sistema com sucesso.");
      await props.refreshMarket();
    },
    onError: props.reportError,
  });
  const trainMutation = useMutation({
    mutationFn: ({ card, attribute }: { card: RosterMarketCard; attribute: PlayerAttributeKey }) =>
      trainFn({ data: { clubPlayerId: card.clubPlayerId, attribute } }),
    onSuccess: async () => {
      setTraining(null);
      props.reportSuccess("Treino concluído e progresso atualizado.");
      await props.refreshMarket();
    },
    onError: props.reportError,
  });

  if (props.cards.length === 0) return <EmptyState text="Seu elenco ainda está vazio." />;

  return (
    <div>
      <SectionHeading
        title="Meu elenco"
        description="Venda ao sistema por 50% do valor de referência ou use o treino diário."
      />
      <div className="mt-4 grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        {props.cards.map((card) => {
          const attribute = attributes[card.clubPlayerId] ?? firstValidAttribute(card);
          const progress =
            card.attributeProgress.find((item) => item.attribute === attribute)?.progress ?? 0;
          const currentValue = card.attributes[attribute];
          const saleReason =
            props.cards.length <= 5
              ? "Mínimo de 5 cartas"
              : card.isReserved
                ? "Carta reservada"
                : null;
          return (
            <PlayerMarketCard
              key={card.clubPlayerId}
              card={card}
              priceLabel="Venda ao sistema"
              reserved={card.isReserved}
            >
              <div className="space-y-3 border-t border-slate-800 pt-3">
                <label className="block text-sm">
                  <span className="text-slate-300">Atributo para treino</span>
                  <select
                    value={attribute}
                    disabled={card.isReserved || trainMutation.isPending}
                    onChange={(event) =>
                      setAttributes((current) => ({
                        ...current,
                        [card.clubPlayerId]: event.target.value as PlayerAttributeKey,
                      }))
                    }
                    className={inputClass}
                  >
                    {validAttributes(card).map((key) => (
                      <option key={key} value={key}>
                        {attributeLabel(key)}
                      </option>
                    ))}
                  </select>
                </label>
                <p className="text-xs text-slate-400">
                  Atual: {currentValue}. Progresso: {progress}/3. Possível evolução: {currentValue}
                  {progress === 2 && currentValue < 99
                    ? ` → ${currentValue + 1}`
                    : " (ainda acumula progresso)"}
                  . Custo: {formatMarketPrice(card.trainingCostCents)}.
                </p>
                <div className="text-xs text-slate-400">
                  <p className="font-medium text-slate-300">Progresso por atributo</p>
                  <ul className="mt-1 grid grid-cols-2 gap-x-3 gap-y-1">
                    {validAttributes(card).map((key) => (
                      <li key={key} className="flex justify-between gap-2">
                        <span>{attributeLabel(key)}</span>
                        <span className="tabular-nums">
                          {card.attributeProgress.find((item) => item.attribute === key)
                            ?.progress ?? 0}
                          /3
                        </span>
                      </li>
                    ))}
                  </ul>
                </div>
                <div className="grid gap-2 sm:grid-cols-2">
                  <button
                    type="button"
                    disabled={
                      Boolean(saleReason) || sellMutation.isPending || trainMutation.isPending
                    }
                    onClick={() => setSale(card)}
                    className={secondaryButtonClass}
                  >
                    {saleReason ?? "Vender ao sistema"}
                  </button>
                  <button
                    type="button"
                    disabled={card.isReserved || trainMutation.isPending || sellMutation.isPending}
                    onClick={() => setTraining({ card, attribute })}
                    className={primaryButtonClass}
                  >
                    {trainMutation.isPending
                      ? "Treinando..."
                      : card.isReserved
                        ? "Reservada"
                        : "Treinar"}
                  </button>
                </div>
              </div>
            </PlayerMarketCard>
          );
        })}
      </div>

      <ConfirmDialog
        open={sale !== null}
        title="Confirmar venda ao sistema"
        description={
          sale
            ? `Você receberá ${formatMarketPrice(sale.systemSalePriceCents)}. Saldo após a venda: ${formatMarketPrice(
                props.balanceCents + sale.systemSalePriceCents,
              )}. Esta carta sairá do seu elenco.`
            : ""
        }
        pending={sellMutation.isPending}
        confirmLabel="Confirmar venda"
        onCancel={() => setSale(null)}
        onConfirm={() => sale && sellMutation.mutate(sale)}
      />
      <ConfirmDialog
        open={training !== null}
        title="Confirmar treino"
        description={
          training
            ? `${training.card.name}: ${attributeLabel(training.attribute)} por ${formatMarketPrice(
                training.card.trainingCostCents,
              )}. Saldo após o treino: ${formatMarketPrice(
                projectBalanceAfter(props.balanceCents, training.card.trainingCostCents),
              )}.`
            : ""
        }
        pending={trainMutation.isPending}
        confirmLabel="Confirmar treino"
        onCancel={() => setTraining(null)}
        onConfirm={() => training && trainMutation.mutate(training)}
      />
    </div>
  );
}

function P2PTab(props: {
  listings: P2PMarketListing[];
  isLoading: boolean;
  error: unknown;
  roster: RosterMarketCard[];
  rosterSize: number;
  balanceCents: number;
  filters: MarketFilters;
  setFilters: (filters: MarketFilters) => void;
  refreshMarket: () => Promise<void>;
  reportSuccess: (text: string) => void;
  reportError: (error: unknown) => void;
}) {
  const createFn = useServerFn(createMarketListing);
  const cancelFn = useServerFn(cancelMarketListing);
  const buyFn = useServerFn(buyMarketListing);
  const [listingCardId, setListingCardId] = useState("");
  const [listingPrice, setListingPrice] = useState("");
  const [action, setAction] = useState<{
    type: "buy" | "cancel";
    listing: P2PMarketListing;
  } | null>(null);
  const visibleListings = useMemo(
    () => filterAndSortMarketCards(props.listings, props.filters),
    [props.listings, props.filters],
  );
  const eligibleCards = props.roster.filter((card) => !card.isReserved);
  const listingValidation = createListingInputSchema.safeParse({
    clubPlayerId: listingCardId,
    priceCents: Number(listingPrice),
  });

  const createMutation = useMutation({
    mutationFn: () => {
      if (!listingValidation.success) throw new Error("invalid_price");
      return createFn({ data: listingValidation.data });
    },
    onSuccess: async () => {
      setListingCardId("");
      setListingPrice("");
      props.reportSuccess("Anúncio criado e carta reservada.");
      await props.refreshMarket();
    },
    onError: props.reportError,
  });
  const actionMutation = useMutation({
    mutationFn: async (selected: { type: "buy" | "cancel"; listing: P2PMarketListing }) => {
      if (selected.type === "cancel") {
        return cancelFn({ data: { listingId: selected.listing.listingId } });
      }
      return buyFn({ data: { listingId: selected.listing.listingId } });
    },
    onSuccess: async (_result, selected) => {
      setAction(null);
      props.reportSuccess(
        selected.type === "buy" ? "Compra P2P concluída." : "Anúncio cancelado e carta liberada.",
      );
      await props.refreshMarket();
    },
    onError: props.reportError,
  });

  return (
    <div>
      <SectionHeading
        title="Mercado P2P"
        description="Anúncios entre clubes com transferência atômica da carta e do saldo."
      />

      <form
        className="mt-4 rounded-md border border-slate-800 p-4"
        onSubmit={(event) => {
          event.preventDefault();
          if (
            canSubmitMarketAction({
              isPending: createMutation.isPending,
              isValid: listingValidation.success,
            })
          ) {
            createMutation.mutate();
          }
        }}
      >
        <h3 className="font-semibold">Criar anúncio</h3>
        <div className="mt-3 grid gap-3 md:grid-cols-[minmax(0,1fr)_180px_auto] md:items-end">
          <label className="text-sm">
            <span className="text-slate-300">Carta elegível</span>
            <select
              value={listingCardId}
              onChange={(event) => setListingCardId(event.target.value)}
              className={inputClass}
            >
              <option value="">Selecionar carta</option>
              {eligibleCards.map((card) => (
                <option key={card.clubPlayerId} value={card.clubPlayerId}>
                  {card.name} · {card.position} · OVR {card.overall}
                </option>
              ))}
            </select>
          </label>
          <label className="text-sm">
            <span className="text-slate-300">Preço em centavos</span>
            <input
              type="number"
              min={1}
              max={10_000}
              value={listingPrice}
              onChange={(event) => setListingPrice(event.target.value)}
              className={inputClass}
            />
          </label>
          <button
            type="submit"
            disabled={
              props.rosterSize <= 5 ||
              !listingValidation.success ||
              createMutation.isPending ||
              eligibleCards.length === 0
            }
            className={primaryButtonClass}
          >
            {createMutation.isPending ? "Criando..." : "Confirmar anúncio"}
          </button>
        </div>
        <p className="mt-2 text-xs text-slate-400">
          Preço permitido: 1 a 10.000 cents. A carta ficará reservada enquanto o anúncio estiver
          aberto.
        </p>
        {props.rosterSize <= 5 && (
          <p className="mt-2 text-sm text-amber-300">
            Seu elenco precisa ficar com pelo menos 5 cartas.
          </p>
        )}
      </form>

      <MarketFilterPanel filters={props.filters} setFilters={props.setFilters} />
      {props.isLoading ? (
        <LoadingState text="Carregando anúncios P2P..." />
      ) : props.error ? (
        <ErrorState text={readableMarketError(props.error)} />
      ) : props.listings.length === 0 ? (
        <EmptyState text="Nenhum anúncio P2P aberto." />
      ) : visibleListings.length === 0 ? (
        <EmptyState text="Nenhum anúncio atende aos filtros." />
      ) : (
        <div className="mt-4 grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {visibleListings.map((listing) => {
            const buyReason = listing.isMine
              ? null
              : props.rosterSize >= 15
                ? "Elenco com 15 cartas"
                : props.balanceCents < listing.priceCents
                  ? "Saldo insuficiente"
                  : null;
            return (
              <PlayerMarketCard
                key={listing.listingId}
                card={listing}
                priceLabel="Preço P2P"
                badge={listing.isMine ? "Meu anúncio" : undefined}
              >
                <p className="text-sm text-slate-400">
                  Vendedor: {listing.sellerName} ({listing.sellerAbbreviation})
                </p>
                <button
                  type="button"
                  disabled={Boolean(buyReason) || actionMutation.isPending}
                  onClick={() => setAction({ type: listing.isMine ? "cancel" : "buy", listing })}
                  className={listing.isMine ? secondaryButtonClass : primaryButtonClass}
                >
                  {actionMutation.isPending
                    ? "Processando..."
                    : listing.isMine
                      ? "Cancelar anúncio"
                      : (buyReason ?? "Comprar")}
                </button>
              </PlayerMarketCard>
            );
          })}
        </div>
      )}

      <ConfirmDialog
        open={action !== null}
        title={action?.type === "buy" ? "Confirmar compra P2P" : "Cancelar anúncio"}
        description={
          action?.type === "buy"
            ? `${action.listing.name}: ${formatMarketPrice(action.listing.priceCents)}. Saldo após a compra: ${formatMarketPrice(
                projectBalanceAfter(props.balanceCents, action.listing.priceCents),
              )}.`
            : action
              ? `Cancelar o anúncio de ${action.listing.name}? A carta será liberada.`
              : ""
        }
        pending={actionMutation.isPending}
        confirmLabel={action?.type === "buy" ? "Confirmar compra" : "Cancelar anúncio"}
        onCancel={() => setAction(null)}
        onConfirm={() => action && actionMutation.mutate(action)}
      />
    </div>
  );
}

function OffersTab(props: {
  offers: TransferOfferSummary[];
  offersLoading: boolean;
  offersError: unknown;
  targets: TradeTarget[];
  targetsLoading: boolean;
  roster: RosterMarketCard[];
  balanceCents: number;
  refreshMarket: () => Promise<void>;
  reportSuccess: (text: string) => void;
  reportError: (error: unknown) => void;
}) {
  const acceptFn = useServerFn(acceptTransferOffer);
  const rejectFn = useServerFn(rejectTransferOffer);
  const cancelFn = useServerFn(cancelTransferOffer);
  const [tab, setTab] = useState<OfferTab>("incoming");
  const [action, setAction] = useState<{
    type: "accept" | "reject" | "cancel";
    offer: TransferOfferSummary;
  } | null>(null);
  const actionMutation = useMutation({
    mutationFn: async (selected: NonNullable<typeof action>) => {
      if (selected.type === "accept")
        return acceptFn({ data: { offerId: selected.offer.offerId } });
      if (selected.type === "reject")
        return rejectFn({ data: { offerId: selected.offer.offerId } });
      return cancelFn({ data: { offerId: selected.offer.offerId } });
    },
    onSuccess: async (_result, selected) => {
      setAction(null);
      props.reportSuccess(
        selected.type === "accept"
          ? "Oferta aceita e troca concluída."
          : selected.type === "reject"
            ? "Oferta rejeitada e cartas liberadas."
            : "Oferta cancelada e cartas liberadas.",
      );
      await props.refreshMarket();
    },
    onError: props.reportError,
  });
  const visible = props.offers.filter((offer) =>
    tab === "incoming" ? offer.direction === "incoming" : offer.direction === "outgoing",
  );

  return (
    <div>
      <SectionHeading
        title="Ofertas de troca"
        description="Cartas e dinheiro são transferidos juntos ou nada muda."
      />
      <div className="mt-4 flex flex-wrap gap-2" role="tablist" aria-label="Tipos de oferta">
        {(
          [
            ["incoming", "Recebidas"],
            ["outgoing", "Enviadas"],
            ["create", "Criar oferta"],
          ] as const
        ).map(([value, label]) => (
          <button
            key={value}
            type="button"
            role="tab"
            aria-selected={tab === value}
            onClick={() => setTab(value)}
            className={tab === value ? primaryButtonClass : secondaryButtonClass}
          >
            {label}
          </button>
        ))}
      </div>

      {tab === "create" ? (
        <CreateOfferForm
          targets={props.targets}
          targetsLoading={props.targetsLoading}
          roster={props.roster}
          balanceCents={props.balanceCents}
          refreshMarket={props.refreshMarket}
          reportSuccess={props.reportSuccess}
          reportError={props.reportError}
        />
      ) : props.offersLoading ? (
        <LoadingState text="Carregando ofertas..." />
      ) : props.offersError ? (
        <ErrorState text={readableMarketError(props.offersError)} />
      ) : visible.length === 0 ? (
        <EmptyState
          text={tab === "incoming" ? "Nenhuma oferta recebida." : "Nenhuma oferta enviada."}
        />
      ) : (
        <div className="mt-4 space-y-4">
          {visible.map((offer) => (
            <OfferCard
              key={offer.offerId}
              offer={offer}
              pending={actionMutation.isPending}
              onAction={(type) => setAction({ type, offer })}
            />
          ))}
        </div>
      )}

      <ConfirmDialog
        open={action !== null}
        title={
          action?.type === "accept"
            ? "Aceitar oferta"
            : action?.type === "reject"
              ? "Rejeitar oferta"
              : "Cancelar oferta"
        }
        description={
          action
            ? `${action.offer.fromClub.name} → ${action.offer.toClub.name}. Dinheiro: ${formatMarketPrice(
                action.offer.cashCents,
              )}. A operação é atômica.`
            : ""
        }
        pending={actionMutation.isPending}
        confirmLabel="Confirmar"
        onCancel={() => setAction(null)}
        onConfirm={() => action && actionMutation.mutate(action)}
      />
    </div>
  );
}

function CreateOfferForm(props: {
  targets: TradeTarget[];
  targetsLoading: boolean;
  roster: RosterMarketCard[];
  balanceCents: number;
  refreshMarket: () => Promise<void>;
  reportSuccess: (text: string) => void;
  reportError: (error: unknown) => void;
}) {
  const targetRosterFn = useServerFn(getTradeTargetRoster);
  const createFn = useServerFn(createTransferOffer);
  const [targetId, setTargetId] = useState("");
  const [ownCards, setOwnCards] = useState<string[]>([]);
  const [targetCards, setTargetCards] = useState<string[]>([]);
  const [cash, setCash] = useState("0");
  const expiresAt = useMemo(() => new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(), []);
  const selectedTarget = props.targets.find((target) => target.clubId === targetId) ?? null;
  const targetRoster = useQuery({
    queryKey: ["tradeTargets", targetId],
    queryFn: () => targetRosterFn({ data: { clubId: targetId } }),
    enabled: Boolean(targetId),
  });
  const input = {
    toClubId: targetId,
    fromClubPlayerIds: ownCards,
    toClubPlayerIds: targetCards,
    cashCents: Number(cash),
    expiresAt,
  };
  const validation = createTransferOfferInputSchema.safeParse(input);
  const projection = selectedTarget
    ? projectTradeRosters({
        fromRosterSize: props.roster.length,
        toRosterSize: selectedTarget.rosterSize,
        fromCards: ownCards.length,
        toCards: targetCards.length,
      })
    : null;
  const projectedBalance = projectBalanceAfter(props.balanceCents, Number(cash) || 0);
  const eligibleOwnCards = props.roster.filter((card) => !card.isReserved);
  const mutation = useMutation({
    mutationFn: () => {
      if (!validation.success || !projection?.isValid || projectedBalance < 0) {
        throw new Error("invalid_cash");
      }
      return createFn({ data: validation.data });
    },
    onSuccess: async () => {
      setTargetId("");
      setOwnCards([]);
      setTargetCards([]);
      setCash("0");
      props.reportSuccess("Oferta criada e todas as cartas foram reservadas.");
      await props.refreshMarket();
    },
    onError: props.reportError,
  });
  const canSubmit =
    validation.success &&
    Boolean(projection?.isValid) &&
    projectedBalance >= 0 &&
    !targetRoster.isLoading;

  return (
    <form
      className="mt-4 space-y-5 rounded-md border border-slate-800 p-4"
      onSubmit={(event) => {
        event.preventDefault();
        if (canSubmitMarketAction({ isPending: mutation.isPending, isValid: canSubmit })) {
          mutation.mutate();
        }
      }}
    >
      <label className="block text-sm">
        <span className="text-slate-300">Clube destinatário</span>
        <select
          value={targetId}
          disabled={props.targetsLoading || mutation.isPending}
          onChange={(event) => {
            setTargetId(event.target.value);
            setTargetCards([]);
          }}
          className={inputClass}
        >
          <option value="">Selecionar clube</option>
          {props.targets.map((target) => (
            <option key={target.clubId} value={target.clubId}>
              {target.name} ({target.abbreviation}) · {target.rosterSize} cartas
            </option>
          ))}
        </select>
      </label>

      <div className="grid gap-5 lg:grid-cols-2">
        <CardSelection
          title="Cartas que você oferece"
          cards={eligibleOwnCards}
          selected={ownCards}
          onToggle={(cardId) => setOwnCards(toggleCard(ownCards, cardId))}
        />
        <CardSelection
          title="Cartas solicitadas"
          cards={targetRoster.data ?? []}
          selected={targetCards}
          loading={targetRoster.isLoading}
          error={targetRoster.error}
          onToggle={(cardId) => setTargetCards(toggleCard(targetCards, cardId))}
        />
      </div>

      <label className="block max-w-xs text-sm">
        <span className="text-slate-300">Dinheiro pago ao destinatário (cents)</span>
        <input
          type="number"
          min={0}
          max={10_000}
          value={cash}
          onChange={(event) => setCash(event.target.value)}
          className={inputClass}
        />
      </label>

      <div className="grid gap-3 rounded-md border border-slate-900 p-3 text-sm sm:grid-cols-3">
        <Info
          label="Seu elenco após"
          value={projection ? String(projection.fromRosterSize) : "-"}
        />
        <Info
          label="Elenco destinatário"
          value={projection ? String(projection.toRosterSize) : "-"}
        />
        <Info label="Seu saldo após" value={formatMarketPrice(projectedBalance)} />
      </div>
      {projection && !projection.isValid && (
        <p className="text-sm text-amber-300">
          A projeção precisa manter os dois elencos entre 5 e 15 cartas.
        </p>
      )}
      {projectedBalance < 0 && (
        <p className="text-sm text-amber-300">Saldo insuficiente para esta oferta.</p>
      )}
      <p className="text-xs text-slate-400">
        A oferta expira em 24 horas. Máximo de 5 cartas de cada lado.
      </p>
      <button
        type="submit"
        disabled={!canSubmit || mutation.isPending}
        className={primaryButtonClass}
      >
        {mutation.isPending ? "Criando oferta..." : "Confirmar oferta"}
      </button>
    </form>
  );
}

function CardSelection(props: {
  title: string;
  cards: Array<RosterMarketCard | TransferOfferCard>;
  selected: string[];
  loading?: boolean;
  error?: unknown;
  onToggle: (cardId: string) => void;
}) {
  return (
    <fieldset className="rounded-md border border-slate-900 p-3">
      <legend className="px-1 text-sm font-semibold">
        {props.title} ({props.selected.length}/5)
      </legend>
      {props.loading ? (
        <p className="text-sm text-slate-400">Carregando cartas...</p>
      ) : props.error ? (
        <p className="text-sm text-red-300">{readableMarketError(props.error)}</p>
      ) : props.cards.length === 0 ? (
        <p className="text-sm text-slate-400">Nenhuma carta elegível.</p>
      ) : (
        <div className="mt-2 max-h-72 space-y-2 overflow-y-auto pr-1">
          {props.cards.map((card) => {
            const checked = props.selected.includes(card.clubPlayerId);
            const disabled = !checked && props.selected.length >= 5;
            return (
              <label
                key={card.clubPlayerId}
                className="flex min-h-11 cursor-pointer items-center gap-3 rounded-md border border-slate-800 p-2 text-sm"
              >
                <input
                  type="checkbox"
                  checked={checked}
                  disabled={disabled}
                  onChange={() => props.onToggle(card.clubPlayerId)}
                />
                <span>
                  {card.name} · {card.position} · OVR {card.overall}
                </span>
              </label>
            );
          })}
        </div>
      )}
    </fieldset>
  );
}

function OfferCard(props: {
  offer: TransferOfferSummary;
  pending: boolean;
  onAction: (type: "accept" | "reject" | "cancel") => void;
}) {
  const offer = props.offer;
  return (
    <article className="rounded-md border border-slate-800 p-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="font-semibold">
            {offer.fromClub.name} → {offer.toClub.name}
          </p>
          <p className="mt-1 text-sm text-slate-400">
            Status: {offerStatusLabel(offer.status)} · Dinheiro:{" "}
            {formatMarketPrice(offer.cashCents)}
          </p>
          <p className="text-xs text-slate-500">Expira: {formatDateTime(offer.expiresAt)}</p>
        </div>
        <span className="rounded-md border border-slate-700 px-2 py-1 text-xs">
          {offer.direction === "incoming" ? "Recebida" : "Enviada"}
        </span>
      </div>
      <div className="mt-4 grid gap-4 md:grid-cols-2">
        <OfferCardList title="Cartas oferecidas" cards={offer.fromCards} />
        <OfferCardList title="Cartas solicitadas" cards={offer.toCards} />
      </div>
      <div className="mt-4 flex flex-wrap gap-2">
        {offer.canAccept && (
          <button
            type="button"
            disabled={props.pending}
            onClick={() => props.onAction("accept")}
            className={primaryButtonClass}
          >
            Aceitar
          </button>
        )}
        {offer.canReject && (
          <button
            type="button"
            disabled={props.pending}
            onClick={() => props.onAction("reject")}
            className={secondaryButtonClass}
          >
            Rejeitar
          </button>
        )}
        {offer.canCancel && (
          <button
            type="button"
            disabled={props.pending}
            onClick={() => props.onAction("cancel")}
            className={secondaryButtonClass}
          >
            Cancelar
          </button>
        )}
      </div>
    </article>
  );
}

function OfferCardList({ title, cards }: { title: string; cards: TransferOfferCard[] }) {
  return (
    <div>
      <h4 className="text-sm font-medium text-slate-300">{title}</h4>
      {cards.length === 0 ? (
        <p className="mt-1 text-sm text-slate-500">Nenhuma carta.</p>
      ) : (
        <ul className="mt-2 space-y-2 text-sm">
          {cards.map((card) => (
            <li key={card.clubPlayerId} className="rounded-md border border-slate-900 p-2">
              {card.name} · {card.position} · {rarityLabel(card.rarity)} · OVR {card.overall}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function MarketFilterPanel(props: {
  filters: MarketFilters;
  setFilters: (filters: MarketFilters) => void;
}) {
  const update = <Key extends keyof MarketFilters>(key: Key, value: MarketFilters[Key]) =>
    props.setFilters({ ...props.filters, [key]: value });
  return (
    <div className="mt-4 grid gap-3 rounded-md border border-slate-800 p-4 sm:grid-cols-2 lg:grid-cols-4">
      <label className="text-sm sm:col-span-2">
        <span className="text-slate-300">Buscar por nome</span>
        <input
          type="search"
          value={props.filters.search}
          onChange={(event) => update("search", event.target.value)}
          className={inputClass}
        />
      </label>
      <FilterSelect
        label="Posição"
        value={props.filters.position ?? ""}
        onChange={(value) =>
          update("position", value ? (value as MarketFilters["position"]) : null)
        }
        options={[
          ["GK", "Goleiro"],
          ["DEF", "Defensor"],
          ["MID", "Meio-campo"],
          ["ATA", "Atacante"],
        ]}
      />
      <FilterSelect
        label="Raridade"
        value={props.filters.rarity ?? ""}
        onChange={(value) => update("rarity", value ? (value as MarketFilters["rarity"]) : null)}
        options={[
          ["peba", "Peba"],
          ["paia", "Paia"],
          ["pika", "Pika"],
        ]}
      />
      <FilterSelect
        label="Setor"
        value={props.filters.sector ?? ""}
        onChange={(value) => update("sector", value ? (value as MarketFilters["sector"]) : null)}
        options={PLAYER_SECTORS.map((sector) => [sector, sectorLabel(sector)])}
      />
      <label className="text-sm">
        <span className="text-slate-300">OVR mínimo</span>
        <input
          type="number"
          min={1}
          max={99}
          value={props.filters.minOverall ?? ""}
          onChange={(event) => update("minOverall", nullableNumber(event.target.value))}
          className={inputClass}
        />
      </label>
      <label className="text-sm">
        <span className="text-slate-300">OVR máximo</span>
        <input
          type="number"
          min={1}
          max={99}
          value={props.filters.maxOverall ?? ""}
          onChange={(event) => update("maxOverall", nullableNumber(event.target.value))}
          className={inputClass}
        />
      </label>
      <FilterSelect
        label="Ordenar por"
        value={props.filters.sortBy}
        onChange={(value) => update("sortBy", value as MarketFilters["sortBy"])}
        options={[
          ["name", "Nome"],
          ["overall", "Overall"],
          ["price", "Preço"],
        ]}
      />
      <FilterSelect
        label="Direção"
        value={props.filters.sortDirection}
        onChange={(value) => update("sortDirection", value as MarketFilters["sortDirection"])}
        options={[
          ["asc", "Crescente"],
          ["desc", "Decrescente"],
        ]}
      />
    </div>
  );
}

function FilterSelect(props: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  options: ReadonlyArray<readonly [string, string]>;
}) {
  return (
    <label className="text-sm">
      <span className="text-slate-300">{props.label}</span>
      <select
        value={props.value}
        onChange={(event) => props.onChange(event.target.value)}
        className={inputClass}
      >
        <option value="">Todos</option>
        {props.options.map(([value, label]) => (
          <option key={value} value={value}>
            {label}
          </option>
        ))}
      </select>
    </label>
  );
}

function PlayerMarketCard(props: {
  card: MarketCardSummary;
  priceLabel: string;
  reserved?: boolean;
  badge?: string;
  children: React.ReactNode;
}) {
  return (
    <article className="flex flex-col rounded-md border border-slate-800 p-4">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h3 className="font-semibold">{props.card.name}</h3>
          <p className="mt-1 text-sm text-slate-400">
            {positionLabel(props.card.position)} · {rarityLabel(props.card.rarity)} ·{" "}
            {sectorLabel(props.card.sector)}
          </p>
        </div>
        <span className="rounded-md border border-slate-700 px-2 py-1 text-sm tabular-nums">
          OVR {props.card.overall}
        </span>
      </div>
      {(props.reserved || props.badge) && (
        <p className="mt-3 text-xs font-medium text-amber-300">
          {props.badge ?? "Carta reservada"}
        </p>
      )}
      <AttributeGrid attributes={props.card.attributes} />
      <dl className="mt-4 space-y-1 border-t border-slate-800 pt-3 text-sm">
        <div className="flex justify-between gap-3 text-slate-400">
          <dt>Valor de referência</dt>
          <dd className="tabular-nums">{formatMarketPrice(props.card.referenceValueCents)}</dd>
        </div>
        <div className="flex justify-between gap-3 font-medium">
          <dt>{props.priceLabel}</dt>
          <dd className="tabular-nums">{formatMarketPrice(props.card.priceCents)}</dd>
        </div>
      </dl>
      <div className="mt-4 flex flex-1 flex-col justify-end gap-3">{props.children}</div>
    </article>
  );
}

function AttributeGrid({ attributes }: { attributes: PlayerAttributes }) {
  return (
    <dl className="mt-4 grid grid-cols-2 gap-x-4 gap-y-1 text-xs text-slate-400">
      {PLAYER_ATTRIBUTE_KEYS.map((key) => (
        <div key={key} className="flex justify-between gap-2">
          <dt>{attributeLabel(key)}</dt>
          <dd className="tabular-nums">{attributes[key]}</dd>
        </div>
      ))}
    </dl>
  );
}

function ConfirmDialog(props: {
  open: boolean;
  title: string;
  description: string;
  pending: boolean;
  confirmLabel: string;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  return (
    <AlertDialog
      open={props.open}
      onOpenChange={(open) => !open && !props.pending && props.onCancel()}
    >
      <AlertDialogContent className="border-slate-700 bg-slate-950 text-slate-100">
        <AlertDialogHeader>
          <AlertDialogTitle>{props.title}</AlertDialogTitle>
          <AlertDialogDescription className="text-slate-400">
            {props.description}
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel disabled={props.pending}>Voltar</AlertDialogCancel>
          <AlertDialogAction disabled={props.pending} onClick={props.onConfirm}>
            {props.pending ? "Processando..." : props.confirmLabel}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}

function MarketShell(props: {
  children?: React.ReactNode;
  loadingMessage?: string;
  errorMessage?: string;
}) {
  return (
    <main className="min-h-screen bg-[#0b0f14] px-4 py-8 text-slate-100 sm:px-6">
      <div className="mx-auto max-w-7xl">
        <Link to="/app" className="inline-flex min-h-11 items-center text-sm underline">
          Voltar ao app
        </Link>
        {props.loadingMessage ? (
          <LoadingState text={props.loadingMessage} />
        ) : props.errorMessage ? (
          <ErrorState text={props.errorMessage} />
        ) : (
          <div className="mt-2">{props.children}</div>
        )}
      </div>
    </main>
  );
}

function SectionHeading({ title, description }: { title: string; description: string }) {
  return (
    <div>
      <h2 className="text-lg font-semibold">{title}</h2>
      <p className="mt-1 text-sm text-slate-400">{description}</p>
    </div>
  );
}

function LoadingState({ text }: { text: string }) {
  return (
    <p className="mt-6 animate-pulse rounded-md border border-slate-800 p-4 text-sm text-slate-400">
      {text}
    </p>
  );
}

function EmptyState({ text }: { text: string }) {
  return (
    <p className="mt-6 rounded-md border border-slate-800 p-4 text-sm text-slate-400">{text}</p>
  );
}

function ErrorState({ text }: { text: string }) {
  return (
    <p role="alert" className="mt-6 rounded-md border border-red-800 p-4 text-sm text-red-300">
      {text}
    </p>
  );
}

function Info({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="text-xs uppercase text-slate-500">{label}</p>
      <p className="mt-1 font-medium tabular-nums">{value}</p>
    </div>
  );
}

function toggleCard(current: string[], cardId: string): string[] {
  if (current.includes(cardId)) return current.filter((id) => id !== cardId);
  if (current.length >= 5) return current;
  return [...current, cardId];
}

function validAttributes(card: RosterMarketCard): PlayerAttributeKey[] {
  return PLAYER_ATTRIBUTE_KEYS.filter((key) => Number.isFinite(card.attributes[key]));
}

function firstValidAttribute(card: RosterMarketCard): PlayerAttributeKey {
  return validAttributes(card)[0] ?? "velocity";
}

function nullableNumber(value: string): number | null {
  if (!value) return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function readableMarketError(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  if (
    message.startsWith("Nao ") ||
    message.startsWith("Não ") ||
    message.startsWith("Sua ") ||
    message.startsWith("Seu ") ||
    message.startsWith("Esta ") ||
    message.startsWith("Este ") ||
    message.startsWith("Somente ") ||
    message.startsWith("Informe ") ||
    message.startsWith("Escolha ") ||
    message.startsWith("Entre ") ||
    message.startsWith("A operação")
  ) {
    return message;
  }
  return mapMarketErrorMessage(error);
}

function attributeLabel(attribute: PlayerAttributeKey): string {
  const labels: Record<PlayerAttributeKey, string> = {
    velocity: "Velocidade",
    finishing: "Finalização",
    passing: "Passe",
    dribbling: "Drible",
    defending: "Defesa",
    physical: "Físico",
    goalkeeping: "Goleiro",
  };
  return labels[attribute];
}

function positionLabel(position: MarketCardSummary["position"]): string {
  return { GK: "Goleiro", DEF: "Defensor", MID: "Meio-campo", ATA: "Atacante" }[position];
}

function rarityLabel(rarity: MarketCardSummary["rarity"]): string {
  return { peba: "Peba", paia: "Paia", pika: "Pika" }[rarity];
}

function sectorLabel(sector: MarketCardSummary["sector"]): string {
  return sector
    .split("_")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function offerStatusLabel(status: TransferOfferSummary["status"]): string {
  return {
    pending: "Pendente",
    accepted: "Aceita",
    rejected: "Rejeitada",
    cancelled: "Cancelada",
    expired: "Expirada",
  }[status];
}

function formatDateTime(value: string): string {
  return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short" }).format(
    new Date(value),
  );
}

const inputClass =
  "mt-1 min-h-11 w-full rounded-md border border-slate-700 bg-slate-950 px-3 py-2 text-base text-slate-100 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-slate-100 sm:text-sm";
const primaryButtonClass =
  "inline-flex min-h-11 items-center justify-center rounded-md bg-slate-100 px-4 py-2 text-sm font-medium text-slate-950 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-slate-100 disabled:cursor-not-allowed disabled:opacity-50";
const secondaryButtonClass =
  "inline-flex min-h-11 items-center justify-center rounded-md border border-slate-700 px-4 py-2 text-sm font-medium text-slate-100 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-slate-100 disabled:cursor-not-allowed disabled:opacity-50";
