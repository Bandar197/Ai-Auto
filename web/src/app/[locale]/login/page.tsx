import { LoginView } from "@/components/views/LoginView";
import { navMetadata } from "@/i18n/metadata";

export function generateMetadata({ params }: PageProps<"/[locale]/login">) {
  return navMetadata(params, "login");
}

export default function Page() {
  return <LoginView />;
}
