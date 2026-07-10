import { useEffect, useMemo, useState } from "react";
import { displaySector, playerCardStats, playerImagePath } from "./adapter";
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

export function PlayerCard({
  player,
  className = "",
  priority = false,
  interactive = false,
  selected = false,
  disabled = false,
}: PlayerCardProps) {
  const imageSrc = useMemo(() => {
    try {
      return playerImagePath(player.id);
    } catch {
      return null;
    }
  }, [player.id]);
  const [imageFailed, setImageFailed] = useState(false);
  const stats = useMemo(() => playerCardStats(player), [player]);
  const sector = displaySector(player.sector);
  const rarity = player.rarity.toLocaleUpperCase("pt-BR");

  useEffect(() => setImageFailed(false), [imageSrc]);

  const showImage = imageSrc !== null && !imageFailed;

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
          {showImage ? (
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
            <div
              className="bgr-card__image-fallback"
              role="img"
              aria-label={`Imagem ${player.code}`}
            >
              <span>{player.code}</span>
            </div>
          )}
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
