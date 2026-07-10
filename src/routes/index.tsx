import { createFileRoute, Link } from "@tanstack/react-router";
import { ArrowRight, ShieldCheck, ShoppingBag, Trophy, UsersRound } from "lucide-react";
import { BrandMark } from "@/components/brand/BrandMark";

export const Route = createFileRoute("/")({
  component: LandingPage,
  head: () => ({
    meta: [
      { title: "BagreFut — PGM joga aqui" },
      {
        name: "description",
        content: "Monte seu clube, gerencie o elenco e dispute o Bagreleirão com seus amigos.",
      },
    ],
  }),
});

const features = [
  {
    icon: UsersRound,
    title: "Monte o elenco",
    text: "Escolha sua escalação, formação e estilo para cada rodada.",
  },
  {
    icon: ShoppingBag,
    title: "Movimente o mercado",
    text: "Treine cartas, negocie e proteja o caixa do clube.",
  },
  {
    icon: Trophy,
    title: "Dispute a temporada",
    text: "Acompanhe jogos, classificação e o histórico do Bagreleirão.",
  },
] as const;

function LandingPage() {
  return (
    <main className="landing-page">
      <nav className="landing-nav" aria-label="Navegação pública">
        <BrandMark />
        <Link to="/login" className="landing-nav__login">
          Entrar
        </Link>
      </nav>

      <section className="landing-hero">
        <div className="landing-hero__copy">
          <p className="landing-eyebrow">
            <ShieldCheck size={15} aria-hidden="true" /> Liga privada · gestão de verdade
          </p>
          <h1>
            Monte clube.
            <br />
            Gerencie elenco.
            <br />
            <span>Domine PGM.</span>
          </h1>
          <p className="landing-hero__description">
            Um jogo enxuto de gestão de futebol: cartas permanentes, economia fechada, escalação por
            rodada e decisões que valem a temporada.
          </p>
          <div className="landing-hero__actions">
            <Link to="/cadastro" className="landing-primary-action">
              Criar minha conta <ArrowRight size={18} aria-hidden="true" />
            </Link>
            <Link to="/login" className="landing-secondary-action">
              Já tenho conta
            </Link>
          </div>
        </div>
        <div className="landing-scoreboard" aria-label="Exemplo de placar BagreFut">
          <div className="landing-scoreboard__meta">
            <span>Bagreleirão</span>
            <span>Rodada 07</span>
          </div>
          <div className="landing-scoreboard__teams">
            <div>
              <span className="landing-team-badge">TUB</span>
              <strong>Tubarões</strong>
            </div>
            <p>
              <strong>3</strong>
              <span>×</span>
              <strong>2</strong>
            </p>
            <div>
              <span className="landing-team-badge">FEC</span>
              <strong>Feras EC</strong>
            </div>
          </div>
          <div className="landing-scoreboard__status">
            <span aria-hidden="true" /> Encerrado · PGM
          </div>
        </div>
      </section>

      <section className="landing-features" aria-label="Como funciona">
        {features.map(({ icon: Icon, title, text }, index) => (
          <article key={title}>
            <div className="landing-feature__number">0{index + 1}</div>
            <Icon aria-hidden="true" />
            <h2>{title}</h2>
            <p>{text}</p>
          </article>
        ))}
      </section>
      <footer className="landing-footer">
        <BrandMark compact />
        <span>BagreFut · PGM joga aqui</span>
      </footer>
    </main>
  );
}
