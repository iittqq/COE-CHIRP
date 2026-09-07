import { useEffect, useRef, useState, type ChangeEvent } from "react";
import {
  Box,
  Button,
  CircularProgress,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  IconButton,
  InputAdornment,
  TextField,
  Typography,
} from "@mui/material";
import UploadFileRoundedIcon from "@mui/icons-material/UploadFileRounded";
import SearchRoundedIcon from "@mui/icons-material/SearchRounded";
import SensorsRoundedIcon from "@mui/icons-material/SensorsRounded";
import AccessTimeRoundedIcon from "@mui/icons-material/AccessTimeRounded";
import ChevronRightRoundedIcon from "@mui/icons-material/ChevronRightRounded";
import CheckRoundedIcon from "@mui/icons-material/CheckRounded";
import EditOutlinedIcon from "@mui/icons-material/EditOutlined";
import DeleteOutlineRoundedIcon from "@mui/icons-material/DeleteOutlineRounded";
import { deleteScan, findScanByFolderName, loadScans, renameScan, type ScanData } from "../utils/scanRepo";
import { deriveFolderName, importScanZip } from "../utils/importScan";
import { useSnackbar } from "../notifications";

interface HistoryProps {
  onOpenScan: (scan: ScanData) => void;
  onCompareScans: (scans: ScanData[]) => void;
}

