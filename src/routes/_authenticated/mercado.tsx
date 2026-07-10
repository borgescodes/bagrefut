import { useMemo, useState, type ReactNode } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createFileRoute, Link } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import { PlayerCard, type PlayerCardData } from "@/components/player-card";
import {
  MAX_MARKET_PRICE_CENTS,
  MAX_ROSTER_SIZE,
  MAX_WALLET_CENTS,
  MIN_ROSTER_SIZE,
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

type MarketTab = "roster" | "system" | "p2p" | "offers";
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
  const [tab, setTab] = useState<MarketTab>("roster");
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
    return <MarketShell loadingMessage="Carregando elenco, mercado e saldo..." />;
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
          <p className="mt-2 text-sm text-slate-400">
            Elenco {roster.length}/{MAX_ROSTER_SIZE} · mínimo {MIN_ROSTER_SIZE}
          </p>
        </div>
        <div className="rounded-md border border-slate-700 px-4 py-3 text-right">
          <p className="text-xs uppercase tracking-wide text-slate-400">Saldo atual</p>
          <p className="mt-1 text-lg font-semibold tabular-nums">
            {formatMarketPrice(club.balance_cents)}
          </p>
          <p className="mt-1 text-xs text-slate-500">
            limite {formatMarketPrice(MAX_WALLET_CENTS)}
          </p>
        </div>
      </header>

      <div className="mt-6 overflow-x-auto" role="tablist" aria-label="Áreas do mercado">
        <div className="flex min-w-max gap-2 border-b border-slate-800 pb-2">
          {(
            [
              ["roster", "Meu elenco"],
              ["system", "Sistema"],
              ["p2p", "P2P"],
              ["offers", "Trocas"],
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
        {tab === "roster" && (
          <RosterTab
            cards={roster}
            balanceCents={club.balance_cents}
            refreshMarket={refreshMarket}
            reportSuccess={reportSuccess}
            reportError={reportError}
          />
        )}
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
      props.reportSuccess("Carta vendida ao sistema e adicionada à vitrine.");
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
        description="Somente suas cartas aparecem aqui. Treine ou venda ao sistema por 50% do valor de referência."
      />
      <div className="mt-3 rounded-md border border-slate-800 p-3 text-sm text-slate-400">
        Você possui {props.cards.length} de {MAX_ROSTER_SIZE} cartas. Venda bloqueada ao atingir{" "}
        {MIN_ROSTER_SIZE}.
      </div>

      <div className="mt-4 grid gap-6 sm:grid-cols-2 xl:grid-cols-3">
        {props.cards.map((card) => {
          const attribute = attributes[card.clubPlayerId] ?? firstValidAttribute(card);
          const progress =
            card.attributeProgress.find((item) => item.attribute === attribute)?.progress ?? 0;
          const currentValue = card.attributes[attribute];
          const saleWouldExceedWallet =
            props.balanceCents + card.systemSalePriceCents > MAX_WALLET_CENTS;
          const saleReason =
            props.cards.length <= MIN_ROSTER_SIZE
              ? `Mínimo de ${MIN_ROSTER_SIZE} cartas`
              : card.isReserved
                ? "Carta reservada"
                : saleWouldExceedWallet
                  ? "Saldo máximo R$ 999,99"
                  : null;

          return (
            <MarketCardFrame
              key={card.clubPlayerId}
              card={card}
              priceLabel="Venda ao sistema"
              priceCents={card.systemSalePriceCents}
              badge={card.isReserved ? "Carta reservada" : undefined}
            >
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
                {attributeLabel(attribute)}: {currentValue} · progresso {progress}/3 · custo{" "}
                {formatMarketPrice(card.trainingCostCents)}
              </p>

              <div className="grid gap-2 sm:grid-cols-2">
                <button
                  type="button"
                  disabled={
                    Boolean(saleReason) || sellMutation.isPending || trainMutation.isPending
                  }
                  onClick={() => setSale(card)}
                  className={secondaryButtonClass}
                >
                  {saleReason ?? "Vender"}
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
            </MarketCardFrame>
          );
        })}
      </div>

      <ConfirmDialog
        open={sale !== null}
        title="Confirmar venda ao sistema"
        description={
          sale
            ? `${sale.name}: você receberá ${formatMarketPrice(
                sale.systemSalePriceCents,
              )}. A carta sairá do clube e ficará disponível na vitrine do sistema por ${formatMarketPrice(
                sale.referenceValueCents,
              )}.`
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
            ? `${training.card.name}: ${attributeLabel(
                training.attribute,
              )} por ${formatMarketPrice(training.card.trainingCostCents)}. Saldo após: ${formatMarketPrice(
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
      props.reportSuccess("Carta comprada do sistema.");
      await props.refreshMarket();
    },
    onError: props.reportError,
  });

  return (
    <div>
      <SectionHeading
        title="Vitrine do sistema"
        description="Começa vazia. Só exibe cartas vendidas por clubes; o sistema revende por 100% do valor de referência."
      />
      <MarketFilterPanel filters={props.filters} setFilters={props.setFilters} />

      {props.cards.length === 0 ? (
        <EmptyState text="Vitrine vazia. Uma carta aparecerá aqui quando algum clube vender ao sistema." />
      ) : visibleCards.length === 0 ? (
        <EmptyState text="Nenhuma carta da vitrine atende aos filtros." />
      ) : (
        <div className="mt-4 grid gap-6 sm:grid-cols-2 xl:grid-cols-3">
          {visibleCards.map((card) => {
            const reason = !card.isAvailable
              ? "Carta indisponível"
              : props.rosterSize >= MAX_ROSTER_SIZE
                ? `Elenco com ${MAX_ROSTER_SIZE} cartas`
                : props.balanceCents < card.priceCents
                  ? "Saldo insuficiente"
                  : null;

            return (
              <MarketCardFrame
                key={card.clubPlayerId}
                card={card}
                priceLabel="Preço do sistema"
                priceCents={card.priceCents}
              >
                <button
                  type="button"
                  disabled={Boolean(reason) || mutation.isPending}
                  onClick={() => setSelected(card)}
                  className={primaryButtonClass}
                >
                  {mutation.isPending ? "Comprando..." : (reason ?? "Comprar")}
                </button>
              </MarketCardFrame>
            );
          })}
        </div>
      )}

      <ConfirmDialog
        open={selected !== null}
        title="Confirmar compra do sistema"
        description={
          selected
            ? `${selected.name}: ${formatMarketPrice(
                selected.priceCents,
              )}. Elenco após: ${props.rosterSize + 1}/${MAX_ROSTER_SIZE}. Saldo após: ${formatMarketPrice(
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
      props.reportSuccess("Anúncio criado. Carta reservada até venda ou cancelamento.");
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
      props.reportSuccess(selected.type === "buy" ? "Compra P2P concluída." : "Anúncio cancelado.");
      await props.refreshMarket();
    },
    onError: props.reportError,
  });

  return (
    <div>
      <SectionHeading
        title="Mercado P2P"
        description="Anúncios de preço fixo entre clubes. Você só anuncia cartas do próprio elenco."
      />

      <form
        className="mt-4 rounded-md border border-slate-800 p-4"
        onSubmit={(event) => {
          event.preventDefault();
          if (
            canSubmitMarketAction({
              isPending: createMutation.isPending,
              isValid: listingValidation.success && props.rosterSize > MIN_ROSTER_SIZE,
            })
          ) {
            createMutation.mutate();
          }
        }}
      >
        <h3 className="font-semibold">Criar anúncio</h3>
        <div className="mt-3 grid gap-3 md:grid-cols-[minmax(0,1fr)_180px_auto] md:items-end">
          <label className="text-sm">
            <span className="text-slate-300">Minha carta</span>
            <select
              value={listingCardId}
              onChange={(event) => setListingCardId(event.target.value)}
              className={inputClass}
            >
              <option value="">Selecionar carta própria</option>
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
              max={MAX_MARKET_PRICE_CENTS}
              value={listingPrice}
              onChange={(event) => setListingPrice(event.target.value)}
              className={inputClass}
            />
          </label>

          <button
            type="submit"
            disabled={
              props.rosterSize <= MIN_ROSTER_SIZE ||
              !listingValidation.success ||
              createMutation.isPending ||
              eligibleCards.length === 0
            }
            className={primaryButtonClass}
          >
            {createMutation.isPending ? "Criando..." : "Anunciar"}
          </button>
        </div>
        <p className="mt-2 text-xs text-slate-400">
          Preço: R$ 0,01 a R$ 100,00. O clube precisa permanecer com no mínimo {MIN_ROSTER_SIZE}{" "}
          cartas.
        </p>
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
        <div className="mt-4 grid gap-6 sm:grid-cols-2 xl:grid-cols-3">
          {visibleListings.map((listing) => {
            const buyReason = listing.isMine
              ? null
              : props.rosterSize >= MAX_ROSTER_SIZE
                ? `Elenco com ${MAX_ROSTER_SIZE} cartas`
                : props.balanceCents < listing.priceCents
                  ? "Saldo insuficiente"
                  : null;

            return (
              <MarketCardFrame
                key={listing.listingId}
                card={listing}
                priceLabel="Preço P2P"
                priceCents={listing.priceCents}
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
              </MarketCardFrame>
            );
          })}
        </div>
      )}

      <ConfirmDialog
        open={action !== null}
        title={action?.type === "buy" ? "Confirmar compra P2P" : "Cancelar anúncio"}
        description={
          action?.type === "buy"
            ? `${action.listing.name}: ${formatMarketPrice(
                action.listing.priceCents,
              )}. Elenco após: ${props.rosterSize + 1}/${MAX_ROSTER_SIZE}.`
            : action
              ? `Cancelar anúncio de ${action.listing.name}? A carta voltará a ficar livre no seu elenco.`
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
            ? "Oferta rejeitada."
            : "Oferta cancelada.",
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
        title="Trocas entre clubes"
        description={`Trocas podem incluir cartas e até ${formatMarketPrice(
          MAX_MARKET_PRICE_CENTS,
        )}. Ambos os elencos devem terminar entre ${MIN_ROSTER_SIZE} e ${MAX_ROSTER_SIZE}.`}
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
              )}. A operação transfere tudo ou não altera nada.`
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
      props.reportSuccess("Oferta criada. Cartas envolvidas ficaram reservadas.");
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
              {target.name} ({target.abbreviation}) · {target.rosterSize}/{MAX_ROSTER_SIZE}
            </option>
          ))}
        </select>
      </label>

      <div className="grid gap-5 lg:grid-cols-2">
        <CardSelection
          title="Minhas cartas oferecidas"
          cards={eligibleOwnCards}
          selected={ownCards}
          onToggle={(cardId) => setOwnCards(toggleCard(ownCards, cardId))}
        />
        <CardSelection
          title="Cartas solicitadas ao outro clube"
          cards={targetRoster.data ?? []}
          selected={targetCards}
          loading={targetRoster.isLoading}
          error={targetRoster.error}
          onToggle={(cardId) => setTargetCards(toggleCard(targetCards, cardId))}
        />
      </div>

      <label className="block max-w-xs text-sm">
        <span className="text-slate-300">Dinheiro pago ao destinatário (centavos)</span>
        <input
          type="number"
          min={0}
          max={MAX_MARKET_PRICE_CENTS}
          value={cash}
          onChange={(event) => setCash(event.target.value)}
          className={inputClass}
        />
      </label>

      <div className="grid gap-3 rounded-md border border-slate-900 p-3 text-sm sm:grid-cols-3">
        <Info
          label="Meu elenco após"
          value={projection ? String(projection.fromRosterSize) : "-"}
        />
        <Info
          label="Elenco destinatário após"
          value={projection ? String(projection.toRosterSize) : "-"}
        />
        <Info label="Meu saldo após" value={formatMarketPrice(projectedBalance)} />
      </div>

      {projection && !projection.isValid && (
        <p className="text-sm text-amber-300">
          Ambos os elencos precisam terminar entre {MIN_ROSTER_SIZE} e {MAX_ROSTER_SIZE} cartas.
        </p>
      )}
      {projectedBalance < 0 && (
        <p className="text-sm text-amber-300">Saldo insuficiente para esta oferta.</p>
      )}

      <p className="text-xs text-slate-400">
        Expira em 24 horas. Máximo de 5 cartas de cada lado e R$ 100,00 em dinheiro.
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
            Status: {offerStatusLabel(offer.status)} · dinheiro:{" "}
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

function MarketCardFrame(props: {
  card: MarketCardSummary;
  priceLabel: string;
  priceCents: number;
  badge?: string;
  children: ReactNode;
}) {
  return (
    <article className="flex flex-col rounded-xl border border-slate-800 bg-slate-950/60 p-4">
      <div className="mx-auto w-full max-w-[19rem]">
        <PlayerCard player={toPlayerCardData(props.card)} />
      </div>

      {props.badge && (
        <p className="mt-4 text-center text-xs font-medium text-amber-300">{props.badge}</p>
      )}

      <dl className="mt-4 space-y-1 border-t border-slate-800 pt-3 text-sm">
        <div className="flex justify-between gap-3 text-slate-400">
          <dt>Valor de referência</dt>
          <dd className="tabular-nums">{formatMarketPrice(props.card.referenceValueCents)}</dd>
        </div>
        <div className="flex justify-between gap-3 font-medium">
          <dt>{props.priceLabel}</dt>
          <dd className="tabular-nums">{formatMarketPrice(props.priceCents)}</dd>
        </div>
      </dl>

      <div className="mt-4 flex flex-1 flex-col justify-end gap-3">{props.children}</div>
    </article>
  );
}

function toPlayerCardData(card: MarketCardSummary): PlayerCardData {
  return {
    id: card.playerId,
    code: `${card.position}-${card.playerId.slice(0, 8)}`.toUpperCase(),
    name: card.name,
    position: card.position,
    rarity: card.rarity,
    sector: card.sector,
    overall: card.overall,
    velocity: card.attributes.velocity,
    finishing: card.attributes.finishing,
    passing: card.attributes.passing,
    dribbling: card.attributes.dribbling,
    defending: card.attributes.defending,
    physical: card.attributes.physical,
    goalkeeping: card.attributes.goalkeeping,
  };
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
  children?: ReactNode;
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
