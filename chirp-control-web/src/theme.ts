import { createTheme } from "@mui/material/styles";

// Mirrors chirp_control's ThemeData: ColorScheme.fromSeed(seedColor: Colors.blue),
// white scaffold background, flat white app bars, rounded Material 3-ish cards.
export const theme = createTheme({
  palette: {
    mode: "light",
    primary: {
      main: "#2563EB",
    },
    background: {
      default: "#F5F6FA",
      paper: "#FFFFFF",
    },
    text: {
      primary: "#111827",
      secondary: "#6B7280",
    },
    error: {
      main: "#DC2626",
    },
    divider: "#E5E7EB",
  },
  shape: {
    borderRadius: 14,
  },
  typography: {
    fontFamily: [
      "-apple-system",
      "BlinkMacSystemFont",
      '"Segoe UI"',
      "Roboto",
      "sans-serif",
    ].join(","),
  },
  components: {
    MuiAppBar: {
      defaultProps: {
        color: "transparent",
        elevation: 0,
      },
      styleOverrides: {
        root: {
          backgroundColor: "#FFFFFF",
          color: "#000000",
          borderBottom: "1px solid #E5E7EB",
        },
      },
    },
    MuiButton: {
      styleOverrides: {
        root: {
          textTransform: "none",
          fontWeight: 700,
          borderRadius: 12,
        },
      },
    },
    MuiPaper: {
      styleOverrides: {
        root: {
          backgroundImage: "none",
        },
      },
    },
    MuiDialog: {
      styleOverrides: {
        paper: {
          borderRadius: 16,
        },
      },
    },
  },
});
