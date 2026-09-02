import { useState } from "react";

export function AssetBadge({ initial, tint, size = 22, logoUrl }: { initial: string; tint: string; size?: number; logoUrl?: string }) {
  const [failed, setFailed] = useState(false);

  if (logoUrl && !failed) {
    return (
      <img
        src={logoUrl}
        alt={initial}
        width={size}
        height={size}
        onError={() => setFailed(true)}
        style={{ width: size, height: size, borderRadius: "50%", objectFit: "cover", flex: "none", background: tint }}
      />
    );
  }

  return (
    <span
      style={{
        display: "grid",
        placeItems: "center",
        width: size,
        height: size,
        borderRadius: "50%",
        background: tint,
        color: "#fff",
        fontFamily: "'Geist Mono',monospace",
        fontSize: size * 0.43,
        fontWeight: 600,
        flex: "none",
      }}
    >
      {initial}
    </span>
  );
}
