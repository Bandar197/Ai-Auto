import { EcuProfilesView } from "@/components/views/EcuProfilesView";
import { navMetadata } from "@/i18n/metadata";

export function generateMetadata({ params }: PageProps<"/[locale]/ecu">) {
  return navMetadata(params, "ecu");
}

export default function Page() {
  return <EcuProfilesView />;
}