export default function History({ onOpenScan, onCompareScans }: HistoryProps) {
  const { notify } = useSnackbar();

  const [allScans, setAllScans] = useState<ScanData[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [searchText, setSearchText] = useState("");
  const [selecting, setSelecting] = useState(false);
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [renameOpen, setRenameOpen] = useState(false);
  const [renameValue, setRenameValue] = useState("");
  const [deleteConfirmOpen, setDeleteConfirmOpen] = useState(false);
  const [pendingImport, setPendingImport] = useState<{ file: File; existing: ScanData } | null>(null);

  const importInputRef = useRef<HTMLInputElement>(null);

  const reload = async () => {
    setLoading(true);
    setError(null);
    try {
      setAllScans(await loadScans());
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    reload();
  }, []);

  const toggleSelect = () => {
    setSelecting((prev) => {
      if (prev) setPicked(new Set());
      return !prev;
    });
  };

  const selectScan = (scan: ScanData) => {
    if (selecting) {
      setPicked((prev) => {
        const next = new Set(prev);
        if (next.has(scan.id)) next.delete(scan.id);
        else next.add(scan.id);
        return next;
      });
    } else {
      onOpenScan(scan);
    }
  };

  const pickedScans = () => allScans.filter((scan) => picked.has(scan.id));

  const openSelected = () => {
    const chosen = pickedScans();
    if (chosen.length === 0) return;
    if (chosen.length === 1) {
      onOpenScan(chosen[0]);
      return;
    }
    onCompareScans(chosen);
  };

  const openRenameDialog = () => {
    if (picked.size !== 1) return;
    setRenameValue(pickedScans()[0].title);
    setRenameOpen(true);
  };

  const submitRename = async () => {
    const scan = pickedScans()[0];
    setRenameOpen(false);
    if (!scan) return;
    try {
      await renameScan(scan, renameValue);
      setPicked(new Set());
      setSelecting(false);
      await reload();
      notify("Scan renamed successfully", { severity: "success" });
    } catch (err) {
      notify(`Rename failed: ${(err as Error).message}`, { severity: "error" });
    }
  };

  const confirmDelete = async () => {
    setDeleteConfirmOpen(false);
    try {
      for (const scan of pickedScans()) await deleteScan(scan);
      setPicked(new Set());
      setSelecting(false);
      await reload();
      notify("Selected scans deleted", { severity: "success" });
    } catch (err) {
      notify(`Delete failed: ${(err as Error).message}`, { severity: "error" });
    }
  };

  const finishImport = async (file: File, overwriteId?: string) => {
    try {
      await importScanZip(file, { overwriteId });
      await reload();
      notify("Scan imported successfully", { severity: "success" });
    } catch (err) {
      notify(`Import failed: ${(err as Error).message}`, { severity: "error" });
    }
  };

  const handleImportFile = async (e: ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file) return;

    const existing = await findScanByFolderName(deriveFolderName(file.name));
    if (existing) {
      setPendingImport({ file, existing });
      return;
    }
    await finishImport(file);
  };

  const confirmOverwriteImport = async () => {
    if (!pendingImport) return;
    const { file, existing } = pendingImport;
    setPendingImport(null);
    await finishImport(file, existing.id);
  };

  const q = searchText.trim().toLowerCase();
  const filtered = q
    ? allScans.filter(
        (scan) =>
          scan.title.toLowerCase().includes(q) ||
          scan.location.toLowerCase().includes(q) ||
          scan.time.toLowerCase().includes(q) ||
          scan.duration.toLowerCase().includes(q),
      )
    : allScans;

  return (
    <Box sx={{ height: "100%", display: "flex", flexDirection: "column" }}>
      <Box
        sx={{
          display: "flex",
          alignItems: "center",
          bgcolor: "#FFFFFF",
          borderBottom: "1px solid #E5E7EB",
          pl: 0.5,
          pr: 1,
          pb: 0.5,
        }}
      >
        <IconButton onClick={() => importInputRef.current?.click()}>
          <UploadFileRoundedIcon sx={{ color: "primary.main" }} />
        </IconButton>
        <Typography sx={{ flex: 1, textAlign: "center", fontWeight: 700, fontSize: 18 }}>
          {selecting ? `${picked.size} Selected` : "PAST SCANS HISTORY"}
        </Typography>
        <Button onClick={toggleSelect} sx={{ fontWeight: 600 }}>
          {selecting ? "Cancel" : "Select"}
        </Button>
      </Box>
      <input ref={importInputRef} type="file" accept=".zip" hidden onChange={handleImportFile} />

      <Box sx={{ bgcolor: "#FFFFFF", px: 2, pb: 1.25 }}>
        <Box sx={{ maxWidth: 1200, mx: "auto" }}>
          <TextField
            fullWidth
            size="small"
            placeholder="Search by date or location"
            value={searchText}
            onChange={(e) => setSearchText(e.target.value)}
            slotProps={{
              input: {
                startAdornment: (
                  <InputAdornment position="start">
                    <SearchRoundedIcon sx={{ color: "#9CA3AF" }} />
                  </InputAdornment>
                ),
                sx: { bgcolor: "#F1F3F5", borderRadius: "12px" },
              },
            }}
          />
        </Box>
      </Box>

      <Box
        sx={{
          flex: 1,
          overflow: "auto",
          p: 2,
          display: "flex",
          flexDirection: "column",
          gap: 1.5,
          maxWidth: 1200,
          width: "100%",
          mx: "auto",
        }}
      >
        {loading ? (
          <Box sx={{ display: "flex", justifyContent: "center", py: 4 }}>
            <CircularProgress />
          </Box>
        ) : error ? (
          <Typography sx={{ textAlign: "center", mt: 4 }}>Error: {error}</Typography>
        ) : allScans.length === 0 ? (
          <Box sx={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 1.5, mt: 6 }}>
            <Typography sx={{ fontSize: 16 }}>No scans found.</Typography>
            <Button
              variant="contained"
              startIcon={<UploadFileRoundedIcon />}
              onClick={() => importInputRef.current?.click()}
            >
              Import Scan
            </Button>
          </Box>
        ) : (
          filtered.map((scan) => {
            const chosen = picked.has(scan.id);
            return (
              <Box
                key={scan.id}
                onClick={() => selectScan(scan)}
                sx={{
                  bgcolor: "#FFFFFF",
                  borderRadius: "14px",
                  p: 1.75,
                  display: "flex",
                  alignItems: "center",
                  gap: 1.5,
                  cursor: "pointer",
                }}
              >
                {selecting ? (
                  <Box
                    sx={{
                      width: 24,
                      height: 24,
                      borderRadius: "50%",
                      flexShrink: 0,
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "center",
                      bgcolor: chosen ? "primary.main" : "transparent",
                      border: `2px solid ${chosen ? "#2563EB" : "#CBD5E1"}`,
                    }}
                  >
                    {chosen && <CheckRoundedIcon sx={{ fontSize: 15, color: "#FFFFFF" }} />}
                  </Box>
                ) : (
                  <Box
                    sx={{
                      width: 42,
                      height: 42,
                      flexShrink: 0,
                      borderRadius: "12px",
                      bgcolor: "#EFF6FF",
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "center",
                    }}
                  >
                    <SensorsRoundedIcon sx={{ color: "primary.main" }} />
                  </Box>
                )}
                <Box sx={{ flex: 1, minWidth: 0 }}>
                  <Box sx={{ display: "flex", justifyContent: "space-between", gap: 1 }}>
                    <Typography sx={{ fontWeight: 800, fontSize: 14 }} noWrap>
                      {scan.title}
                    </Typography>
                    <Typography sx={{ fontSize: 12, color: "#9CA3AF", flexShrink: 0 }}>
                      {scan.time}
                    </Typography>
                  </Box>
                  <Typography sx={{ fontSize: 12, color: "#6B7280", mt: 0.5 }}>
                    {scan.location}
                  </Typography>
                  <Box sx={{ display: "flex", alignItems: "center", gap: 0.75, mt: 1 }}>
                    <AccessTimeRoundedIcon sx={{ fontSize: 14, color: "#9CA3AF" }} />
                    <Typography sx={{ fontSize: 12, color: "#9CA3AF" }}>
                      {scan.duration}
                    </Typography>
                  </Box>
                </Box>
                {!selecting && <ChevronRightRoundedIcon sx={{ color: "#CBD5E1" }} />}
              </Box>
            );
          })
        )}
      </Box>

      {selecting && picked.size > 0 && (
        <Box sx={{ display: "flex", gap: 1.25, p: 2, maxWidth: 1200, width: "100%", mx: "auto" }}>
          <Button
            variant="contained"
            disabled={picked.size !== 1}
            onClick={openRenameDialog}
            sx={{
              minWidth: 60,
              height: 52,
              bgcolor: "#6B7280",
              "&:hover": { bgcolor: "#4B5563" },
            }}
          >
            <EditOutlinedIcon />
          </Button>
          <Button
            fullWidth
            variant="contained"
            onClick={openSelected}
            sx={{ height: 52, fontSize: 15 }}
          >
            Analyze Selected ({picked.size})
          </Button>
          <Button
            variant="contained"
            color="error"
            onClick={() => setDeleteConfirmOpen(true)}
            sx={{ minWidth: 60, height: 52 }}
          >
            <DeleteOutlineRoundedIcon />
          </Button>
        </Box>
      )}

      <Dialog open={renameOpen} onClose={() => setRenameOpen(false)} fullWidth maxWidth="xs">
        <DialogTitle>Rename Scan</DialogTitle>
        <DialogContent>
          <TextField
            autoFocus
            fullWidth
            placeholder="Enter new scan name"
            value={renameValue}
            onChange={(e) => setRenameValue(e.target.value)}
            sx={{ mt: 1 }}
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setRenameOpen(false)}>Cancel</Button>
          <Button onClick={submitRename}>Save</Button>
        </DialogActions>
      </Dialog>

      <Dialog open={deleteConfirmOpen} onClose={() => setDeleteConfirmOpen(false)} fullWidth maxWidth="xs">
        <DialogTitle>Delete scans?</DialogTitle>
        <DialogContent>
          <Typography>Are you sure you want to delete selected scan(s)?</Typography>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setDeleteConfirmOpen(false)}>Cancel</Button>
          <Button color="error" onClick={confirmDelete}>
            Delete
          </Button>
        </DialogActions>
      </Dialog>

      <Dialog open={!!pendingImport} onClose={() => setPendingImport(null)} fullWidth maxWidth="xs">
        <DialogTitle>Scan already exists</DialogTitle>
        <DialogContent>
          <Typography>
            A scan named &quot;{pendingImport?.existing.title}&quot; already exists. Importing
            will overwrite it and its data cannot be recovered.
          </Typography>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setPendingImport(null)}>Cancel</Button>
          <Button color="error" onClick={confirmOverwriteImport}>
            Overwrite
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}
