import { OverviewView } from "@/components/views/OverviewView";
import { navMetadata } from "@/i18n/metadata";

export function generateMetadata({ params }: PageProps<"/[locale]">) {
  return navMetadata(params, "overview");
}

export default function Page() {
  return <OverviewView />;
}
