import { DiagnosticsView } from "@/components/views/DiagnosticsView";
import { navMetadata } from "@/i18n/metadata";

export function generateMetadata({ params }: PageProps<"/[locale]/diagnostics">) {
  return navMetadata(params, "diagnostics");
}

export default function Page() {
  return <DiagnosticsView />;
}
