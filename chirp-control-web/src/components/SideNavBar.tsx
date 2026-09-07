import { Box, IconButton, List, ListItemButton, ListItemIcon, ListItemText, Typography } from "@mui/material";
import HomeRoundedIcon from "@mui/icons-material/HomeRounded";
import ExploreRoundedIcon from "@mui/icons-material/ExploreRounded";
import ArticleRoundedIcon from "@mui/icons-material/ArticleRounded";
import SettingsRoundedIcon from "@mui/icons-material/SettingsRounded";
import type { SvgIconComponent } from "@mui/icons-material";
import menuIcon from "../assets/menu.svg";
import cpraLogo from "../assets/CPRA-LOGO.jpg";

export const SIDEBAR_WIDTH = 232;

const TABS: { icon: SvgIconComponent; label: string }[] = [
  { icon: HomeRoundedIcon, label: "Home" },
  { icon: ExploreRoundedIcon, label: "Scans" },
  { icon: ArticleRoundedIcon, label: "History" },
  { icon: SettingsRoundedIcon, label: "Settings" },
];

interface SideNavBarProps {
  currentIndex: number;
  onChange: (index: number) => void;
  open: boolean;
  // Only passed by the mobile overlay variant, which needs an in-drawer
  // affordance to close since the drawer itself covers the header's
  // hamburger button that would otherwise toggle it.
  onClose?: () => void;
}

export default function SideNavBar({ currentIndex, onChange, open, onClose }: SideNavBarProps) {
  return (
    <Box
      sx={{
        width: open ? SIDEBAR_WIDTH : 0,
        flexShrink: 0,
        height: "100%",
        bgcolor: "#FFFFFF",
        borderRight: open ? "1px solid #E5E7EB" : "none",
        display: "flex",
        flexDirection: "column",
        py: 2.5,
        overflow: "hidden",
        whiteSpace: "nowrap",
        transition: "width 0.2s ease, border-right 0.2s ease",
      }}
    >
      <Box sx={{ display: "flex", alignItems: "center", gap: 1, px: 3, pb: 3 }}>
        <Box component="img" src={cpraLogo} alt="CPRA" sx={{ width: 28, height: 28, borderRadius: "50%" }} />
        <Typography sx={{ fontWeight: 800, fontSize: 18, color: "#111827", flex: 1 }}>
          Chirp Control
        </Typography>
        {onClose && (
          <IconButton onClick={onClose} size="small" aria-label="Close navigation">
            <Box component="img" src={menuIcon} alt="" sx={{ width: 20, height: 20 }} />
          </IconButton>
        )}
      </Box>
      <List sx={{ display: "flex", flexDirection: "column", gap: 0.5, px: 1.5 }}>
        {TABS.map((tab, index) => {
          const selected = currentIndex === index;
          const Icon = tab.icon;
          return (
            <ListItemButton
              key={tab.label}
              selected={selected}
              onClick={() => onChange(index)}
              sx={{
                borderRadius: "10px",
                py: 1.1,
                color: selected ? "primary.main" : "#4B5563",
                "&.Mui-selected": {
                  bgcolor: "#EFF6FF",
                  "&:hover": { bgcolor: "#EFF6FF" },
                },
              }}
            >
              <ListItemIcon sx={{ minWidth: 40, color: "inherit" }}>
                <Icon />
              </ListItemIcon>
              <ListItemText
                primary={tab.label}
                slotProps={{ primary: { sx: { fontWeight: selected ? 700 : 600 } } }}
              />
            </ListItemButton>
          );
        })}
      </List>
    </Box>
  );
}
