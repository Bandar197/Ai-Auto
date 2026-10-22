import { AuditView } from "@/components/views/AuditView";
import { navMetadata } from "@/i18n/metadata";

export function generateMetadata({ params }: PageProps<"/[locale]/audit">) {
  return navMetadata(params, "audit");
}

export default function Page() {
  return <AuditView />;
}
