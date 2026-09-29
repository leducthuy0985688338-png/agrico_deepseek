# AGRICO v2 — Land Parcel, Measurement & Google Earth Contract

Status: APPROVED

## Goal

Use one canonical land-boundary model for AGRICO GPS measurement, Google Earth interoperability and future GeoCAD Bridge/CAD exchange without coupling AGRICO to CAD implementation details.

## Canonical coordinate model

- Stored boundary CRS: WGS84 / EPSG:4326.
- Coordinate order in domain code is explicit: latitude, longitude. Serializers must explicitly map formats that use longitude,latitude (including KML coordinates).
- Polygon exterior ring must be closed for interchange/storage validation.
- Area and perimeter are derived values; the canonical geometry remains the source of truth.
- Derived area/perimeter calculations must use a geodesic or locally appropriate projected calculation rather than treating latitude/longitude degrees as metres.

## LandParcel

Required identity/relationship fields:
- id
- farmId
- parcelCode
- name
- ownerHouseholdId? / ownerDisplayName?
- active
- createdAt / createdBy
- updatedAt / updatedBy
- schemaVersion

Boundary fields:
- boundary: ordered WGS84 vertices
- centroid: WGS84 coordinate
- areaM2
- areaHa
- perimeterM
- boundarySource
- horizontalAccuracyM?
- measuredAt?
- measuredBy?
- verificationStatus
- boundaryConfidence?
- boundaryVersion

BoundarySource enum:
- gps
- googleEarth
- manual
- cad
- imported

VerificationStatus enum:
- draft
- measured
- verified
- rejected

## Boundary version history

Every accepted geometry change creates an immutable LandParcelBoundaryVersion containing:
- id, parcelId, version
- boundary + derived metrics
- source
- accuracy metadata
- captured/imported timestamp
- actor
- note
- source file metadata where applicable

Restoring an older version creates a new version; history is never rewritten.

## GPS measurement workflow

Start measurement -> capture ordered GPS points -> quality checks -> preview polygon -> calculate geodesic area/perimeter/centroid -> user confirms -> persist local transaction -> create boundary version -> enqueue cloud sync.

Quality checks include:
- minimum 3 distinct vertices;
- closed polygon;
- no invalid coordinates;
- reject/flag self-intersection;
- accuracy warning when device accuracy is poor;
- prevent accidental replacement of a verified boundary without required permission/confirmation.

## Google Earth interoperability

### Export

LandParcel -> KML 2.2 Polygon using WGS84 coordinates.

Export must preserve AGRICO metadata in ExtendedData where practical:
- parcel ID/code/name
- farm ID
- area/perimeter
- source/version
- verification status
- timestamps

KMZ is a packaging option over generated KML and related assets.

### Import

KML/KMZ -> parse Placemark Polygon/MultiGeometry -> normalize WGS84 -> validate -> preview -> choose create parcel or update existing parcel -> permission check -> persist as a new boundary version with source=googleEarth/imported.

Import never silently overwrites an existing verified boundary.

Initial integration scope:
1. Import KML/KMZ.
2. Export KML/KMZ.
3. Open/share exported file with Google Earth when the platform supports an external handler.

Embedding Google Earth itself inside AGRICO is explicitly outside the first integration milestone.

## GeoCAD Bridge compatibility

AGRICO owns agricultural parcel semantics and canonical WGS84 geometry. GeoCAD Bridge may transform the same geometry to projected CRS/UTM and CAD formats. Future interchange should preserve stable parcel IDs and metadata so the chain can be:

AGRICO <-> Google Earth <-> GeoCAD Bridge <-> AutoCAD

## Permissions

- field.view
- field.create
- field.edit
- field.delete
- field.measure
- field.boundary.view_history
- field.boundary.edit
- field.boundary.verify
- field.google_earth.import
- field.google_earth.export

Permissions are combined with data scope (farm/team/assigned fields/own where applicable).

## Localization

All system UI/messages/errors/actions for measurement and Google Earth import/export require vi, lo and en keys. Parcel names, owner names, notes and imported user content remain as entered.

## Persistence/sync requirements

Local and Cloud schemas must store schemaVersion. Boundary history is synced as first-class data. Full Cloud Restore must restore parcels before boundary history and validate history parcel links. Empty/invalid cloud groups must not erase valid local parcel/history data.

## Test contract

At minimum:
- WGS84 coordinate serialization round trip;
- polygon closure/validation;
- area/perimeter derivation tolerance tests;
- KML export/import round trip;
- KML longitude/latitude ordering test;
- malformed KML rejection;
- MultiGeometry handling;
- duplicate/version handling;
- permission enforcement;
- verified-boundary overwrite protection;
- local-first persistence and cloud retry;
- full restore dependency/link validation;
- vi/lo/en localization key coverage.
