import { PlansView } from "@/components/views/PlansView";
import { navMetadata } from "@/i18n/metadata";

export function generateMetadata({ params }: PageProps<"/[locale]/plans">) {
  return navMetadata(params, "plans");
}

export default function Page() {
  return <PlansView />;
}
