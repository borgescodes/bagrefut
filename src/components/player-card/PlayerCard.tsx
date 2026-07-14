import { useEffect, useMemo, useState } from "react";
import { displaySector, playerCardStats, playerImagePath, playerInitials } from "./adapter";
import type { PlayerCardProps } from "./types";
import "./player-card.css";

function verticalCharacters(value: string) {
  return Array.from(value).map((character, index) =>
    character === " " ? (
      <span key={`gap-${index}`} className="bgr-card__vertical-gap" aria-hidden="true" />
    ) : (
      <span key={`${character}-${index}`} aria-hidden="true">
        {character}
      </span>
    ),
  );
}

/**
 * Fallback sem foto: silhueta + iniciais derivadas de players.name.
 * players.code nunca é renderizado nem exposto em aria-label.
 */
function ImageFallback({ name, position }: { name: string; position: string }) {
  return (
    <div className="bgr-card__image-fallback" role="img" aria-label={`Sem foto de ${name}`}>
      <span className="bgr-card__fallback-silhouette" aria-hidden="true" />
      <span className="bgr-card__fallback-initials" aria-hidden="true">
        {playerInitials(name)}
      </span>
      <span className="bgr-card__fallback-position" aria-hidden="true">
        {position}
      </span>
    </div>
  );
}

export function PlayerCard({
  player,
  variant = "full",
  priceLabel,
  className = "",
  priority = false,
  interactive = false,
  selected = false,
  disabled = false,
}: PlayerCardProps) {
  const imageSrc = useMemo(() => {
    try {
      return playerImagePath(player.code);
    } catch {
      return null;
    }
  }, [player.code]);
  const [imageFailed, setImageFailed] = useState(false);
  const stats = useMemo(() => playerCardStats(player), [player]);
  const sector = displaySector(player.sector);
  const rarity = player.rarity.toLocaleUpperCase("pt-BR");

  useEffect(() => setImageFailed(false), [imageSrc]);

  const showImage = imageSrc !== null && !imageFailed;

  const image = showImage ? (
    <img
      className="bgr-card__image"
      src={imageSrc}
      alt={player.name}
      loading={priority ? "eager" : "lazy"}
      fetchPriority={priority ? "high" : "auto"}
      decoding="async"
      onError={() => setImageFailed(true)}
    />
  ) : (
    <ImageFallback name={player.name} position={player.position} />
  );

  if (variant === "compact") {
    return (
      <article
        className={`bgr-card-compact ${className}`.trim()}
        data-rarity={player.rarity}
        data-interactive={interactive || undefined}
        data-selected={selected || undefined}
        data-disabled={disabled || undefined}
        aria-disabled={disabled || undefined}
        aria-label={`Carta de ${player.name}, ${player.position}, overall ${player.overall}, raridade ${rarity}`}
      >
        <div className="bgr-card-compact__artwork">
          {image}
          <span className="bgr-card-compact__chip">
            <strong className="bgr-card-compact__overall">{player.overall}</strong>
            <span className="bgr-card-compact__position">{player.position}</span>
          </span>
        </div>
        <div className="bgr-card-compact__body">
          <h3 className="bgr-card-compact__name" title={player.name}>
            {player.name}
          </h3>
          <p className="bgr-card-compact__meta">
            <span className="bgr-card-compact__sector">{sector}</span>
          </p>
          {priceLabel && <p className="bgr-card-compact__price">{priceLabel}</p>}
        </div>
      </article>
    );
  }

  return (
    <article
      className={`bgr-card ${className}`.trim()}
      data-rarity={player.rarity}
      data-interactive={interactive || undefined}
      data-selected={selected || undefined}
      data-disabled={disabled || undefined}
      aria-disabled={disabled || undefined}
      aria-label={`Carta de ${player.name}, ${player.position}, overall ${player.overall}, raridade ${rarity}`}
    >
      <aside className="bgr-card__rail">
        <div className="bgr-card__identity">
          <strong className="bgr-card__overall">{player.overall}</strong>
          <span className="bgr-card__position">{player.position}</span>
        </div>

        <div className="bgr-card__vertical-block bgr-card__sector" aria-label={`Setor ${sector}`}>
          {verticalCharacters(sector)}
        </div>

        <div
          className="bgr-card__vertical-block bgr-card__rarity"
          aria-label={`Raridade ${rarity}`}
        >
          {verticalCharacters(rarity)}
        </div>
      </aside>

      <div className="bgr-card__main">
        <div className="bgr-card__artwork">
          <div className="bgr-card__pattern" aria-hidden="true" />
          {image}
        </div>

        <h2 className="bgr-card__name" title={player.name}>
          {player.name}
        </h2>

        <dl className="bgr-card__stats">
          {stats.map((stat) => (
            <div className="bgr-card__stat" key={stat.label}>
              <dd className="bgr-card__stat-value">{stat.value}</dd>
              <dt className="bgr-card__stat-label">{stat.label}</dt>
            </div>
          ))}
        </dl>
      </div>
    </article>
  );
}
