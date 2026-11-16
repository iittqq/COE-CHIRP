import { useState } from "react";
import {
  Box,
  Button,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  InputAdornment,
  TextField,
  Typography,
} from "@mui/material";
import {
  ACQUISITION_FIELDS,
  formatAcquisitionValue,
  normalizeAcquisition,
  type AcquisitionMetadata,
} from "../utils/acquisition";

interface AcquisitionCardProps {
  acquisition: AcquisitionMetadata;
  onSave: (next: AcquisitionMetadata) => Promise<void>;
}

const cardSx = { bgcolor: "#FFFFFF", borderRadius: "14px", border: "1px solid #E5E7EB", p: 1.75 };

// Shows and edits the acquisition settings stored with a scan (sonar model,
// firmware, beam mode, transducer elevation and datum, blind-spot offset).
export default function AcquisitionCard({ acquisition, onSave }: AcquisitionCardProps) {
  const [open, setOpen] = useState(false);
  const [draft, setDraft] = useState<Record<string, string>>({});
  const [saving, setSaving] = useState(false);

  const openEditor = () => {
    setDraft(
      Object.fromEntries(
        ACQUISITION_FIELDS.map((spec) => [spec.key, String(acquisition[spec.key] ?? "")]),
      ),
    );
    setOpen(true);
  };

  const invalidNumbers = ACQUISITION_FIELDS.filter(
    (spec) =>
      spec.kind === "number" &&
      (draft[spec.key] ?? "").trim() !== "" &&
      !Number.isFinite(Number(draft[spec.key].trim())),
  ).map((spec) => spec.key);

  const handleSave = async () => {
    setSaving(true);
    try {
      await onSave(normalizeAcquisition(draft));
      setOpen(false);
    } finally {
      setSaving(false);
    }
  };

  return (
    <Box sx={cardSx}>
      <Box sx={{ display: "flex", alignItems: "center", mb: 1 }}>
        <Typography sx={{ flex: 1, fontSize: 13, fontWeight: 800 }}>Acquisition settings</Typography>
        <Button size="small" onClick={openEditor}>
          Edit
        </Button>
      </Box>
      {ACQUISITION_FIELDS.map((spec) => (
        <Box key={spec.key} sx={{ display: "flex", justifyContent: "space-between", gap: 2, mb: 0.75 }}>
          <Typography sx={{ color: "text.secondary", fontSize: 12, fontWeight: 600 }}>{spec.label}</Typography>
          <Typography sx={{ fontSize: 12, fontWeight: 700, textAlign: "right" }}>
            {formatAcquisitionValue(acquisition, spec)}
          </Typography>
        </Box>
      ))}

      <Dialog open={open} onClose={() => !saving && setOpen(false)} fullWidth maxWidth="sm">
        <DialogTitle>Acquisition settings</DialogTitle>
        <DialogContent sx={{ display: "flex", flexDirection: "column", gap: 2, pt: "8px !important" }}>
          {ACQUISITION_FIELDS.map((spec) => (
            <TextField
              key={spec.key}
              label={spec.label}
              size="small"
              value={draft[spec.key] ?? ""}
              onChange={(e) => setDraft((d) => ({ ...d, [spec.key]: e.target.value }))}
              error={invalidNumbers.includes(spec.key)}
              helperText={invalidNumbers.includes(spec.key) ? "Enter a number" : spec.help}
              slotProps={{
                htmlInput: spec.kind === "number" ? { inputMode: "decimal" } : undefined,
                input: spec.unit
                  ? { endAdornment: <InputAdornment position="end">{spec.unit}</InputAdornment> }
                  : undefined,
              }}
            />
          ))}
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setOpen(false)} disabled={saving}>
            Cancel
          </Button>
          <Button variant="contained" onClick={handleSave} disabled={saving || invalidNumbers.length > 0}>
            {saving ? "Saving..." : "Save"}
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}
