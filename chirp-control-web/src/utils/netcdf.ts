// Minimal writer for the NetCDF classic format (CDF-1), the most widely
// readable NetCDF variant (netCDF-C/4-python, xarray, MATLAB, R, Panoply, ...).
// Supports fixed-size dimensions, global and variable attributes, and
// variables of type char, short, int and double. No record (unlimited)
// dimension. Format specification:
// https://docs.unidata.ucar.edu/netcdf-c/current/file_format_specifications.html

export type NcType = "char" | "short" | "int" | "double";
export type NcAttrValue = string | number | number[];

export interface NcDimension {
  name: string;
  size: number; // must be >= 1 (0 would make it the record dimension)
}

export interface NcVariable {
  name: string;
  type: Exclude<NcType, "char">;
  dims: string[]; // [] for a scalar
  attrs?: Record<string, NcAttrValue>;
  data: ArrayLike<number>; // row-major, length = product of dim sizes
}

export interface NcFile {
  dims: NcDimension[];
  attrs: Record<string, NcAttrValue>;
  vars: NcVariable[];
}

const TYPE_CODE: Record<NcType, number> = { char: 2, short: 3, int: 4, double: 6 };
const TYPE_SIZE: Record<NcType, number> = { char: 1, short: 2, int: 4, double: 8 };
const NC_DIMENSION = 0x0a;
const NC_VARIABLE = 0x0b;
const NC_ATTRIBUTE = 0x0c;

const pad4 = (n: number) => (4 - (n % 4)) % 4;
const encoder = new TextEncoder();

class ByteWriter {
  private chunks: Uint8Array[] = [];
  length = 0;

  bytes(b: Uint8Array) {
    this.chunks.push(b);
    this.length += b.length;
  }
  int32(v: number) {
    const b = new Uint8Array(4);
    new DataView(b.buffer).setInt32(0, v, false);
    this.bytes(b);
  }
  padding(n: number) {
    if (n > 0) this.bytes(new Uint8Array(n));
  }
  name(s: string) {
    const b = encoder.encode(s);
    this.int32(b.length);
    this.bytes(b);
    this.padding(pad4(b.length));
  }
  values(type: NcType, values: ArrayLike<number>) {
    const size = TYPE_SIZE[type];
    const b = new Uint8Array(values.length * size);
    const view = new DataView(b.buffer);
    for (let i = 0; i < values.length; i++) {
      const v = values[i];
      if (type === "double") view.setFloat64(i * size, v, false);
      else if (type === "int") view.setInt32(i * size, v, false);
      else if (type === "short") view.setInt16(i * size, v, false);
      else view.setUint8(i, v);
    }
    this.bytes(b);
    this.padding(pad4(b.length));
  }
  concat(): Uint8Array {
    const out = new Uint8Array(this.length);
    let offset = 0;
    for (const c of this.chunks) {
      out.set(c, offset);
      offset += c.length;
    }
    return out;
  }
}

function writeAttrs(w: ByteWriter, attrs: Record<string, NcAttrValue> | undefined, varType?: NcType) {
  const entries = Object.entries(attrs ?? {});
  if (entries.length === 0) {
    w.int32(0); // ABSENT
    w.int32(0);
    return;
  }
  w.int32(NC_ATTRIBUTE);
  w.int32(entries.length);
  for (const [name, value] of entries) {
    w.name(name);
    if (typeof value === "string") {
      const b = encoder.encode(value);
      w.int32(TYPE_CODE.char);
      w.int32(b.length);
      w.bytes(b);
      w.padding(pad4(b.length));
    } else {
      // _FillValue, valid_min/max etc. must match the variable's type (CF).
      const type: NcType =
        varType && varType !== "char" && /^(_FillValue|valid_min|valid_max|valid_range|missing_value)$/.test(name)
          ? varType
          : "double";
      const arr = Array.isArray(value) ? value : [value];
      w.int32(TYPE_CODE[type]);
      w.int32(arr.length);
      w.values(type, arr);
    }
  }
}

export function encodeNetcdf(file: NcFile): Uint8Array {
  const dimIndex = new Map(file.dims.map((d, i) => [d.name, i]));
  for (const d of file.dims) {
    if (!Number.isInteger(d.size) || d.size < 1) {
      throw new Error(`NetCDF dimension "${d.name}" must have size >= 1`);
    }
  }
  const varSizes = file.vars.map((v) => {
    const count = v.dims.reduce((n, name) => {
      const i = dimIndex.get(name);
      if (i === undefined) throw new Error(`Unknown dimension "${name}" in variable "${v.name}"`);
      return n * file.dims[i].size;
    }, 1);
    if (v.data.length !== count) {
      throw new Error(`Variable "${v.name}" has ${v.data.length} values; expected ${count}`);
    }
    const bytes = count * TYPE_SIZE[v.type];
    return { count, vsize: bytes + pad4(bytes) };
  });

  // The header records each variable's data offset, which depends on the
  // header's own length: write it once with placeholder offsets to measure.
  const writeHeader = (begins: number[]) => {
    const w = new ByteWriter();
    w.bytes(encoder.encode("CDF"));
    w.bytes(new Uint8Array([1]));
    w.int32(0); // numrecs
    if (file.dims.length === 0) {
      w.int32(0);
      w.int32(0);
    } else {
      w.int32(NC_DIMENSION);
      w.int32(file.dims.length);
      for (const d of file.dims) {
        w.name(d.name);
        w.int32(d.size);
      }
    }
    writeAttrs(w, file.attrs);
    if (file.vars.length === 0) {
      w.int32(0);
      w.int32(0);
    } else {
      w.int32(NC_VARIABLE);
      w.int32(file.vars.length);
      file.vars.forEach((v, i) => {
        w.name(v.name);
        w.int32(v.dims.length);
        for (const d of v.dims) w.int32(dimIndex.get(d)!);
        writeAttrs(w, v.attrs, v.type);
        w.int32(TYPE_CODE[v.type]);
        w.int32(varSizes[i].vsize);
        w.int32(begins[i]);
      });
    }
    return w;
  };

  const headerLength = writeHeader(file.vars.map(() => 0)).length;
  const begins: number[] = [];
  let offset = headerLength;
  for (const s of varSizes) {
    begins.push(offset);
    offset += s.vsize;
  }
  if (offset > 2 ** 31 - 1) throw new Error("NetCDF classic files are limited to 2 GiB");

  const w = writeHeader(begins);
  file.vars.forEach((v) => w.values(v.type, v.data));
  return w.concat();
}
