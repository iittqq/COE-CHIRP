import { jsPDF } from "jspdf";
import { toPng } from "html-to-image";

export const PDF_MARGIN = 40;

export function newReportDoc(): jsPDF {
  return new jsPDF({ unit: "pt", format: "a4" });
}

export function pageContentWidth(doc: jsPDF): number {
  return doc.internal.pageSize.getWidth() - PDF_MARGIN * 2;
}

// Starts a new page (resetting y to the top margin) if the next block
// wouldn't fit on the current one.
export function ensureSpace(doc: jsPDF, y: number, neededHeight: number): number {
  const pageHeight = doc.internal.pageSize.getHeight();
  if (y + neededHeight > pageHeight - PDF_MARGIN) {
    doc.addPage();
    return PDF_MARGIN;
  }
  return y;
}

export function addHeading(doc: jsPDF, text: string, y: number, size = 16): number {
  y = ensureSpace(doc, y, size + 10);
  doc.setFont("helvetica", "bold");
  doc.setFontSize(size);
  doc.setTextColor(17, 24, 39);
  doc.text(text, PDF_MARGIN, y);
  doc.setFont("helvetica", "normal");
  return y + size + 10;
}

export function addSubtext(doc: jsPDF, text: string, y: number): number {
  y = ensureSpace(doc, y, 16);
  doc.setFontSize(10);
  doc.setTextColor(107, 114, 128);
  doc.text(text, PDF_MARGIN, y);
  doc.setTextColor(17, 24, 39);
  return y + 20;
}

export function addLabelValueLine(doc: jsPDF, label: string, value: string, y: number): number {
  y = ensureSpace(doc, y, 16);
  doc.setFontSize(10);
  doc.setTextColor(107, 114, 128);
  doc.text(label, PDF_MARGIN, y);
  doc.setTextColor(17, 24, 39);
  doc.text(value, PDF_MARGIN + 140, y);
  return y + 16;
}

export function addWrappedText(doc: jsPDF, text: string, y: number, fontSize = 10): number {
  doc.setFontSize(fontSize);
  doc.setTextColor(17, 24, 39);
  const width = pageContentWidth(doc);
  const lines: string[] = doc.splitTextToSize(text || "—", width);
  for (const line of lines) {
    y = ensureSpace(doc, y, fontSize + 4);
    doc.text(line, PDF_MARGIN, y);
    y += fontSize + 4;
  }
  return y + 6;
}

export interface CapturedImage {
  dataUrl: string;
  width: number;
  height: number;
}

// Captures `node` at 2x pixel density. Pass a ref target that has an
// explicit CSS width (not one clipped by a scrolling ancestor) so the
// capture isn't cropped to whatever's currently scrolled into view - see
// DepthLineChart's chartBodyRef/yAxisPanelRef.
export async function captureNode(node: HTMLElement | null): Promise<CapturedImage | null> {
  if (!node) return null;
  const dataUrl = await toPng(node, { pixelRatio: 2, backgroundColor: "#ffffff" });
  return { dataUrl, width: node.offsetWidth, height: node.offsetHeight };
}

// Lays out captured images left-to-right (e.g. a fixed y-axis panel next to
// the scrollable chart body it belongs with), scaled down together to fit
// the page width so they stay proportional to each other.
export function addImagesInRow(
  doc: jsPDF,
  images: (CapturedImage | null)[],
  y: number,
): number {
  const valid = images.filter((img): img is CapturedImage => !!img);
  if (valid.length === 0) return y;

  const totalNativeWidth = valid.reduce((sum, img) => sum + img.width, 0);
  const nativeHeight = Math.max(...valid.map((img) => img.height));
  const maxWidth = pageContentWidth(doc);
  const scale = Math.min(1, maxWidth / totalNativeWidth);
  const drawHeight = nativeHeight * scale;

  y = ensureSpace(doc, y, drawHeight + 16);
  let x = PDF_MARGIN;
  for (const img of valid) {
    const w = img.width * scale;
    const h = img.height * scale;
    doc.addImage(img.dataUrl, "PNG", x, y, w, h);
    x += w;
  }
  return y + drawHeight + 20;
}
