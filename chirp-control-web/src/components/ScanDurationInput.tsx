import { useEffect, useState } from "react";
import { Box, Button, TextField, Typography } from "@mui/material";

export interface TimerButtonData {
  title: string;
  subtitle: string;
}

interface ScanDurationInputProps {
  buttons: TimerButtonData[];
  forceClose?: boolean;
  onDurationChanged: (totalSeconds: number) => void;
}

export default function ScanDurationInput({
  buttons,
  forceClose = false,
  onDurationChanged,
}: ScanDurationInputProps) {
  const [selectedIndex, setSelectedIndex] = useState<number | null>(null);
  const [showInput, setShowInput] = useState(false);
  const [minutes, setMinutes] = useState("");
  const [seconds, setSeconds] = useState("");

  useEffect(() => {
    if (forceClose && showInput) setShowInput(false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [forceClose]);

  const notifyParent = (
    nextShowInput: boolean,
    nextSelectedIndex: number | null,
    nextMinutes: string,
    nextSeconds: string,
  ) => {
    let totalSeconds = 0;
    if (nextShowInput) {
      totalSeconds = (parseInt(nextMinutes, 10) || 0) * 60 +
        (parseInt(nextSeconds, 10) || 0);
    } else if (nextSelectedIndex !== null) {
      totalSeconds = (parseInt(buttons[nextSelectedIndex].title, 10) || 0) * 60;
    }
    onDurationChanged(totalSeconds);
  };

  return (
    <Box sx={{ display: "flex", flexDirection: "column", gap: 3 }}>
      <Box sx={{ display: "flex", justifyContent: "space-between", gap: 1 }}>
        {buttons.map((item, index) => {
          const isLast = index === buttons.length - 1;
          const isSelected = selectedIndex === index;
          const isNumeric = !Number.isNaN(Number(item.title));

          return (
            <Button
              key={item.title}
              onClick={() => {
                setSelectedIndex(index);
                setShowInput(isLast);
                notifyParent(isLast, index, minutes, seconds);
              }}
              sx={{
                width: 80,
                height: 80,
                minWidth: 80,
                p: 0,
                borderRadius: "12px",
                bgcolor: isSelected ? "primary.main" : "#FFFFFF",
                color: isSelected ? "#FFFFFF" : "#000000",
                border: "1px solid #E5E7EB",
                "&:hover": {
                  bgcolor: isSelected ? "primary.dark" : "#F3F4F6",
                },
              }}
            >
              <Box sx={{ display: "flex", flexDirection: "column", alignItems: "center" }}>
                <Box sx={{ display: "flex", alignItems: "baseline", gap: 0.25 }}>
                  <Typography sx={{ fontSize: 18, fontWeight: 700 }}>
                    {item.title}
                  </Typography>
                  {isNumeric && (
                    <Typography
                      sx={{
                        fontSize: 11,
                        color: isSelected ? "rgba(255,255,255,0.7)" : "text.secondary",
                      }}
                    >
                      min
                    </Typography>
                  )}
                </Box>
                <Typography
                  sx={{
                    fontSize: 12,
                    color: isSelected ? "rgba(255,255,255,0.7)" : "text.secondary",
                  }}
                >
                  {item.subtitle}
                </Typography>
              </Box>
            </Button>
          );
        })}
      </Box>
      {showInput && (
        <Box sx={{ display: "flex", gap: 2 }}>
          <TextField
            label="Minutes"
            type="number"
            fullWidth
            value={minutes}
            onChange={(e) => {
              setMinutes(e.target.value);
              notifyParent(true, selectedIndex, e.target.value, seconds);
            }}
          />
          <TextField
            label="Seconds"
            type="number"
            fullWidth
            value={seconds}
            onChange={(e) => {
              setSeconds(e.target.value);
              notifyParent(true, selectedIndex, minutes, e.target.value);
            }}
          />
        </Box>
      )}
    </Box>
  );
}
