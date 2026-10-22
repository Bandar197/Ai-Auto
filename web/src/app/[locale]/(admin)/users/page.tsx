import { UsersView } from "@/components/views/UsersView";
import { navMetadata } from "@/i18n/metadata";

export function generateMetadata({ params }: PageProps<"/[locale]/users">) {
  return navMetadata(params, "users");
}

export default function Page() {
  return <UsersView />;
}
