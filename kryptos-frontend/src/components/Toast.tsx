import { useApp } from "../state/AppContext";

export function Toast() {
  const { ui } = useApp();
  const toast = ui.toast;
  if (!toast) return null;

  return (
    <div
      style={{
        position: "fixed",
        zIndex: 80,
        right: 22,
        bottom: 22,
        display: "flex",
        alignItems: "center",
        gap: 11,
        maxWidth: 360,
        padding: "13px 15px",
        border: "1px solid var(--border2)",
        borderRadius: 12,
        background: "var(--surface)",
        boxShadow: "0 16px 40px rgba(0,0,0,0.45)",
        animation: "kfToast 200ms ease-out",
      }}
    >
      <span
        style={{
          flex: "none",
          display: "grid",
          placeItems: "center",
          width: 22,
          height: 22,
          borderRadius: "50%",
          background: toast.color,
          color: "#0B1020",
          fontSize: 12,
          fontWeight: 700,
        }}
      >
        {toast.glyph}
      </span>
      <div>
        <div style={{ fontSize: 13.5, fontWeight: 600 }}>{toast.title}</div>
        <div style={{ marginTop: 2, fontSize: 12.5, color: "var(--dim)" }}>{toast.body}</div>
      </div>
    </div>
  );
}
