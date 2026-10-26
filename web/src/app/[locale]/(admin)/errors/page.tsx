import { ErrorsView } from "@/components/views/ErrorsView";
import { navMetadata } from "@/i18n/metadata";

export function generateMetadata({ params }: PageProps<"/[locale]/errors">) {
  return navMetadata(params, "errors");
}

export default function Page() {
  return <ErrorsView />;
}
