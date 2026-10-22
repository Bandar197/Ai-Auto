import { AdminShell } from "@/components/layout/AdminShell";

export default function AdminLayout({ children }: LayoutProps<"/[locale]">) {
  return <AdminShell>{children}</AdminShell>;
}
