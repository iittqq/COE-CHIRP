import { useEffect, useRef, useState } from "react";
import { Box, Typography } from "@mui/material";
import WifiTetheringRoundedIcon from "@mui/icons-material/WifiTetheringRounded";

export type SystemStatus = "online" | "connecting" | "offline";

interface SystemStatusCardProps {
  status: SystemStatus;
  siteName: string;
  onSendPing: () => void;
  showHeader?: boolean;
}

const PING_INTERVAL_SECONDS = 60;

export default function SystemStatusCard({
  status,
  siteName,
  onSendPing,
  showHeader = true,
}: SystemStatusCardProps) {
  const [elapsedSeconds, setElapsedSeconds] = useState(0);
  const onSendPingRef = useRef(onSendPing);
  onSendPingRef.current = onSendPing;

  // Mirrors the Flutter card's wall-clock ping timer: keeps counting across
  // tab switches (since Home/Scan stay mounted), pauses while backgrounded
  // (page hidden) or while a ping is already in flight ("connecting"), and
  // resumes from where it left off rather than resetting.
  useEffect(() => {
    if (status === "connecting") return;

    let cancelled = false;
    const tick = () => {
      if (cancelled || document.hidden) return;
      setElapsedSeconds((prev) => {
        const next = prev + 1;
        if (next >= PING_INTERVAL_SECONDS) {
          onSendPingRef.current();
          return 0;
        }
        return next;
      });
    };

    const interval = setInterval(tick, 1000);
    return () => {
      cancelled = true;
      clearInterval(interval);
    };
  }, [status]);

  const isOnline = status === "online";
  const isOffline = status === "offline";

  let bgColor = "#FEEBC8";
  let dotColor = "#ED8936";
  let textColor = "#9C4221";
  let statusLabel = "Connecting";

  if (isOnline) {
    bgColor = "#E6F9F1";
    dotColor = "#38A169";
    textColor = "#2F855A";
    statusLabel = "Online";
  } else if (isOffline) {
    bgColor = "#FEF2F2";
    dotColor = "#EF4444";
    textColor = "#991B1B";
    statusLabel = "Offline";
  }

  const remainingSeconds = PING_INTERVAL_SECONDS - elapsedSeconds;

  return (
    <Box sx={{ display: "flex", flexDirection: "column", alignItems: "stretch" }}>
      <Box
        sx={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
          pl: 0.5,
          pr: 1,
          pb: 1.5,
        }}
      >
        {showHeader ? (
          <Typography sx={{ fontSize: 16, fontWeight: 600, color: "#9CA3AF" }}>
            System Status
          </Typography>
        ) : (
          <Box />
        )}
        <Typography sx={{ fontSize: 12, color: "#9CA3AF" }}>
          {remainingSeconds}
        </Typography>
      </Box>
      <Box
        sx={{
          p: 3,
          borderRadius: "20px",
          bgcolor: "#FFFFFF",
          border: "1px solid #F3F4F6",
          boxShadow: "0 4px 12px rgba(0,0,0,0.04)",
        }}
      >
        <Box
          sx={{
            display: "flex",
            justifyContent: "space-between",
            alignItems: "center",
          }}
        >
          <Box sx={{ display: "flex", alignItems: "center", gap: 1.25 }}>
            <WifiTetheringRoundedIcon sx={{ color: "#2563EB", fontSize: 24 }} />
            <Typography sx={{ fontSize: 18, fontWeight: 700, color: "#1A202C" }}>
              Connection
            </Typography>
          </Box>
          <Box
            sx={{
              display: "flex",
              alignItems: "center",
              gap: 1,
              px: 1.25,
              py: 0.5,
              borderRadius: "20px",
              bgcolor: bgColor,
            }}
          >
            <Box
              sx={{
                width: 8,
                height: 8,
                borderRadius: "50%",
                bgcolor: dotColor,
              }}
            />
            <Typography sx={{ color: textColor, fontWeight: 700, fontSize: 13 }}>
              {statusLabel}
            </Typography>
          </Box>
        </Box>
        <Typography
          sx={{
            mt: 1.5,
            fontSize: 30,
            fontWeight: 800,
            color: "#1A202C",
            letterSpacing: "-1px",
          }}
        >
          {siteName}
        </Typography>
      </Box>
    </Box>
  );
}
