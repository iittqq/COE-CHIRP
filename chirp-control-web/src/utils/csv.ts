// CSV parsing with no side effects or app configuration, so it can be used
// (and tested) without a backend. scanRepo.ts re-exports these.

export type CsvCell = string | number;
export type CsvRow = CsvCell[];

// Splits on newlines and commas (the vendor exports never quote fields).
// Numeric cells become numbers; blank cells stay "". Lines starting with "#"
// are comments (used by the annotated CSV export for its metadata block).
export function parseCsv(text: string): CsvRow[] {
  return text
    .split(/\r?\n/)
    .filter((line) => line.trim().length > 0 && !line.trimStart().startsWith("#"))
    .map((line) =>
      line.split(",").map((cell) => {
        const trimmed = cell.trim();
        if (trimmed === "") return trimmed;
        const num = Number(trimmed);
        return Number.isNaN(num) ? trimmed : num;
      }),
    );
}
