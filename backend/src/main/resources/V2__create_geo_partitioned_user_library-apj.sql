/*
 Create PostgreSQL tablespaces for the US East, Central and West regions.
 The region names in the tablespaces definition correspond to the names of the regions
 that you selected for the database nodes in the previous chapter of the tutorial.
 As a result, data belonging to a specific tablespace will be stored on database nodes from the same region.
 */
CREATE TABLESPACE asia_ne_ts WITH (
    replica_placement = '{"num_replicas": 1, "placement_blocks":
    [{"cloud":"gcp","region":"asia-northeast1","zone":"asia-northeast1-a","min_num_replicas":1}]}'
);

CREATE TABLESPACE asia_s_ts WITH (
    replica_placement = '{"num_replicas": 1, "placement_blocks":
    [{"cloud":"gcp","region":"asia-south1","zone":"asia-south1-a","min_num_replicas":1}]}'
);

CREATE TABLESPACE asia_se_ts WITH (
    replica_placement = '{"num_replicas": 1, "placement_blocks":
    [{"cloud":"gcp","region":"asia-southeast1","zone":"asia-southeast1-a","min_num_replicas":1}]}'
);


/*
 For the demo purpose, drop the existing table.
 In a production environment, you can use one of the techniques to move data between old and new tables.
 */
DROP TABLE user_library;


/*
 Create a geo-partitioned version of the table partitioning the data by the "user_location" column.
 */
CREATE TABLE user_library(
    user_id uuid NOT NULL,
    movie_id integer NOT NULL,
    start_watch_time int NOT NULL DEFAULT 0,
    added_time timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    user_location text
)
PARTITION BY LIST (user_location);


/*
 Create partitions for each cloud region mapping the values of the "user_location" column
 to a respective geo-aware tablespace.
 */
CREATE TABLE user_library_asia_ne PARTITION OF user_library(user_id, movie_id, start_watch_time, added_time, user_location, PRIMARY KEY (user_id, movie_id, user_location))
FOR VALUES IN ('Tokyo', 'Osaka') TABLESPACE asia_ne_ts;

CREATE TABLE user_library_asia_s PARTITION OF user_library(user_id, movie_id, start_watch_time, added_time, user_location, PRIMARY KEY (user_id, movie_id, user_location))
FOR VALUES IN ( 'Ayodhya', 'Bengaluru', 'Chennai', 'Delhi', 'Hyderabad','Mumbai') TABLESPACE asia_s_ts;

CREATE TABLE user_library_asia_se PARTITION OF user_library(user_id, movie_id, start_watch_time, added_time, user_location, PRIMARY KEY (user_id, movie_id, user_location))
FOR VALUES IN ('Singapore', 'Kuala Lumpur') TABLESPACE asia_se_ts;

CREATE TABLE user_library_default PARTITION OF user_library(user_id, movie_id, start_watch_time, added_time, user_location, PRIMARY KEY (user_id, movie_id, user_location))
DEFAULT;

INSERT INTO user_account(id, email, PASSWORD, full_name, user_location)
    VALUES ('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'user1@gmail.com', '$2a$10$s17IziaW1967UZGW/Q8diOqX0qCzABGBykf/BK6xvO/qElLKkWV6a', 'John Doe', 'Tokyo'),
('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a12', 'user2@gmail.com', '$2a$10$s17IziaW1967UZGW/Q8diOqX0qCzABGBykf/BK6xvO/qElLKkWV6a', 'Emely Smith', 'Chennai'),
('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a13', 'user3@gmail.com', '$2a$10$s17IziaW1967UZGW/Q8diOqX0qCzABGBykf/BK6xvO/qElLKkWV6a', 'Michael Williams', 'Singapore'),
('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a14', 'user4@gmail.com', '$2a$10$s17IziaW1967UZGW/Q8diOqX0qCzABGBykf/BK6xvO/qElLKkWV6a', 'Jessica Brown', 'Mumbai'),




WITH user_data AS (
    SELECT
        id,
        user_location
    FROM
        user_account
    WHERE
        email = 'user2@gmail.com')
INSERT INTO user_library(user_id, movie_id, start_watch_time, added_time, user_location)
SELECT
    (
        SELECT
            id
        FROM
            user_data),
    id,
    0,
    CURRENT_TIMESTAMP,
(
        SELECT
            user_location
        FROM
            user_data)
FROM
    movie
WHERE
    id IN (
        SELECT
            id
        FROM
            movie
        ORDER BY
            RANDOM()
        LIMIT 3);

WITH user_data AS (
    SELECT
        id,
        user_location
    FROM
        user_account
    WHERE
        email = 'user3@gmail.com')
INSERT INTO user_library(user_id, movie_id, start_watch_time, added_time, user_location)
SELECT
    (
        SELECT
            id
        FROM
            user_data),
    id,
    0,
    CURRENT_TIMESTAMP,
(
        SELECT
            user_location
        FROM
            user_data)
FROM
    movie
WHERE
    id IN (
        SELECT
            id
        FROM
            movie
        ORDER BY
            RANDOM()
        LIMIT 3);

WITH user_data AS (
    SELECT
        id,
        user_location
    FROM
        user_account
    WHERE
        email = 'user4@gmail.com')
INSERT INTO user_library(user_id, movie_id, start_watch_time, added_time, user_location)
SELECT
    (
        SELECT
            id
        FROM
            user_data),
    id,
    0,
    CURRENT_TIMESTAMP,
(
        SELECT
            user_location
        FROM
            user_data)
FROM
    movie
WHERE
    id IN (
        SELECT
            id
        FROM
            movie
        ORDER BY
            RANDOM()
        LIMIT 3);
