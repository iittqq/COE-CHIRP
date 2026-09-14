import ExcelJS from "exceljs";
import { addIspRecord, type IspCell, type IspRecord } from "./ispRepo";
import { getSession } from "./auth";

function cellToValue(value: ExcelJS.CellValue): IspCell {
  if (value === null || value === undefined) return null;
  if (value instanceof Date) return value.toISOString();
  if (typeof value === "object") {
    if ("result" in value) {
      return cellToValue((value as ExcelJS.CellFormulaValue).result ?? null);
    }
    if ("richText" in value) {
      return (value as ExcelJS.CellRichTextValue).richText.map((t) => t.text).join("");
    }
    if ("text" in value) return String((value as { text: unknown }).text);
    return String(value);
  }
  return typeof value === "boolean" ? String(value) : value;
}

function headerLabel(cell: IspCell, index: number): string {
  return cell === null || cell === "" ? `Column ${index + 1}` : String(cell);
}

function parseCsvText(text: string): { headers: string[]; rows: IspCell[][] } {
  const lines = text.split(/\r?\n/).filter((line) => line.trim().length > 0);
  if (lines.length === 0) return { headers: [], rows: [] };

  const parseLine = (line: string): IspCell[] =>
    line.split(",").map((cell) => {
      const trimmed = cell.trim();
      if (trimmed === "") return null;
      const num = Number(trimmed);
      return Number.isNaN(num) ? trimmed : num;
    });

  const headers = parseLine(lines[0]).map(headerLabel);
  const rows = lines.slice(1).map(parseLine);
  return { headers, rows };
}

async function parseXlsxWorkbook(
  file: File,
): Promise<{ sheetName: string; headers: string[]; rows: IspCell[][] }> {
  const buffer = await file.arrayBuffer();
  const workbook = new ExcelJS.Workbook();
  await workbook.xlsx.load(buffer);

  const worksheet = workbook.worksheets[0];
  if (!worksheet) throw new Error("Workbook has no sheets");

  const allRows: IspCell[][] = [];
  worksheet.eachRow({ includeEmpty: false }, (row) => {
    const values = (row.values as ExcelJS.CellValue[]).slice(1).map(cellToValue);
    allRows.push(values);
  });

  if (allRows.length === 0) return { sheetName: worksheet.name, headers: [], rows: [] };

  const [headerRow, ...dataRows] = allRows;
  const headers = headerRow.map(headerLabel);
  const rows = dataRows.filter((row) => row.some((cell) => cell !== null && cell !== ""));

  return { sheetName: worksheet.name, headers, rows };
}

// Same identifying name a re-import of the same file would produce, so it
// can be checked against existing records (via ispRepo's
// findIspRecordByFileName) before actually reading/importing it.
export function deriveFileName(fileName: string): string {
  return fileName || `isp_${Date.now()}`;
}

export async function parseIspWorkbook(
  file: File,
): Promise<{ sheetName: string; headers: string[]; rows: IspCell[][] }> {
  if (/\.csv$/i.test(file.name)) {
    const text = await file.text();
    return { sheetName: "Sheet1", ...parseCsvText(text) };
  }
  if (/\.xls$/i.test(file.name)) {
    throw new Error("Legacy .xls files aren't supported — please re-save as .xlsx or .csv");
  }
  return parseXlsxWorkbook(file);
}

export async function importIspFile(
  file: File,
  options?: { overwriteId?: string },
): Promise<IspRecord> {
  const { sheetName, headers, rows } = await parseIspWorkbook(file);

  if (headers.length === 0) {
    throw new Error("Spreadsheet did not contain any data");
  }

  return addIspRecord({
    fileName: deriveFileName(file.name),
    sheetName,
    headers,
    rows,
    userId: getSession()?.user_id,
    overwriteId: options?.overwriteId,
  });
}
