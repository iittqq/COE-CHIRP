import { ungzip } from "pako";

// Replaces Dart's GZipCodec().decode(base64.decode(b64)) — the remote
// controller sends each UI-automation snapshot as a gzip+base64 XML dump.
export function decodeZippedXml(b64: string): string {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return ungzip(bytes, { toText: true });
}

export function parseXml(xml: string): Document {
  return new DOMParser().parseFromString(xml, "application/xml");
}

export function allNodes(doc: Document): Element[] {
  return Array.from(doc.getElementsByTagName("node"));
}

// Equivalent to Dart's XmlElement.toXmlString() for the self-closing
// <node .../> elements the remote controller's clickByXml/swipeByXml
// commands expect.
export function serializeNode(el: Element): string {
  const attrs = Array.from(el.attributes)
    .map(
      (a) =>
        `${a.name}="${a.value.replace(/&/g, "&amp;").replace(/"/g, "&quot;")}"`,
    )
    .join(" ");
  return `<node ${attrs} />`;
}
