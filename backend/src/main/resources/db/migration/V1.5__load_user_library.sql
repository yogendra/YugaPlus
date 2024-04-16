

-- Add three movies from the movie table

WITH
  movies AS ( select id from movie ORDER BY RANDOM() LIMIT 3),
  user_data AS ( SELECT id, user_location FROM user_account)
INSERT INTO user_library(user_id, movie_id, start_watch_time, added_time, user_location)
SELECT
    u.id,
    m.id,
    0 ,
    CURRENT_TIMESTAMP,
    u.user_location
FROM
    movies m,  user_data u;
