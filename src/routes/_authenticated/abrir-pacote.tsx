import { createFileRoute } from "@tanstack/react-router";
import { PackOpeningExperience } from "@/components/pack-opening/PackOpeningExperience";

export const Route = createFileRoute("/_authenticated/abrir-pacote")({
  component: PackOpeningExperience,
});
