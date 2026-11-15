-- DESIGN ONLY: NOT EXECUTED. No Cassandra server was used.
-- Wide-column model for Konga shipment tracking events (the relational table is konga.shipment_events; its UUID text ids map to the Cassandra uuid type).
-- Design rule for column-family stores: start from the queries, then build one table per query.

-- Query 1: "show the tracking timeline of shipment X, newest first"
CREATE TABLE konga.events_by_shipment (
    shipment_id  uuid,
    event_time   timestamp,
    status       text,          -- same values as the relational status: shipped, in_transit, delivered, failed, returned
    location     text,
    description  text,
    PRIMARY KEY ((shipment_id), event_time)       -- partition key = shipment, clustering key = time
) WITH CLUSTERING ORDER BY (event_time DESC);

-- Query 2: "all events at a hub today" (operations dashboard). Bucketed by day so a partition never grows without limit.
CREATE TABLE konga.events_by_hub_day (
    hub          text,
    day          date,
    event_time   timeuuid,
    shipment_id  uuid,
    status       text,
    PRIMARY KEY ((hub, day), event_time)
) WITH CLUSTERING ORDER BY (event_time DESC)
  AND default_time_to_live = 7776000;              -- keep 90 days

-- The application writes each event to BOTH tables (denormalisation instead of joins).
-- Consistency: writes at LOCAL_QUORUM, reads at LOCAL_QUORUM gives read-your-writes while tolerating one replica down.
-- Replication: NetworkTopologyStrategy with 3 replicas per data centre.
