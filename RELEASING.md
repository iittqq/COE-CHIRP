# Releasing and archiving on Zenodo

A Zenodo DOI turns a release into a **permanent, public, citable record that
cannot be edited or deleted**. Work through this list before tagging the first
version. Items come from the FAIR review of 2 November 2026 (section numbers
refer to that review) plus items found while addressing it.

Legend: ✅ done in the repository · 👤 needs the author · 🏛️ needs the
supervisor, LSU or the sponsor

## Before the first release (v1.0.0)

### Decisions and permissions

- [ ] 🏛️ **License (§4.1).** Confirm with LSU and the sponsor (MIT and
  BSD-3-Clause are common). Then add `LICENSE`, add `license: <SPDX id>` to
  `CITATION.cff`, and update the *License* section of the README. Until this
  is done, Zenodo would apply its own default license to the permanent record.
- [ ] 🏛️ **Repository ownership (§8.1).** Transfer the repository to the
  LSU or lab GitHub organization **before** enabling Zenodo, then update
  `repository-code` in `CITATION.cff` and the `repository` URL in
  `chirp-control-web/package.json`.
- [ ] 🏛️ **Site coordinates (§8.2).** ✅ Removed from code and screenshots
  (default is now Baton Rouge, LA). Restore the real site only if CPRA agrees.
- [ ] 🏛️ **CPRA logo (§8.3).** ✅ Removed from the web app and screenshots.
  Restore `chirp-control-web/src/assets/CPRA-LOGO.jpg` (see git history) and
  the `SideNavBar` mark only if CPRA grants permission.
- [ ] 🏛️ **Other third-party images.** Confirm source and permission, or add
  a credit line, for:
  - `chirp_control/assets/erosion.jpg`: the projected land-loss map appears
    to come from CPRA's Coastal Master Plan;
  - `chirp_control/assets/radar-sonar.svg` and
    `chirp-control-web/src/assets/radar-sonar.svg`: an icon of unknown origin.
- [ ] 👤 **Photos (§8.4).** `chirp_control/assets/system-being-used.jpeg` shows
  two identifiable people. Get their consent or crop or blur the faces.
  ✅ GPS coordinates and camera metadata were stripped from this photo and from
  `field-deployment.jpeg`; both embedded the field-site location.
- [x] ✅ **Example report (§8.5).** Checked: it is a settling-column test with
  no site name and empty notes. It predates 1.0.0. Regenerate it after
  deploying 1.0.0 so it shows the Processing and Acquisition sections.
- [x] ✅ **Stray files (§8.6).** Removed, and `.gitignore` updated so they
  can't come back.
- [ ] 👤 **Git history.** A Zenodo release archives only the tagged snapshot,
  but the GitHub repository keeps every past commit. The old coordinates,
  photo EXIF data and logo are still in the history. If they must not stay
  public on GitHub, rewrite the history (e.g. `git filter-repo`) **before**
  the transfer and before making the repository more widely known.

### Metadata

- [ ] 👤 **Authors and ORCIDs (R1.2).** Add every contributor to
  `CITATION.cff` with an ORCID and affiliation (template in the file header).
- [ ] 🏛️ **Funding.** Add the sponsor and award number to the README
  *Acknowledgments* and, via Zenodo's form or a `.zenodo.json`, to the record.
  (Without a `.zenodo.json`, Zenodo reads `CITATION.cff`. If you add one, it
  takes precedence, so keep the two consistent.)
- [ ] 👤 Validate: `pip install cffconvert && cffconvert --validate`.

### Scientific choices to confirm

- [ ] 🏛️ **Settled-depth window.** Settled depth is now the mean of the last
  **30 s** (`SETTLED_WINDOW_S` in `bathymetry.ts`, `depth_processing.dart` and
  `chirp_bathymetry.py`, and `generate.py` for the tests). Confirm the
  window, or change all four and rerun the tests.
- [ ] 🏛️ **PRO+ 2 blind-spot offset.** The settling-column notes say "an
  adjustment of 5 cm" without a sign. The software applies no correction by
  default. Once the sign is confirmed, state it in README §3 and
  `data_visualization/README.md`.

### Release mechanics

- [ ] 👤 Deploy the 1.0.0 `scan_handler.py`. The web app needs it to save
  acquisition settings.
- [ ] 👤 All tests pass (`pnpm test`, `flutter test`, `python -m pytest`), and
  so does the GitHub Actions workflow.
- [ ] 👤 Versions match the tag: `chirp-control-web/package.json` →
  `version`, `chirp_control/pubspec.yaml` → `version` (the part before `+`),
  `chirp_control/lib/utils/config.dart` → `appVersion`, `CITATION.cff` →
  `version`.
- [ ] 👤 In `CITATION.cff` set `date-released`. Move the CHANGELOG
  "unreleased" heading to the date.
- [ ] 👤 Enable the repository in Zenodo (Zenodo → GitHub → toggle on),
  **then** create the GitHub release with tag `v1.0.0`. Zenodo archives it and
  mints a version DOI plus a concept DOI for all versions.
- [ ] 👤 After Zenodo mints the DOIs: add `doi:` (concept DOI) to
  `CITATION.cff`, add the DOI badge to the top of the README (placeholder
  comment there), and fill in the *How to cite* section. Commit; the change
  ships with the next version.

## Sample dataset (§6, can follow 1.0.0)

The software DOI does not cover data, and the repository contains no real scan
data. The package for a **separate Zenodo dataset record** is built by
`data_visualization/build_sample_dataset.py` from the four settling-column
runs `scan_data_7_deg_{0,6,12,18}_cm`. These are laboratory scans with no GPS
positions, and the builder refuses any scan that has positions. A draft has
been built and checked: the raw files are byte-identical to the originals, all
checksums verify, and all four NetCDF files pass CF-1.8 at the strict level.

1. [ ] 👤 Fill in every `TODO` in `data_visualization/sample_dataset.json`:
   ORCID, data license, sonar model, sediment description, and confirmation of
   the 69 cm water height. Add the software concept DOI once the software
   release exists.
2. [ ] 👤 Build the final package (needs the raw scans in
   `data_visualization/scans/`):
   `cd data_visualization && python build_sample_dataset.py`
   → `build/sample-dataset/COE-CHIRP-settling-column-sample-1.0.0.zip`.
   Review its `README.md` and `figures/`.
3. [ ] 👤 On Zenodo: *New upload*, upload type **Dataset**. Upload the
   **contents** of the package folder (or the zip) and copy the fields from
   `metadata/zenodo.json` (title, creators, description, keywords, license,
   related identifiers). Publish.
4. [ ] 👤 Link the two records: in the software record (next version), add the
   dataset DOI as `isSupplementedBy`. The dataset record already lists the
   software as `isSupplementTo`. Add the dataset DOI to the README
   (*Repository layout* and *How to cite*) and to `CITATION.cff` `references`.

## Later versions

From the review's checklist, items 8–14:

- [x] ✅ Read CSV columns by header name, with validation (§5.1)
- [x] ✅ Show dropped points; settled depth by time window; signed depth change (§5.3–5.5)
- [x] ✅ Store acquisition metadata with every scan (§5.8)
- [ ] ISP records in the backend (§5.9). ✅ Interim: JSON export, and the
  README warns that records stay in the browser. A backend store needs a
  table, a Lambda and a migration like the one used for scans.
- [x] ✅ Real tests of the depth computations (R3)
- [x] ✅ Annotated CSV export and NetCDF (CF-1.8) export (§9.13)
- [ ] Sample dataset on Zenodo: ✅ package builder and checked draft; deposit pending (above)
