import { useState, type FormEvent } from "react";
import { Box, Button, IconButton, InputAdornment, Paper, TextField, Typography } from "@mui/material";
import VisibilityRoundedIcon from "@mui/icons-material/VisibilityRounded";
import VisibilityOffRoundedIcon from "@mui/icons-material/VisibilityOffRounded";
import SensorsRoundedIcon from "@mui/icons-material/SensorsRounded";
import { loginAccount, registerAccount, resetPassword, setSession, type AccountSession } from "../utils/auth";

interface AuthScreenProps {
  onAuthenticated: (session: AccountSession) => void;
}

type Mode = "login" | "register" | "reset";

export default function AuthScreen({ onAuthenticated }: AuthScreenProps) {
  const [mode, setMode] = useState<Mode>("login");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const isRegister = mode === "register";
  const isReset = mode === "reset";
  const needsConfirm = isRegister || isReset;

  const switchMode = (next: Mode) => {
    setMode(next);
    setError(null);
    setPassword("");
    setConfirmPassword("");
  };

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);

    const trimmedEmail = email.trim();
    if (!trimmedEmail || !password) {
      setError("Enter an email and password.");
      return;
    }
    if (needsConfirm && password !== confirmPassword) {
      setError("Passwords don't match.");
      return;
    }

    setSubmitting(true);
    try {
      const session = isRegister
        ? await registerAccount(trimmedEmail, password)
        : isReset
          ? await resetPassword(trimmedEmail, password)
          : await loginAccount(trimmedEmail, password);
      setSession(session);
      onAuthenticated(session);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Box
      sx={{
        minHeight: "100dvh",
        width: "100%",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        bgcolor: "#F5F6FA",
        px: 2,
      }}
    >
      <Paper
        elevation={0}
        sx={{
          width: "100%",
          maxWidth: 400,
          p: 4,
          borderRadius: "16px",
          border: "1px solid #E5E7EB",
          boxShadow: "0 4px 10px rgba(0,0,0,0.04)",
        }}
      >
        <Box sx={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 1, mb: 3 }}>
          <Box
            sx={{
              width: 56,
              height: 56,
              borderRadius: "50%",
              bgcolor: "#EFF6FF",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
            }}
          >
            <SensorsRoundedIcon sx={{ color: "primary.main", fontSize: 28 }} />
          </Box>
          <Typography sx={{ fontSize: 22, fontWeight: 700, color: "#111827" }}>
            {isReset ? "Reset Password" : isRegister ? "Create Account" : "Welcome Back"}
          </Typography>
          <Typography sx={{ fontSize: 13, color: "text.secondary", textAlign: "center" }}>
            {isReset
              ? "Enter your email and a new password."
              : isRegister
                ? "Sign up to register and manage your sonars."
                : "Log in to access your registered sonars."}
          </Typography>
        </Box>

        <Box component="form" onSubmit={handleSubmit} sx={{ display: "flex", flexDirection: "column", gap: 2 }}>
          <TextField
            label="Email"
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            autoComplete="email"
            fullWidth
            autoFocus
          />
          <TextField
            label={isReset ? "New Password" : "Password"}
            type={showPassword ? "text" : "password"}
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            autoComplete={needsConfirm ? "new-password" : "current-password"}
            fullWidth
            slotProps={{
              input: {
                endAdornment: (
                  <InputAdornment position="end">
                    <IconButton onClick={() => setShowPassword((v) => !v)} edge="end" size="small">
                      {showPassword ? <VisibilityOffRoundedIcon /> : <VisibilityRoundedIcon />}
                    </IconButton>
                  </InputAdornment>
                ),
              },
            }}
          />
          {needsConfirm && (
            <TextField
              label="Confirm Password"
              type={showPassword ? "text" : "password"}
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
              autoComplete="new-password"
              fullWidth
            />
          )}

          {error && (
            <Typography sx={{ color: "error.main", fontSize: 13, fontWeight: 600 }}>
              {error}
            </Typography>
          )}

          <Button
            type="submit"
            variant="contained"
            size="large"
            disabled={submitting}
            sx={{ height: 48, fontSize: 15, mt: 1 }}
          >
            {submitting
              ? "Please wait..."
              : isReset
                ? "Reset Password"
                : isRegister
                  ? "Create Account"
                  : "Log In"}
          </Button>
        </Box>

        {mode === "login" && (
          <Box sx={{ display: "flex", justifyContent: "center", mt: 2 }}>
            <Typography
              onClick={() => switchMode("reset")}
              sx={{ fontSize: 13, color: "primary.main", fontWeight: 700, cursor: "pointer" }}
            >
              Forgot password?
            </Typography>
          </Box>
        )}

        <Box sx={{ display: "flex", justifyContent: "center", gap: 0.5, mt: mode === "login" ? 1 : 3 }}>
          <Typography sx={{ fontSize: 13, color: "text.secondary" }}>
            {isRegister
              ? "Already have an account?"
              : isReset
                ? "Remembered your password?"
                : "Don't have an account?"}
          </Typography>
          <Typography
            onClick={() => switchMode(isRegister ? "login" : isReset ? "login" : "register")}
            sx={{ fontSize: 13, color: "primary.main", fontWeight: 700, cursor: "pointer" }}
          >
            {isRegister || isReset ? "Log In" : "Create Account"}
          </Typography>
        </Box>
      </Paper>
    </Box>
  );
}
