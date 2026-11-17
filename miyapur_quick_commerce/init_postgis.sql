-- 1. Enable PostGIS Extension
CREATE EXTENSION IF NOT EXISTS postgis;

-- 2. Store Table with Spatial Geometry
CREATE TABLE IF NOT EXISTS stores (
    id UUID PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    geom geometry(Point, 4326),
    delivery_radius_meters INTEGER DEFAULT 10000,
    is_active BOOLEAN DEFAULT TRUE
);

-- 3. GIST Spatial Index for Ultra-Fast Sub-2ms Radius Lookups
CREATE INDEX IF NOT EXISTS idx_stores_geom ON stores USING GIST (geom);

-- 4. Seed Miyapur Central Dark Store Hub
INSERT INTO stores (id, name, latitude, longitude, geom, delivery_radius_meters, is_active)
VALUES (
    '9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d',
    'Miyapur Central Dark Store Hub (Metro Pillar 84)',
    17.495101,
    78.367535,
    ST_SetSRID(ST_MakePoint(78.367535, 17.495101), 4326),
    10000,
    TRUE
)
ON CONFLICT (id) DO NOTHING;
