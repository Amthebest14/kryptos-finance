import { Routes, Route } from "react-router-dom";
import { AppProvider } from "./state/AppContext";
import { Header } from "./components/Header";
import { TransactionModal } from "./components/TransactionModal";
import { Toast } from "./components/Toast";
import { Landing } from "./pages/Landing";
import { Dashboard } from "./pages/Dashboard";
import { LiquidationsFeed } from "./pages/LiquidationsFeed";
import { Stats } from "./pages/Stats";
import { Staking } from "./pages/Staking";
import { PrivacyCheck } from "./pages/PrivacyCheck";

export default function App() {
  return (
    <AppProvider>
      <div style={{ minHeight: "100vh", background: "var(--bg)", color: "var(--text)", fontFamily: "Geist,Helvetica,'Helvetica Neue',sans-serif", fontSize: 14, lineHeight: 1.45 }}>
        <Header />
        <Routes>
          <Route path="/" element={<Landing />} />
          <Route path="/dashboard" element={<Dashboard />} />
          <Route path="/liquidations" element={<LiquidationsFeed />} />
          <Route path="/stats" element={<Stats />} />
          <Route path="/staking" element={<Staking />} />
          <Route path="/exposure" element={<PrivacyCheck />} />
        </Routes>
        <TransactionModal />
        <Toast />
      </div>
    </AppProvider>
  );
}
