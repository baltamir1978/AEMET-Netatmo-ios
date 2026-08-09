#!/usr/bin/env python3
"""Genera AppPersonal/Nucleos.tsv: el nomenclátor de núcleos de población de España.

Por qué existe: el geocodificador de Apple sólo llega al municipio. En todo el
concejo de Llanes devuelve "Llanes" y `subLocality` nil, así que Posada de Llanes,
Niembro y la villa son indistinguibles (sólo cambia el código postal). Este fichero
aporta los núcleos que faltan, y `Nomenclator.swift` busca el más cercano.

Fuente: GeoNames (https://download.geonames.org/export/dump/ES.zip), CC BY 4.0.
La atribución vive en el README y en la pantalla de fuentes de la app.

Uso:
    python3 Tools/build_nomenclator.py [ES.txt]

Sin argumento se descarga el dump. Salida: AppPersonal/Nucleos.tsv, ordenado por
latitud (Nomenclator.swift acota por bandas de latitud antes de medir).
"""

import io
import os
import sys
import urllib.request
import zipfile

DUMP_URL = "https://download.geonames.org/export/dump/ES.zip"

# Sólo lugares habitados de verdad. Fuera quedan los que ensuciarían el resultado:
# PPLQ (despoblado), PPLW (destruido), PPLH (histórico), PPLF (granja), PPLR
# (religioso), PPLS (conjunto de lugares) y PPLX (secciones de ciudad: los barrios
# los pone MapKit, que en las ciudades grandes acierta y va sin coste de bundle).
KEEP = {"PPL", "PPLA", "PPLA2", "PPLA3", "PPLA4", "PPLC", "PPLL"}

# Columnas del dump (geonames readme.txt)
NAME, LAT, LON, FCLASS, FCODE, ADMIN3 = 1, 4, 5, 6, 7, 12


def load_dump(path=None):
    if path:
        with open(path, encoding="utf-8") as fh:
            yield from fh
        return
    print(f"Descargando {DUMP_URL} …", file=sys.stderr)
    with urllib.request.urlopen(DUMP_URL) as resp:
        blob = resp.read()
    with zipfile.ZipFile(io.BytesIO(blob)) as zf:
        with zf.open("ES.txt") as fh:
            yield from io.TextIOWrapper(fh, encoding="utf-8")


def build(rows):
    out = []
    for line in rows:
        f = line.rstrip("\n").split("\t")
        if len(f) < 15 or f[FCLASS] != "P" or f[FCODE] not in KEEP:
            continue
        name = f[NAME].strip()
        ine = f[ADMIN3].strip()
        # El código INE de municipio (admin3) ancla cada núcleo a su municipio, que
        # es como AEMET indexa su catálogo: así el núcleo mostrado nunca puede saltar
        # al pueblo de un municipio vecino. Lo trae el 99% de las entradas; el resto
        # se queda sin ancla y sólo puede casar por distancia.
        if not (len(ine) == 5 and ine.isdigit()):
            ine = ""
        if not name or "\t" in name:
            continue
        # 4 decimales ≈ 11 m: de sobra para elegir el núcleo más cercano, y recorta
        # un tercio del fichero frente a la precisión completa del dump.
        out.append((float(f[LAT]), float(f[LON]), ine, name))
    out.sort(key=lambda r: r[0])
    return out


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else None
    rows = build(load_dump(src))
    if len(rows) < 20000:
        sys.exit(f"Sólo {len(rows)} núcleos: el dump parece incompleto, no piso el fichero bueno.")
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    # Vive en el target de la app, no en Shared/: el widget no resuelve GPS (lee el
    # `resolvedCurrent` ya calculado del App Group), así que no necesita cargar con
    # el megabyte del nomenclátor.
    dest = os.path.join(root, "AppPersonal", "Nucleos.tsv")
    with open(dest, "w", encoding="utf-8") as fh:
        for lat, lon, ine, name in rows:
            fh.write(f"{lat:.4f}\t{lon:.4f}\t{ine}\t{name}\n")
    size = os.path.getsize(dest)
    print(f"{len(rows)} núcleos → {dest} ({size / 1024:.0f} KB)")


if __name__ == "__main__":
    main()
