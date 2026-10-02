import { AdminDashboard } from "@/components/admin-dashboard";
import { AuthProvider } from "@/context/auth-context";

export default function MusicAdminPage() {
  return <AuthProvider><AdminDashboard /></AuthProvider>;
}
